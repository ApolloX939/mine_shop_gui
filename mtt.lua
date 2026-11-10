-- Integration tests, run inside the real engine by the `mtt` mod.
-- See AGENTS.md ("Testing and running") for how to start them.

local api = mine_shop_gui.currency

-- Fake players from fakelib, visible to core.get_player_by_name only while a
-- test runs. mtt.join_player is avoided on purpose: it fires every mod's join
-- callbacks, and some (credits) look players up through the real engine.
local fake_players = {}
local real_get_player_by_name = core.get_player_by_name
function core.get_player_by_name(name)
	return fake_players[name] or real_get_player_by_name(name)
end

local function with_player(name, fn)
	local player = fakelib.create_player({ name = name })
	fake_players[name] = player
	local inv = player:get_inventory()
	inv:set_size("main", 32)
	local ok, err = xpcall(function() fn(player, inv) end, debug.traceback)
	fake_players[name] = nil
	if not ok then error(err, 0) end
end

local function count_value(inv, values)
	local total = 0
	for _, stack in ipairs(inv:get_list("main")) do
		total = total + (values[stack:get_name()] or 0) * stack:get_count()
	end
	return total
end

local function used_slots(inv)
	local n = 0
	for _, stack in ipairs(inv:get_list("main")) do
		if not stack:is_empty() then n = n + 1 end
	end
	return n
end

-- Account balances persist in the world between runs, so every test that
-- uses one starts by resetting it.
local function reset_credits(name, digital)
	credits.add_coin(name, -credits.get_balance_digital(name))
	if digital and digital > 0 then credits.add_coin(name, digital) end
end

local function use(name)
	local adapter = assert(api.adapters[name], "no adapter " .. name)
	assert(adapter.available(), "adapter not available: " .. name)
	api.active = adapter
	return adapter
end

---------------------------------------------------------------- selection

mtt.register("currency: auto selection picks currency first", function(callback)
	core.settings:set("mine_shop_gui_currency", "auto")
	assert(api.resolve().name == "currency")
	callback()
end)

mtt.register("currency: unavailable explicit choice falls back to auto", function(callback)
	core.settings:set("mine_shop_gui_currency", "nonexistent")
	assert(api.resolve().name == "currency")
	core.settings:set("mine_shop_gui_currency", "auto")
	callback()
end)

---------------------------------------------------------------- currency (Minegeld)

local CENTS = {
	["currency:minegeld_cent_5"] = 5, ["currency:minegeld_cent_10"] = 10,
	["currency:minegeld_cent_25"] = 25, ["currency:minegeld"] = 100,
	["currency:minegeld_5"] = 500, ["currency:minegeld_10"] = 1000,
	["currency:minegeld_50"] = 5000, ["currency:minegeld_100"] = 10000,
}

mtt.register("currency: rounding and formatting", function(callback)
	local c = use("currency")
	assert(c.round(3) == 5)
	assert(c.round(2) == 0)
	assert(c.round(12) == 10)
	assert(c.format(12345) == "123.45")
	callback()
end)

mtt.register("currency: pay with a big note and get change", function(callback)
	local c = use("currency")
	with_player("shop_alice", function(_, inv)
		inv:add_item("main", ItemStack("currency:minegeld_100"))
		assert(c.balance("shop_alice") == 10000)
		assert(c.withdraw("shop_alice", 100) == true)
		assert(count_value(inv, CENTS) == 9900)
		-- 99.00 = 50 + 4x10 + 5 + 4x1
		assert(used_slots(inv) == 4, "slots used: " .. used_slots(inv))
	end)
	callback()
end)

mtt.register("currency: invalid and unaffordable payments change nothing", function(callback)
	local c = use("currency")
	with_player("shop_bob", function(_, inv)
		inv:add_item("main", ItemStack("currency:minegeld_10 2"))
		local function fails(amount, reason)
			local ok, why = c.withdraw("shop_bob", amount)
			assert(ok == false and why == reason,
				"amount " .. tostring(amount) .. " gave " .. tostring(why))
			assert(count_value(inv, CENTS) == 2000)
		end
		fails(3, "invalid_amount")
		fails(-5, "invalid_amount")
		fails(1.5, "invalid_amount")
		fails("5", "invalid_amount")
		fails(5000, "insufficient_funds")
	end)
	callback()
end)

mtt.register("currency: pay exactly everything, then deposit", function(callback)
	local c = use("currency")
	with_player("shop_carol", function(_, inv)
		inv:add_item("main", ItemStack("currency:minegeld_5 3"))
		assert(c.withdraw("shop_carol", 1500) == true)
		assert(count_value(inv, CENTS) == 0)
		assert(c.deposit("shop_carol", 135) == true)
		assert(count_value(inv, CENTS) == 135)
		local ok, why = c.deposit("shop_carol", 7)
		assert(ok == false and why == "invalid_amount")
	end)
	callback()
end)

mtt.register("currency: bundles are not money", function(callback)
	local c = use("currency")
	with_player("shop_dave", function(_, inv)
		inv:add_item("main", ItemStack("currency:minegeld_bundle 3"))
		assert(c.balance("shop_dave") == 0)
	end)
	callback()
end)

mtt.register("currency: change that does not fit rolls the payment back", function(callback)
	local c = use("currency")
	with_player("shop_erin", function(_, inv)
		inv:set_size("main", 1)
		inv:add_item("main", ItemStack("currency:minegeld_100"))
		local ok, why = c.withdraw("shop_erin", 100)
		assert(ok == false and why == "no_room", tostring(why))
		assert(count_value(inv, CENTS) == 10000)
		assert(inv:get_stack("main", 1):get_name() == "currency:minegeld_100")
	end)
	callback()
end)

mtt.register("currency: offline player is unavailable", function(callback)
	local c = use("currency")
	assert(c.balance("shop_nobody") == nil)
	local ok, why = c.withdraw("shop_nobody", 5)
	assert(ok == false and why == "unavailable")
	callback()
end)

---------------------------------------------------------------- item currency
-- The test config sets:
--   mine_shop_gui_item_currency = default:goldblock=9, default:gold_ingot=1

mtt.register("items: pay and make change in configured items", function(callback)
	local c = use("items")
	local values = { ["default:gold_ingot"] = 1, ["default:goldblock"] = 9 }
	with_player("shop_frank", function(_, inv)
		assert(c.deposit("shop_frank", 20) == true)
		assert(count_value(inv, values) == 20)
		assert(inv:get_stack("main", 1):get_name() == "default:goldblock",
			"slot 1 is '" .. inv:get_stack("main", 1):to_string() .. "', slot 2 is '"
			.. inv:get_stack("main", 2):to_string() .. "'")
		assert(inv:get_stack("main", 1):get_count() == 2)
		assert(c.withdraw("shop_frank", 11) == true)
		assert(count_value(inv, values) == 9)
		assert(c.round(2.6) == 3)
	end)
	callback()
end)

---------------------------------------------------------------- unified_money

mtt.register("unified_money: balance, withdraw, deposit", function(callback)
	local c = use("unified_money")
	unified_money.set_balance_safe("shop_gina", 50)
	assert(c.balance("shop_gina") == 50)
	assert(c.withdraw("shop_gina", 20) == true)
	assert(unified_money.get_balance("shop_gina") == 30)
	local ok, why = c.withdraw("shop_gina", 31)
	assert(ok == false and why == "insufficient_funds")
	assert(c.deposit("shop_gina", 5) == true)
	assert(unified_money.get_balance("shop_gina") == 35)
	ok, why = c.withdraw("shop_gina", 1.5)
	assert(ok == false and why == "invalid_amount")
	callback()
end)

mtt.register("unified_money: deposit creates a missing account", function(callback)
	local c = use("unified_money")
	unified_money.delete_account("shop_newcomer")
	assert(c.balance("shop_newcomer") == 0)
	assert(c.deposit("shop_newcomer", 7) == true)
	assert(unified_money.get_balance("shop_newcomer") == 7)
	callback()
end)

---------------------------------------------------------------- credits (V1.3 in the test world)

local function valued(inv, count, value)
	local stack = ItemStack({ name = "credits:credits", count = count })
	if value then stack:get_meta():set_int("value", value) end
	inv:add_item("main", stack)
end

mtt.register("credits: only valued stacks count (V1.3)", function(callback)
	local c = use("credits")
	assert(credits.get_balance_physical_all, "this test expects credits V1.3")
	with_player("shop_hank", function(_, inv)
		valued(inv, 1, 1000)
		inv:add_item("main", ItemStack("credits:credits_mkii 5"))
		assert(c.balance("shop_hank") == 1000)
	end)
	callback()
end)

mtt.register("credits: spend digital first, then physical, surplus returns digitally", function(callback)
	local c = use("credits")
	with_player("shop_iris", function(_, inv)
		reset_credits("shop_iris", 100)
		valued(inv, 1, 1000)
		assert(c.balance("shop_iris") == 1100)

		assert(c.withdraw("shop_iris", 60) == true)
		assert(credits.get_balance_digital("shop_iris") == 40)
		assert(inv:contains_item("main", ItemStack("credits:credits")))

		-- needs 40 digital + 260 from the 1000 stack; 740 comes back digitally
		assert(c.withdraw("shop_iris", 300) == true)
		assert(credits.get_balance_digital("shop_iris") == 740)
		assert(not inv:contains_item("main", ItemStack("credits:credits")))
		assert(c.balance("shop_iris") == 740)
	end)
	callback()
end)

mtt.register("credits: invalid and unaffordable payments change nothing", function(callback)
	local c = use("credits")
	with_player("shop_jack", function(_, inv)
		reset_credits("shop_jack", 10)
		valued(inv, 1, 5)
		local function fails(amount, reason)
			local ok, why = c.withdraw("shop_jack", amount)
			assert(ok == false and why == reason, tostring(why))
			assert(c.balance("shop_jack") == 15)
		end
		fails(16, "insufficient_funds")
		fails(1.5, "invalid_amount")
		fails(-1, "invalid_amount")
	end)
	callback()
end)

mtt.register("credits: deposit is digital", function(callback)
	local c = use("credits")
	reset_credits("shop_kim", 0)
	assert(c.deposit("shop_kim", 7) == true)
	assert(credits.get_balance_digital("shop_kim") == 7)
	callback()
end)

---------------------------------------------------------------- price scaling

mtt.register("price: currency scale, minimum buy price, refused cheap sells", function(callback)
	use("currency")
	assert(api.scale() == 5)
	assert(api.price(1, "buy") == 5)
	assert(api.price(20, "buy") == 100)
	assert(api.price(0.1, "buy") == 5, "tiny buy price is raised to the smallest coin")
	assert(api.price(0, "buy") == 0)
	assert(api.price(20, "sell") == 50, "sells for half")
	local amount, why = api.price(0.5, "sell")
	assert(amount == nil and why == "too_cheap")
	amount, why = api.price(0, "sell")
	assert(amount == nil and why == "too_cheap")
	callback()
end)

mtt.register("price: rejects bad input", function(callback)
	use("currency")
	for _, bad in ipairs({ -1, 0 / 0, math.huge, "5" }) do
		local amount, why = api.price(bad, "buy")
		assert(amount == nil and why == "invalid_amount", tostring(bad))
	end
	local amount, why = api.price(1, "trade")
	assert(amount == nil and why == "invalid_mode")
	callback()
end)

mtt.register("price: scale setting overrides the default", function(callback)
	use("currency")
	core.settings:set("mine_shop_gui_scale_currency", "10")
	local ok, err = pcall(function() assert(api.price(3, "buy") == 30) end)
	core.settings:remove("mine_shop_gui_scale_currency")
	assert(ok, err)
	assert(api.price(3, "buy") == 15)
	callback()
end)

mtt.register("price: sell ratio setting", function(callback)
	use("currency")
	core.settings:set("mine_shop_gui_sell_ratio", "1")
	local ok, err = pcall(function() assert(api.price(20, "sell") == 100) end)
	core.settings:remove("mine_shop_gui_sell_ratio")
	assert(ok, err)
	callback()
end)

mtt.register("price: credits and items use their own scales", function(callback)
	use("credits")
	assert(api.price(2.4, "buy") == 2)
	assert(api.price(0.2, "buy") == 1)
	assert(api.price(10, "sell") == 5)
	use("items")
	assert(api.price(20, "buy") == 1, "20 cobblestone is one item")
	assert(api.price(100, "buy") == 5)
	local amount, why = api.price(10, "sell")
	assert(amount == nil and why == "too_cheap", "5 units sells for less than one item")
	use("unified_money")
	assert(api.price(7, "buy") == 7)
	callback()
end)

---------------------------------------------------------------- price derivation

local derive = mine_shop_gui.pricing.derive

-- recipe(type, {{"item", count}, {group = "g", count}}, "output", output_count)
local function recipe(rtype, inputs, out_name, out_count)
	local list = {}
	for _, i in ipairs(inputs) do
		if i.group then
			list[#list + 1] = { group = i.group, count = i.count or 1 }
		else
			list[#list + 1] = { name = i[1], count = i[2] or 1 }
		end
	end
	return { type = rtype, inputs = list, output = { name = out_name, count = out_count or 1 } }
end

local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-9 end

mtt.register("derive: cost is the sum of ingredients divided by output count", function(callback)
	local prices, source = derive({
		base = { ["t:stone"] = 1, ["t:log"] = 4 },
		recipes = {
			recipe("normal", { { "t:stone", 3 } }, "t:wall"),
			recipe("normal", { { "t:log" } }, "t:plank", 4),
		},
	})
	assert(near(prices["t:wall"], 3))
	assert(near(prices["t:plank"], 1))
	assert(source["t:wall"] == "normal" and source["t:stone"] == "base")
	callback()
end)

mtt.register("derive: cheapest route wins", function(callback)
	local prices = derive({
		base = { ["t:a"] = 10, ["t:b"] = 3 },
		recipes = {
			recipe("normal", { { "t:a" } }, "t:x"),
			recipe("alloy", { { "t:b", 2 } }, "t:x"),
		},
	})
	assert(near(prices["t:x"], 6))
	callback()
end)

mtt.register("derive: base prices are never overridden", function(callback)
	local prices, source = derive({
		base = { ["t:a"] = 10, ["t:x"] = 100 },
		recipes = { recipe("normal", { { "t:a" } }, "t:x") },
	})
	assert(near(prices["t:x"], 100) and source["t:x"] == "base")
	callback()
end)

mtt.register("derive: recipes with an unpriced ingredient give no price", function(callback)
	local prices = derive({
		base = { ["t:a"] = 1 },
		recipes = {
			recipe("normal", { { "t:a" }, { "t:mystery" } }, "t:x"),
			recipe("normal", { { "t:x" } }, "t:y"),
		},
	})
	assert(prices["t:x"] == nil and prices["t:y"] == nil)
	callback()
end)

mtt.register("derive: markup per recipe type", function(callback)
	local prices = derive({
		base = { ["t:a"] = 10 },
		recipes = { recipe("alloy", { { "t:a", 2 } }, "t:x") },
		markup = function(rtype) return rtype == "alloy" and 0.25 or 0 end,
	})
	assert(near(prices["t:x"], 25))
	callback()
end)

mtt.register("derive: a group costs as much as its cheapest priced member", function(callback)
	local prices = derive({
		base = { ["t:oak"] = 4, ["t:pine"] = 2 },
		groups = { wood = { "t:oak", "t:pine", "t:unpriced" } },
		recipes = { recipe("normal", { { group = "wood", count = 2 } }, "t:chest") },
	})
	assert(near(prices["t:chest"], 4))
	callback()
end)

mtt.register("derive: block and ingot cycle settles at the cheapest cost", function(callback)
	local prices = derive({
		base = { ["t:ingot"] = 10 },
		recipes = {
			recipe("normal", { { "t:ingot", 9 } }, "t:block"),
			recipe("normal", { { "t:block" } }, "t:ingot", 9),
		},
	})
	assert(near(prices["t:ingot"], 10), "ingot stays at its base price")
	assert(near(prices["t:block"], 90))
	callback()
end)

mtt.register("derive: a loop that creates value is dropped, not priced near zero", function(callback)
	local prices, _, dropped = derive({
		base = { ["t:seed"] = 8 },
		recipes = {
			recipe("normal", { { "t:seed" } }, "t:clone"),
			recipe("normal", { { "t:clone" } }, "t:clone", 2), -- duplicates itself
			recipe("normal", { { "t:seed" } }, "t:fine"),
		},
	})
	assert(prices["t:clone"] == nil, "clone has no price")
	assert(near(prices["t:fine"], 8), "unrelated items keep their price")
	assert(#dropped == 1 and dropped[1] == "t:clone")
	callback()
end)

---------------------------------------------------------------- base price file

local base_prices = mine_shop_gui.pricing.base_prices

local function write_temp(name, text)
	local path = core.get_worldpath() .. "/mine_shop_gui_test_" .. name .. ".lua"
	assert(core.safe_file_write(path, text))
	return path
end

mtt.register("base prices: a Lua file with comments and decimals loads", function(callback)
	local path = write_temp("ok", [[
-- stone family
return {
	["default:stone"] = 1, -- cheap
	["default:gold_lump"] = 40.5,
}
]])
	local prices, problems = base_prices.parse(path)
	assert(prices, tostring(problems))
	assert(prices["default:stone"] == 1 and prices["default:gold_lump"] == 40.5)
	assert(#problems == 0)
	callback()
end)

mtt.register("base prices: invalid entries are reported and skipped", function(callback)
	local path = write_temp("bad", [[
return {
	["default:stone"] = 1,
	["default:dirt"] = -3,
	["default:sand"] = "lots",
	[5] = 2,
}
]])
	local prices, problems = base_prices.parse(path)
	assert(prices["default:stone"] == 1)
	assert(prices["default:dirt"] == nil and prices["default:sand"] == nil)
	assert(#problems == 3, "problems: " .. #problems)
	callback()
end)

mtt.register("base prices: files cannot run code or touch globals", function(callback)
	local path = write_temp("evil", [[
core.log("error", "price file ran code")
return { ["default:stone"] = 1 }
]])
	local prices, err = base_prices.parse(path)
	assert(prices == nil and err, "expected the file to be rejected")
	callback()
end)

mtt.register("base prices: syntax errors and wrong return types are rejected", function(callback)
	local prices, err = base_prices.parse(write_temp("syntax", "return {"))
	assert(prices == nil and err)
	prices, err = base_prices.parse(write_temp("number", "return 5"))
	assert(prices == nil and err:find("table"))
	prices, err = base_prices.parse(core.get_worldpath() .. "/mine_shop_gui_test_missing.lua")
	assert(prices == nil and err == "not found")
	callback()
end)

mtt.register("base prices: world file overrides, false removes", function(callback)
	local merged = base_prices.merge(
		{ ["a:x"] = 1, ["a:y"] = 2, ["a:z"] = 3 },
		{ ["a:y"] = 20, ["a:z"] = false, ["a:new"] = 5 })
	assert(merged["a:x"] == 1 and merged["a:y"] == 20 and merged["a:new"] == 5)
	assert(merged["a:z"] == nil)
	callback()
end)

---------------------------------------------------------------- price file lookup

-- A fixture tree under the world folder:
--   prices/games/fakegame.lua, prices/mods/{alpha_conf,alpha_folder,onlyfolder,beta}.lua
local fixture = core.get_worldpath() .. "/mine_shop_gui_test_fixture"
local function fixture_file(rel, text)
	local dir = (fixture .. "/" .. rel):match("^(.*)/[^/]+$")
	assert(core.mkdir(dir), "cannot create " .. dir)
	assert(core.safe_file_write(fixture .. "/" .. rel, text))
end

mtt.register("price files: mod.conf name is preferred, folder name is deprecated", function(callback)
	local dir = fixture .. "/prices/mods"
	fixture_file("prices/mods/alpha_conf.lua", "return {}")
	fixture_file("prices/mods/alpha_folder.lua", "return {}")
	fixture_file("prices/mods/onlyfolder.lua", "return {}")
	fixture_file("prices/mods/beta.lua", "return {}")

	local path, deprecated = base_prices.mod_file(dir, "alpha_conf", "/x/mods/alpha_folder")
	assert(path == dir .. "/alpha_conf.lua" and deprecated == false, "conf name wins")

	path, deprecated = base_prices.mod_file(dir, "gamma_conf", "/x/mods/onlyfolder/")
	assert(path == dir .. "/onlyfolder.lua" and deprecated == true, "folder name is deprecated")

	path, deprecated = base_prices.mod_file(dir, "beta", [[C:\x\mods\beta]])
	assert(path == dir .. "/beta.lua" and deprecated == false, "no mod.conf name: folder is the id")

	assert(base_prices.mod_file(dir, "nothing", "/x/mods/nothing") == nil)
	callback()
end)

mtt.register("price files: game, mods and world file are layered in order", function(callback)
	fixture_file("prices/games/fakegame.lua",
		'return { ["fake:a"] = 1, ["fake:b"] = 2, ["fake:c"] = 3 }')
	fixture_file("prices/mods/beta.lua", 'return { ["fake:b"] = 20, ["fake:d"] = 4 }')
	fixture_file("world.lua", 'return { ["fake:c"] = false, ["fake:d"] = 40 }')

	local prices, unknown = base_prices.load({
		root = fixture .. "/prices",
		game_id = "fakegame",
		mods = { "beta", "not_installed_mod" },
		world_file = fixture .. "/world.lua",
	})
	assert(prices["fake:a"] == 1, "game price kept")
	assert(prices["fake:b"] == 20, "mod overrides game")
	assert(prices["fake:c"] == nil, "world false removes")
	assert(prices["fake:d"] == 40, "world overrides mod")
	assert(#unknown == 3, "unknown items are reported: " .. #unknown)
	callback()
end)

mtt.register("price files: the shipped files apply only to what is installed", function(callback)
	local prices, unknown = base_prices.load()
	assert(prices["default:cobble"] == 1, "game file for 'minetest' is loaded")
	assert(prices["default:iron_lump"] == 16)
	if core.get_modpath("technic_worldgen") then
		assert(prices["technic:zinc_lump"] == 14, "technic_worldgen file is loaded")
		assert(prices["moretrees:rubber_tree_trunk"] == 4)
	else
		assert(prices["technic:zinc_lump"] == nil, "technic is not in this world")
	end
	assert(prices["default:clay_lump"] == 2 and prices["farming:wheat"] == 3)
	assert(#unknown == 0, "shipped prices name unknown items: " .. table.concat(unknown, ", "))
	callback()
end)

---------------------------------------------------------------- flags (derivation)

mtt.register("flags: a derived item inherits flags from its ingredients", function(callback)
	local prices, _, _, flags = derive({
		base = { ["t:a"] = 1, ["t:b"] = 1, ["t:c"] = 1 },
		flags = { ["t:a"] = { no_buy = true }, ["t:b"] = { no_sell = true } },
		recipes = {
			recipe("normal", { { "t:a" }, { "t:b" } }, "t:ab"),
			recipe("normal", { { "t:ab" }, { "t:c" } }, "t:abc"),
			recipe("normal", { { "t:c", 2 } }, "t:cc"),
		},
	})
	assert(near(prices["t:ab"], 2), "still priced")
	assert(flags["t:ab"].no_buy and flags["t:ab"].no_sell, "both flags reach the result")
	assert(flags["t:abc"].no_buy and flags["t:abc"].no_sell, "and the result of the result")
	assert(flags["t:cc"] == nil, "unflagged ingredients give no flags")
	assert(flags["t:a"].no_buy and not flags["t:a"].no_sell, "own flags stay as they are")
	callback()
end)

mtt.register("flags: an item's own flags are kept and added to inherited ones", function(callback)
	local _, _, _, flags = derive({
		base = { ["t:a"] = 1, ["t:c"] = 1 },
		flags = { ["t:a"] = { no_buy = true }, ["t:x"] = { no_sell = true } },
		recipes = { recipe("normal", { { "t:a" }, { "t:c" } }, "t:x") },
	})
	assert(flags["t:x"].no_buy and flags["t:x"].no_sell)
	callback()
end)

mtt.register("flags: they follow the cheapest route", function(callback)
	local _, _, _, flags = derive({
		base = { ["t:flagged"] = 1, ["t:plain"] = 3 },
		flags = { ["t:flagged"] = { no_buy = true } },
		recipes = {
			recipe("normal", { { "t:flagged" } }, "t:cheap_flagged"),
			recipe("normal", { { "t:plain" } }, "t:cheap_flagged"),
			recipe("normal", { { "t:flagged", 5 } }, "t:cheap_plain"),
			recipe("alloy", { { "t:plain" } }, "t:cheap_plain"),
		},
	})
	assert(flags["t:cheap_flagged"] and flags["t:cheap_flagged"].no_buy, "cheapest route is flagged")
	assert(flags["t:cheap_plain"] == nil, "cheapest route is unflagged")
	callback()
end)

mtt.register("flags: a group ingredient passes on the flags of the member used", function(callback)
	local _, _, _, flags = derive({
		base = { ["t:oak"] = 4, ["t:pine"] = 2 },
		groups = { wood = { "t:oak", "t:pine" } },
		flags = { ["t:oak"] = { no_buy = true } },
		recipes = { recipe("normal", { { group = "wood", count = 1 } }, "t:chest") },
	})
	assert(flags["t:chest"] == nil, "pine is cheaper and unflagged")
	callback()
end)

---------------------------------------------------------------- flags (items and stacks)

local collect = mine_shop_gui.pricing.collect

mtt.register("flags: item definitions set them with _mine_shop_gui", function(callback)
	local f = collect.flags_from_def({ _mine_shop_gui = { no_buy = true } })
	assert(f.no_buy and not f.no_sell)
	f = collect.flags_from_def({ _mine_shop_gui = { no_sell = true, no_buy = true } })
	assert(f.no_buy and f.no_sell)
	assert(collect.flags_from_def({}) == nil)
	assert(collect.flags_from_def({ _mine_shop_gui = {} }) == nil)
	assert(collect.flags_from_def({ _mine_shop_gui = "yes" }) == nil)
	callback()
end)

mtt.register("flags: stack metadata flag is set only by the string 'true'", function(callback)
	local stack = ItemStack("default:stone")
	local meta = stack:get_meta()
	local f = collect.stack_flags(stack)
	assert(f.no_buy == false and f.no_sell == false, "absent keys are unset")

	meta:set_string("no_sell", "true")
	meta:set_string("no_buy", "true")
	f = collect.stack_flags(stack)
	assert(f.no_sell == true and f.no_buy == true, "'true' sets it")

	for _, value in ipairs({ "false", "1", "yes", "True", "TRUE", "0", "nonsense" }) do
		meta:set_string("no_sell", value)
		assert(collect.stack_flags(stack).no_sell == false, "'" .. value .. "' must not set it")
	end

	meta:set_int("no_sell", 1)
	assert(collect.stack_flags(stack).no_sell == false, "integer 1 is stored as '1', not 'true'")

	meta:set_string("no_sell", "")
	assert(not meta:contains("no_sell"), "an empty string deletes the key")
	assert(collect.stack_flags(stack).no_sell == false)
	assert(collect.stack_flags(stack).no_buy == true, "other flag is independent")
	assert(meta.set_bool == nil, "metadata really has no set_bool")
	callback()
end)

---------------------------------------------------------------- collector (real recipes)

mtt.register("collector: reads real recipes, groups and Minetest Game crafts", function(callback)
	local recipes = collect.recipes()
	assert(#recipes > 100, "recipes: " .. #recipes)

	local found_cooking, found_sticks
	for _, r in ipairs(recipes) do
		assert(core.registered_items[r.output.name], "unregistered output " .. r.output.name)
		assert(r.output.count >= 1 and #r.inputs >= 1)
		for _, input in ipairs(r.inputs) do
			assert(input.name or input.group)
			assert(input.count >= 1)
		end
		if r.type == "cooking" and r.output.name == "default:stone"
				and r.inputs[1].name == "default:cobble" then
			found_cooking = true
		end
		if r.output.name == "default:stick" and r.output.count == 4
				and r.inputs[1].group == "wood" then
			found_sticks = true
		end
	end
	assert(found_cooking, "cobble -> stone smelting recipe")
	assert(found_sticks, "4 sticks from group:wood")

	local groups = collect.groups(recipes)
	local wood = groups["wood"]
	assert(wood, "group wood is used by recipes")
	local has_wood = false
	for _, name in ipairs(wood) do
		if name == "default:wood" then has_wood = true end
	end
	assert(has_wood, "default:wood is in group wood")
	callback()
end)

---------------------------------------------------------------- generation and hook

mtt.register("generate: real prices for Minetest Game", function(callback)
	local pricing = mine_shop_gui.pricing
	local items, report = pricing.generate()
	assert(#report.dropped == 0, "unstable items: " .. table.concat(report.dropped, ", "))
	assert(items["default:cobble"].price == 1 and items["default:cobble"].source == "base")
	assert(near(items["default:stone"].price, 1) and items["default:stone"].source == "cooking")
	assert(near(items["default:wood"].price, 1), "4 planks from a 4-unit log")
	assert(near(items["default:stick"].price, 0.25), "4 sticks from one plank")
	assert(near(items["default:steel_ingot"].price, core.get_modpath("technic") and 8 or 16),
		"smelted from an iron lump (16), or from half a lump when Technic grinds it")
	assert(near(items["default:clay"].price, 8), "4 clay lumps at 2 each")
	assert(items["default:paper"] and items["default:bookshelf"], "papyrus anchor prices paper and shelves")
	for name, entry in pairs(items) do
		assert(entry.price >= 0 and entry.price < math.huge, name)
		assert(entry.no_buy == false and entry.no_sell == false,
			name .. " has flags in plain Minetest Game")
	end
	callback()
end)

mtt.register("generate: markup setting applies per recipe type", function(callback)
	local before = mine_shop_gui.pricing.generate()["default:steel_ingot"].price
	core.settings:set("mine_shop_gui_markup_cooking", "50")
	local ok, err = pcall(function()
		local items = mine_shop_gui.pricing.generate()
		assert(near(items["default:steel_ingot"].price, before * 1.5), "smelting costs 50% more")
		assert(near(items["default:wood"].price, 1), "crafting markup is still 0")
	end)
	core.settings:remove("mine_shop_gui_markup_cooking")
	assert(ok, err)
	callback()
end)

mtt.register("hook: runs after the collector and can change, remove, add and flag", function(callback)
	local pricing = mine_shop_gui.pricing
	local seen_before_hook
	local items = pricing.generate({
		base = { ["default:stone"] = 2, ["default:dirt"] = 3, ["default:sand"] = 4 },
		recipes = {}, groups = {}, flags = {},
		hooks = {
			function(t)
				seen_before_hook = t["default:stone"] and t["default:stone"].price
				t["default:stone"].price = 10
				t["default:dirt"] = nil
				t["default:gravel"] = { price = 7 }
				t["default:sand"].no_sell = true
			end,
			function(t)
				-- later hooks see earlier changes
				t["default:gravel"].price = t["default:gravel"].price + 1
			end,
		},
	})
	assert(seen_before_hook == 2, "hook saw the derived price")
	assert(items["default:stone"].price == 10)
	assert(items["default:dirt"] == nil)
	assert(items["default:gravel"].price == 8 and items["default:gravel"].source == "hook")
	assert(items["default:gravel"].no_buy == false)
	assert(items["default:sand"].no_sell == true and items["default:sand"].no_buy == false)
	callback()
end)

mtt.register("hook: bad entries are dropped and a failing hook does not stop others", function(callback)
	local items = mine_shop_gui.pricing.generate({
		base = { ["default:stone"] = 2 },
		recipes = {}, groups = {}, flags = {},
		hooks = {
			function() error("boom") end,
			function(t)
				t["default:dirt"] = { price = -1 }
				t["default:sand"] = { price = "free" }
				t["mod_that_is_not_installed:thing"] = { price = 5 }
				t["default:gravel"] = 5
				t["default:clay_lump"] = { price = 3 }
			end,
		},
	})
	assert(items["default:stone"].price == 2)
	assert(items["default:dirt"] == nil and items["default:sand"] == nil)
	assert(items["mod_that_is_not_installed:thing"] == nil and items["default:gravel"] == nil)
	assert(items["default:clay_lump"].price == 3, "the good entry from the same hook survives")
	callback()
end)

mtt.register("trade checks: flags on items and on stacks", function(callback)
	local pricing = mine_shop_gui.pricing
	pricing.generate({
		base = { ["default:stone"] = 1, ["default:dirt"] = 1, ["default:sand"] = 1 },
		recipes = {}, groups = {},
		flags = { ["default:dirt"] = { no_sell = true }, ["default:sand"] = { no_buy = true } },
		hooks = {},
	})
	assert(pricing.can_buy("default:stone") and pricing.can_sell(ItemStack("default:stone")))
	assert(pricing.can_buy("default:dirt") and not pricing.can_sell(ItemStack("default:dirt")))
	assert(not pricing.can_buy("default:sand") and pricing.can_sell(ItemStack("default:sand")))
	assert(not pricing.can_buy("default:gravel"), "unpriced items cannot be bought")
	assert(not pricing.can_sell(ItemStack("default:gravel")), "or sold")

	local flagged = ItemStack("default:stone")
	flagged:get_meta():set_string("no_sell", "true")
	assert(not pricing.can_sell(flagged), "this stack cannot be sold")
	assert(pricing.can_sell(ItemStack("default:stone")), "other stone still can")

	pricing.generate() -- back to the real prices
	callback()
end)

---------------------------------------------------------------- Technic (only when it is installed)

if core.get_modpath("technic") then

mtt.register("technic: machine recipes are collected, multi-output ones are not", function(callback)
	local by_type = {}
	for _, r in ipairs(collect.recipes()) do
		by_type[r.type] = (by_type[r.type] or 0) + 1
		assert(r.output.name and r.output.count >= 1, "one output per recipe")
	end
	for _, rtype in ipairs({ "grinding", "alloy", "compressing", "extracting", "cooking", "normal" }) do
		assert((by_type[rtype] or 0) > 0, "no " .. rtype .. " recipes collected")
	end
	assert(by_type["separating"] == nil, "separating recipes have two outputs and are skipped")
	callback()
end)

mtt.register("technic: ingots cost half their lump because players grind", function(callback)
	local items = mine_shop_gui.pricing.generate()
	local metals = {
		{ "default:iron_lump", "default:steel_ingot" },
		{ "default:copper_lump", "default:copper_ingot" },
		{ "default:tin_lump", "default:tin_ingot" },
		{ "default:gold_lump", "default:gold_ingot" },
	}
	for _, pair in ipairs(metals) do
		local lump, ingot = items[pair[1]], items[pair[2]]
		assert(lump and lump.source == "base", pair[1] .. " keeps its base price")
		assert(ingot and near(ingot.price, lump.price / 2),
			pair[2] .. " should be half of " .. pair[1] .. ", got " .. tostring(ingot and ingot.price))
		assert(ingot.source == "cooking", pair[2] .. " is smelted from ground dust")
	end
	callback()
end)

mtt.register("technic: grinding markup of 100% puts ingots back at the lump price", function(callback)
	core.settings:set("mine_shop_gui_markup_grinding", "100")
	local ok, err = pcall(function()
		local items = mine_shop_gui.pricing.generate()
		assert(near(items["default:steel_ingot"].price, 16))
		assert(near(items["default:gold_ingot"].price, 40))
	end)
	core.settings:remove("mine_shop_gui_markup_grinding")
	assert(ok, err)
	callback()
end)

mtt.register("technic: its own lumps and rubber trunk are priced", function(callback)
	local items = mine_shop_gui.pricing.generate()
	assert(items["technic:zinc_lump"].price == 14 and items["technic:zinc_lump"].source == "base")
	assert(items["moretrees:rubber_tree_trunk"].price == 4)
	callback()
end)

end
