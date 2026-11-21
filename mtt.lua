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

-- Run fn with a setting changed, then put the setting back as it was.
local function with_setting(key, value, fn)
	local original = core.settings:get(key)
	if value == nil then core.settings:remove(key) else core.settings:set(key, value) end
	local ok, err = pcall(fn)
	if original == nil then core.settings:remove(key) else core.settings:set(key, original) end
	assert(ok, err)
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
	with_setting("mine_shop_gui_item_currency", "", function()
		assert(api.resolve().name == "currency")
	end)
	callback()
end)

mtt.register("currency: a configured item currency is used by auto", function(callback)
	core.settings:set("mine_shop_gui_currency", "auto")
	assert((core.settings:get("mine_shop_gui_item_currency") or "") ~= "", "the test config sets an item currency")
	assert(api.resolve().name == "items", "auto uses the item currency once it is set up")
	-- an explicit choice still wins
	core.settings:set("mine_shop_gui_currency", "currency")
	assert(api.resolve().name == "currency")
	core.settings:set("mine_shop_gui_currency", "items")
	assert(api.resolve().name == "items")
	core.settings:set("mine_shop_gui_currency", "auto")
	callback()
end)

mtt.register("currency: unavailable explicit choice falls back to auto", function(callback)
	core.settings:set("mine_shop_gui_currency", "nonexistent")
	with_setting("mine_shop_gui_item_currency", "", function()
		assert(api.resolve().name == "currency")
	end)
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

---------------------------------------------------------------- cookies
-- Only runs in a world where the Noclip Cookie mod is loaded.

if rawget(_G, "cookies") and core.registered_items["currency:cookie"] then
	local function reset_jar(name, jar)
		assert(cookies.set(name, jar or 0))
	end

	mtt.register("cookies: auto selection finds the cookie mod", function(callback)
		core.settings:set("mine_shop_gui_currency", "auto")
		with_setting("mine_shop_gui_item_currency", "", function()
			assert(api.resolve().name == "cookies")
		end)
		assert(api.is_money("currency:cookie"))
		callback()
	end)

	mtt.register("cookies: spend the jar first, then cookie items", function(callback)
		local c = use("cookies")
		with_player("shop_cookie1", function(_, inv)
			reset_jar("shop_cookie1", 10)
			inv:add_item("main", ItemStack("currency:cookie 5"))
			assert(c.balance("shop_cookie1") == 15)
			assert(c.withdraw("shop_cookie1", 12) == true)
			assert(cookies.get("shop_cookie1") == 0)
			assert(count_value(inv, { ["currency:cookie"] = 1 }) == 3)
			assert(c.deposit("shop_cookie1", 7) == true)
			assert(cookies.get("shop_cookie1") == 7, "payouts go to the jar")
			assert(c.balance("shop_cookie1") == 10)
		end)
		callback()
	end)

	mtt.register("cookies: invalid and unaffordable payments change nothing", function(callback)
		local c = use("cookies")
		with_player("shop_cookie2", function(_, inv)
			reset_jar("shop_cookie2", 4)
			inv:add_item("main", ItemStack("currency:cookie 2"))
			local ok, why = c.withdraw("shop_cookie2", 7)
			assert(ok == false and why == "insufficient_funds")
			ok, why = c.withdraw("shop_cookie2", -1)
			assert(ok == false and why == "invalid_amount")
			ok, why = c.withdraw("shop_cookie2", 1.5)
			assert(ok == false and why == "invalid_amount")
			assert(c.balance("shop_cookie2") == 6 and cookies.get("shop_cookie2") == 4)
		end)
		callback()
	end)

	mtt.register("cookies: snapshot and restore undo a payment", function(callback)
		local c = use("cookies")
		with_player("shop_cookie3", function(_, inv)
			reset_jar("shop_cookie3", 3)
			inv:add_item("main", ItemStack("currency:cookie 4"))
			local snap = c.snapshot("shop_cookie3")
			assert(c.withdraw("shop_cookie3", 6) == true)
			assert(c.balance("shop_cookie3") == 1)
			c.restore("shop_cookie3", snap)
			assert(cookies.get("shop_cookie3") == 3)
			assert(count_value(inv, { ["currency:cookie"] = 1 }) == 4)
		end)
		callback()
	end)

	mtt.register("cookies: offline player is unavailable", function(callback)
		local c = use("cookies")
		assert(c.balance("shop_nobody") == nil)
		local ok, why = c.withdraw("shop_nobody", 1)
		assert(ok == false and why == "unavailable")
		callback()
	end)
end

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
	with_setting("mine_shop_gui_item_currency_worth", "20", function()
		assert(api.price(20, "buy") == 1, "20 cobblestone is one item")
		assert(api.price(100, "buy") == 5)
		local amount, why = api.price(10, "sell")
		assert(amount == nil and why == "too_cheap", "5 units sells for less than one item")
	end)
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

mtt.register("derive: a base price is a ceiling that a cheaper recipe lowers", function(callback)
	local prices, source, _, _, _, lowered = derive({
		base = { ["t:a"] = 10, ["t:x"] = 100, ["t:y"] = 3 },
		recipes = {
			recipe("melting", { { "t:a" } }, "t:x"), -- makes x for 10, base says 100
			recipe("normal", { { "t:a" } }, "t:y"),  -- makes y for 10, base says 3: stays
		},
	})
	assert(near(prices["t:x"], 10) and source["t:x"] == "melting", "x is lowered to the recipe cost")
	assert(lowered["t:x"] == 100, "the original base price is reported")
	assert(near(prices["t:y"], 3) and source["t:y"] == "base" and lowered["t:y"] == nil,
		"a recipe that costs more changes nothing")
	callback()
end)

mtt.register("derive: a fixed base price is never lowered, only reported", function(callback)
	local prices, source, _, _, below, lowered = derive({
		base = { ["t:a"] = 10, ["t:x"] = { price = 100, fixed = true }, ["t:y"] = { price = 3, fixed = false } },
		recipes = {
			recipe("melting", { { "t:a" } }, "t:x"),
			recipe("melting", { { "t:a", 0.1 } }, "t:y"),
		},
	})
	assert(near(prices["t:x"], 100) and source["t:x"] == "base", "fixed price stays")
	assert(near(below["t:x"], 10) and lowered["t:x"] == nil, "and is reported as undercut")
	assert(near(prices["t:y"], 1) and lowered["t:y"] == 3, "fixed = false behaves like a plain number")
	callback()
end)

mtt.register("derive: a lowered base price takes on the flags of the cheaper route", function(callback)
	local _, _, _, flags = derive({
		base = { ["t:flagged"] = 1, ["t:x"] = 50 },
		flags = { ["t:flagged"] = { no_buy = true }, ["t:x"] = { no_sell = true } },
		recipes = { recipe("melting", { { "t:flagged" } }, "t:x") },
	})
	assert(flags["t:x"].no_buy and flags["t:x"].no_sell, "own flag kept, inherited flag added")
	callback()
end)

mtt.register("derive: cutting a loop leaves everything downstream of it priced", function(callback)
	-- 2 sand compress to 1 sandstone, but 1 sandstone grinds to 4 sand: a gain of 2x per turn
	local prices, _, dropped = derive({
		base = { ["t:sand"] = 1 },
		recipes = {
			recipe("compressing", { { "t:sand", 2 } }, "t:sandstone"),
			recipe("grinding", { { "t:sandstone" } }, "t:sand", 4),
			recipe("normal", { { "t:sandstone", 2 } }, "t:wall"),
			recipe("normal", { { "t:wall" } }, "t:stair", 2),
		},
	})
	assert(near(prices["t:sand"], 1), "the base-priced member is held at its base price")
	assert(near(prices["t:sandstone"], 2), "sandstone costs 2 sand")
	assert(near(prices["t:wall"], 4) and near(prices["t:stair"], 2), "downstream items keep their prices")
	assert(#dropped == 0, "nothing was left unpriced")
	callback()
end)

mtt.register("derive: a value-creating loop holds a base-priced item at its base price", function(callback)
	local prices, _, dropped = derive({
		base = { ["t:seed"] = 8, ["t:clone"] = 5 },
		recipes = {
			recipe("normal", { { "t:seed" } }, "t:clone"),
			recipe("normal", { { "t:clone" } }, "t:clone", 2), -- duplicates itself
		},
	})
	assert(near(prices["t:clone"], 5), "falls back to the base price, not to zero")
	assert(#dropped == 0, "it still has a price, so it is not dropped")
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

mtt.register("derive: a loop that creates value is cut, the item keeps its outside route", function(callback)
	local prices, _, dropped = derive({
		base = { ["t:seed"] = 8 },
		recipes = {
			recipe("normal", { { "t:seed" } }, "t:clone"),
			recipe("normal", { { "t:clone" } }, "t:clone", 2), -- duplicates itself
			recipe("normal", { { "t:seed" } }, "t:fine"),
		},
	})
	assert(near(prices["t:clone"], 8), "priced from the seed, not driven towards zero")
	assert(near(prices["t:fine"], 8), "unrelated items keep their price")
	assert(#dropped == 0, "nothing is left unpriced")
	callback()
end)

mtt.register("derive: a loop with no outside route stays unpriced", function(callback)
	local prices, _, dropped = derive({
		base = { ["t:seed"] = 8 },
		recipes = {
			recipe("normal", { { "t:a" } }, "t:b", 2),
			recipe("normal", { { "t:b" } }, "t:a", 2),
			recipe("normal", { { "t:seed" } }, "t:fine"),
		},
	})
	assert(prices["t:a"] == nil and prices["t:b"] == nil, "no way in, no price")
	assert(near(prices["t:fine"], 8))
	callback()
end)

mtt.register("derive: a gaining loop with no base price is priced from its outside routes", function(callback)
	-- glass is made from sand, ground into fragments (4 per glass), and 4 fragments melt into 2 glass
	local prices, _, dropped = derive({
		base = { ["t:sand"] = 1 },
		recipes = {
			recipe("cooking", { { "t:sand" } }, "t:glass"),
			recipe("grinding", { { "t:glass" } }, "t:fragments", 4),
			recipe("melting", { { "t:fragments", 4 } }, "t:glass", 2),
			recipe("normal", { { "t:glass", 3 } }, "t:slab", 6),
		},
	})
	assert(near(prices["t:glass"], 1), "glass keeps the price of making it from sand")
	assert(near(prices["t:fragments"], 0.25), "fragments are priced from the held glass")
	assert(near(prices["t:slab"], 0.5), "slabs downstream are priced too")
	assert(#dropped == 0)
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
	assert(prices["default:cobble"].price == 1 and prices["default:cobble"].fixed == true,
		"game file for 'minetest' is loaded; cobblestone is the fixed unit")
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
	assert(items["default:clay"].price <= 8 + 1e-9, "clay costs at most 4 lumps at 2 each (less with Techage's grinder)")
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
		-- Techage's melting pot makes 4 steel from 3 iron lumps and 1 coal: (3*16 + 8) / 4
		local steel = (core.get_modpath("techage") and core.get_modpath("unified_inventory")) and 14 or 16
		assert(near(items["default:steel_ingot"].price, steel), "steel: " .. items["default:steel_ingot"].price)
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

---------------------------------------------------------------- Techage (only when it is installed)

-- No recipe may appear twice (same output and ingredients), whichever source it came from.
mtt.register("collector: duplicate recipes from different sources are removed", function(callback)
	local seen = {}
	for _, r in ipairs(collect.recipes()) do
		local parts = {}
		for _, i in ipairs(r.inputs) do parts[#parts + 1] = (i.name or ("group:" .. i.group)) .. "*" .. i.count end
		table.sort(parts)
		local key = r.output.name .. "*" .. r.output.count .. "|" .. table.concat(parts, ",")
		assert(not seen[key], "duplicate recipe " .. key)
		seen[key] = true
	end
	callback()
end)

if core.get_modpath("techage") then

mtt.register("techage: fabricator and doser recipes are collected through its API", function(callback)
	local by_type, chip = {}, nil
	for _, r in ipairs(collect.recipes()) do
		by_type[r.type] = (by_type[r.type] or 0) + 1
		if r.output.name == "techage:ta4_wlanchip" then chip = r end
	end
	for _, rtype in ipairs({ "ta2_electronic_fab", "ta3_electronic_fab", "ta4_electronic_fab", "ta4_doser" }) do
		assert((by_type[rtype] or 0) > 0, "no " .. rtype .. " recipes")
	end
	assert(chip and chip.output.count == 8, "a WLAN chip recipe that makes 8")
	local names = {}
	for _, i in ipairs(chip.inputs) do names[i.name] = i.count end
	assert(names["default:mese_crystal"] == 1 and names["default:gold_ingot"] == 1
		and names["default:copper_ingot"] == 1 and names["techage:ta4_silicon_wafer"] == 1,
		"inputs of the chip recipe")
	callback()
end)

mtt.register("techage: chips and tubes are priced from their parts", function(callback)
	local items = mine_shop_gui.pricing.generate()
	local function p(name) return items[name].price end

	local chip = items["techage:ta4_wlanchip"]
	assert(chip and chip.source:find("electronic_fab"), "chip source: " .. tostring(chip and chip.source))
	assert(near(chip.price, (p("default:mese_crystal") + p("default:copper_ingot")
		+ p("default:gold_ingot") + p("techage:ta4_silicon_wafer")) / 8), "8 chips from one set of parts")

	local tube = items["techage:vacuum_tube"]
	assert(tube and near(tube.price, (p("default:glass") + p("basic_materials:copper_wire")
		+ p("basic_materials:plastic_sheet") + p("techage:usmium_nuggets")) / 2),
		"2 vacuum tubes, one of them paid for with a usmium nugget; got " .. tostring(tube and tube.price))
	assert(items["techage:ta5_aichip"] and items["techage:ta5_ssd"], "later tiers are priced too")
	callback()
end)

mtt.register("techage: markup applies per fabricator type", function(callback)
	local before = mine_shop_gui.pricing.generate()["techage:ta4_wlanchip"]
	core.settings:set("mine_shop_gui_markup_" .. before.source, "100")
	local ok, err = pcall(function()
		local after = mine_shop_gui.pricing.generate()["techage:ta4_wlanchip"]
		assert(near(after.price, before.price * 2), "100% markup doubles the chip: " .. after.price)
	end)
	core.settings:remove("mine_shop_gui_markup_" .. before.source)
	assert(ok, err)
	callback()
end)

if core.get_modpath("unified_inventory") then

mtt.register("techage: melting pot and mill recipes come from the craft guide", function(callback)
	local found_iron, found_bronze, random_types = false, false, 0
	for _, r in ipairs(collect.recipes()) do
		if r.type == "melting" and r.output.name == "techage:iron_ingot"
				and r.inputs[1].name == "default:iron_lump" and r.inputs[1].count == 1 then
			found_iron = true
		end
		if r.type == "melting" and r.output.name == "default:bronze_ingot" and r.output.count == 4 then
			found_bronze = true
		end
		if r.type:find("sieve") or r.type == "rinsing" or r.type:find("digging") then
			random_types = random_types + 1
		end
	end
	assert(found_iron, "iron lump melts to a Techage iron ingot")
	assert(found_bronze, "3 copper + 1 tin melt to 4 bronze")
	assert(random_types == 0, "random-output machines are not collected")
	callback()
end)

end

end

mtt.register("generate: lowered base prices and undercut fixed prices are reported", function(callback)
	local _, report = mine_shop_gui.pricing.generate({
		base = { ["default:cobble"] = 1, ["default:obsidian"] = 25, ["default:glass"] = { price = 9, fixed = true },
			["default:sand"] = 1 },
		recipes = {
			{ type = "melting", inputs = { { name = "default:cobble", count = 1 } },
				output = { name = "default:obsidian", count = 1 } },
			{ type = "melting", inputs = { { name = "default:sand", count = 1 } },
				output = { name = "default:glass", count = 1 } },
		},
		groups = {}, flags = {}, hooks = {},
	})
	assert(#report.lowered == 1, "one lowered price, got " .. #report.lowered)
	local drop = report.lowered[1]
	assert(drop.item == "default:obsidian" and drop.base == 25 and near(drop.route, 1))
	assert(#report.below_base == 1, "one fixed price undercut, got " .. #report.below_base)
	local gap = report.below_base[1]
	assert(gap.item == "default:glass" and gap.base == 9 and near(gap.route, 1))
	mine_shop_gui.pricing.generate() -- back to the real prices
	callback()
end)

---------------------------------------------------------------- base prices as ceilings

mtt.register("generate: no recipe makes an item for less than its price", function(callback)
	local pricing = mine_shop_gui.pricing
	local items, report = pricing.generate()
	local recipes = collect.recipes()
	local groups = collect.groups(recipes)
	local fixed_gap = {}
	for _, gap in ipairs(report.below_base) do fixed_gap[gap.item] = true end
	for _, gap in ipairs(report.held) do fixed_gap[gap.item] = true end -- held inside a gaining loop

	local checked, violations = 0, {}
	for _, r in ipairs(recipes) do
		local entry = items[r.output.name]
		if entry and not fixed_gap[r.output.name] then
			local cost, complete = 0, true
			for _, input in ipairs(r.inputs) do
				local price
				if input.name then
					price = items[input.name] and items[input.name].price
				else
					for _, member in ipairs(groups[input.group] or {}) do
						local e = items[member]
						if e and (not price or e.price < price) then price = e.price end
					end
				end
				if not price then complete = false break end
				cost = cost + price * input.count
			end
			if complete then
				checked = checked + 1
				local candidate = cost * (1 + pricing.markup(r.type)) / r.output.count
				if candidate < entry.price * (1 - 1e-6) then
					violations[#violations + 1] = string.format("%s: %s makes it for %.3f, price is %.3f",
						r.output.name, r.type, candidate, entry.price)
				end
			end
		end
	end
	assert(checked > 100, "checked only " .. checked .. " recipes")
	assert(#violations == 0, #violations .. " items cost more than a recipe makes them for, e.g. "
		.. (violations[1] or ""))
	callback()
end)

mtt.register("generate: the shipped prices leave no fixed price undercut", function(callback)
	local _, report = mine_shop_gui.pricing.generate()
	local names = {}
	for _, gap in ipairs(report.below_base) do names[#names + 1] = gap.item end
	assert(#names == 0, "fixed prices above the cost of making the item: " .. table.concat(names, ", "))
	callback()
end)

if core.get_modpath("techage") and core.get_modpath("unified_inventory") then

mtt.register("techage: prices the machines undercut are lowered, the unit is not", function(callback)
	local items, report = mine_shop_gui.pricing.generate()
	assert(near(items["default:obsidian"].price, 1) and items["default:obsidian"].source == "melting",
		"melting pot makes obsidian from cobblestone")
	assert(items["default:clay_lump"].price < 2, "sand grinds to clay")
	assert(items["default:cobble"].price == 1 and items["default:cobble"].source == "base",
		"cobblestone is fixed")
	local lowered = {}
	for _, drop in ipairs(report.lowered) do lowered[drop.item] = drop end
	assert(lowered["default:obsidian"] and lowered["default:obsidian"].base == 25)
	callback()
end)

end

---------------------------------------------------------------- shop: trading

local trade = mine_shop_gui.shop.trade
local catalog_api = mine_shop_gui.shop.catalog
local ui = mine_shop_gui.shop.ui
local pricing_api = mine_shop_gui.pricing

local function has_stack(inv, text)
	return inv:contains_item("main", ItemStack(text))
end

mtt.register("shop trade: buying pays, makes change and delivers", function(callback)
	use("currency")
	pricing_api.generate()
	with_player("shop_buyer1", function(_, inv)
		inv:add_item("main", ItemStack("currency:minegeld")) -- 100 cents
		local ok, info = trade.buy("shop_buyer1", "default:cobble", 10) -- 10 units * 5 cents
		assert(ok, tostring(info))
		assert(info.cost == 50 and info.amount == 10)
		assert(has_stack(inv, "default:cobble 10"))
		assert(count_value(inv, CENTS) == 50, "change: " .. count_value(inv, CENTS))
	end)
	callback()
end)

mtt.register("shop trade: buying more than the player can afford changes nothing", function(callback)
	use("currency")
	pricing_api.generate()
	with_player("shop_buyer2", function(_, inv)
		inv:add_item("main", ItemStack("currency:minegeld_cent_25"))
		local ok, why = trade.buy("shop_buyer2", "default:cobble", 10)
		assert(ok == false and why == "insufficient_funds", tostring(why))
		assert(count_value(inv, CENTS) == 25)
		assert(not has_stack(inv, "default:cobble"))
	end)
	callback()
end)

mtt.register("shop trade: a purchase that cannot be delivered is paid back", function(callback)
	use("currency")
	pricing_api.generate()
	with_player("shop_buyer3", function(_, inv)
		inv:set_size("main", 2)
		inv:set_stack("main", 1, ItemStack("currency:minegeld_cent_10"))
		inv:set_stack("main", 2, ItemStack("default:dirt 99"))
		local ok, why = trade.buy("shop_buyer3", "default:cobble", 1) -- 5 cents, the change takes the coin's slot
		assert(ok == false and why == "no_room", tostring(why))
		assert(count_value(inv, CENTS) == 10, "the 10 cent coin is back: " .. count_value(inv, CENTS))
		assert(not has_stack(inv, "default:cobble"))
		assert(has_stack(inv, "default:dirt 99"))
	end)
	callback()
end)

mtt.register("shop trade: an undeliverable purchase restores credits and unified_money too", function(callback)
	pricing_api.generate()
	if api.adapters.credits.available() then
		use("credits")
		with_player("shop_buyer4", function(_, inv)
			inv:set_size("main", 1)
			inv:set_stack("main", 1, ItemStack("default:dirt 99"))
			reset_credits("shop_buyer4", 100)
			local ok, why = trade.buy("shop_buyer4", "default:cobble", 1)
			assert(ok == false and why == "no_room", tostring(why))
			assert(credits.get_balance_digital("shop_buyer4") == 100, "digital balance restored")
		end)
	end
	if api.adapters.unified_money.available() then
		use("unified_money")
		with_player("shop_buyer5", function(_, inv)
			inv:set_size("main", 1)
			inv:set_stack("main", 1, ItemStack("default:dirt 99"))
			unified_money.set_balance_safe("shop_buyer5", 50)
			local ok, why = trade.buy("shop_buyer5", "default:cobble", 1)
			assert(ok == false and why == "no_room", tostring(why))
			assert(unified_money.get_balance("shop_buyer5") == 50, "balance restored")
		end)
	end
	callback()
end)

mtt.register("shop trade: selling takes only items the shop accepts and pays", function(callback)
	use("currency")
	pricing_api.generate()
	with_player("shop_seller1", function(_, inv)
		inv:set_stack("main", 1, ItemStack("default:cobble 8"))
		local flagged = ItemStack("default:cobble 2")
		flagged:get_meta():set_string("no_sell", "true")
		inv:set_stack("main", 2, flagged)
		inv:set_stack("main", 3, ItemStack("default:pick_steel"))
		local worn = ItemStack("default:pick_steel")
		worn:set_wear(1000)
		inv:set_stack("main", 4, worn)

		assert(trade.sellable_count("shop_seller1", "default:cobble") == 8, "flagged stack is not counted")
		assert(trade.sellable_count("shop_seller1", "default:pick_steel") == 1, "a worn tool is not counted")

		local ok, info = trade.sell("shop_seller1", "default:cobble", 8) -- 8 * 0.5 * 5 cents
		assert(ok, tostring(info))
		assert(info.payout == 20, "payout " .. tostring(info.payout))
		assert(count_value(inv, CENTS) == 20)
		assert(inv:get_stack("main", 2):get_count() == 2, "the flagged stack is untouched")

		local again, why = trade.sell("shop_seller1", "default:cobble", 1)
		assert(again == false and why == "not_enough", tostring(why))
	end)
	callback()
end)

mtt.register("shop trade: sell all, and items worth less than a coin", function(callback)
	use("currency")
	pricing_api.generate()
	with_player("shop_seller2", function(_, inv)
		inv:set_stack("main", 1, ItemStack("default:cobble 7"))
		inv:set_stack("main", 2, ItemStack("default:cobble 5"))
		local ok, info = trade.sell_all("shop_seller2", "default:cobble")
		assert(ok and info.amount == 12 and info.payout == 30, "12 * 2.5 cents rounds to 30")
		assert(not has_stack(inv, "default:cobble"))
	end)
	local stick = pricing_api.get("default:stick")
	if stick and near(stick.price, 0.25) then
		with_player("shop_seller3", function(_, inv)
			inv:set_stack("main", 1, ItemStack("default:stick 8"))
			local ok, why = trade.sell("shop_seller3", "default:stick", 1)
			assert(ok == false and why == "too_cheap", tostring(why))
			assert(has_stack(inv, "default:stick 8"), "nothing was taken")
			assert(trade.min_sell_amount("default:stick") == 4, "min " .. tostring(trade.min_sell_amount("default:stick")))
			assert(trade.sell("shop_seller3", "default:stick", 4))
		end)
	end
	callback()
end)

mtt.register("shop trade: flags and limits", function(callback)
	use("currency")
	pricing_api.generate({
		base = { ["default:dirt"] = 1, ["default:sand"] = 1, ["default:gravel"] = 1 },
		recipes = {}, groups = {}, hooks = {},
		flags = { ["default:dirt"] = { no_buy = true }, ["default:sand"] = { no_sell = true } },
	})
	local ok, why = trade.quote("default:dirt", 1, "buy")
	assert(ok == nil and why == "not_for_sale")
	assert(trade.quote("default:dirt", 1, "sell"), "dirt can still be sold")
	ok, why = trade.quote("default:sand", 1, "sell")
	assert(ok == nil and why == "not_for_sale")
	assert(trade.quote("default:sand", 1, "buy"), "sand can still be bought")
	ok, why = trade.quote("default:stone", 1, "buy")
	assert(ok == nil and why == "not_for_sale", "unpriced items cannot be traded")

	core.settings:set("mine_shop_gui_max_amount", "5")
	local good = trade.quote("default:gravel", 5, "buy")
	local bad, bad_why = trade.quote("default:gravel", 6, "buy")
	core.settings:remove("mine_shop_gui_max_amount")
	assert(good and bad == nil and bad_why == "invalid_amount", "the purchase limit applies")
	for _, amount in ipairs({ 0, -1, 1.5 }) do
		local q, w = trade.quote("default:gravel", amount, "buy")
		assert(q == nil and w == "invalid_amount", tostring(amount))
	end
	pricing_api.generate()
	callback()
end)

---------------------------------------------------------------- shop: catalog

mtt.register("shop catalog: categories, search and paging", function(callback)
	pricing_api.generate()
	local cats = catalog_api.categories()
	assert(cats[1].id == "all" and cats[1].title == "Everything")
	local default
	for _, c in ipairs(cats) do
		assert(c.count > 0 and core.registered_items[c.icon], "category " .. c.id .. " has an icon")
		if c.id == "default" then default = c end
	end
	assert(default and default.count > 50, "the default mod is a category")

	local found = catalog_api.items("all", "cobble")
	local has_cobble = false
	for i, r in ipairs(found) do
		if r.name == "default:cobble" then has_cobble = true end
		if i > 1 then assert(found[i - 1].key <= r.key, "sorted by title") end
	end
	assert(has_cobble, "search finds cobblestone")
	assert(#catalog_api.items("all", "no such item xyz") == 0)
	assert(#catalog_api.items("all", "") == #catalog_api.items("all"))
	assert(#catalog_api.items("all", "mossy cobble") < #catalog_api.items("all", "cobble"), "all words must match")
	assert(#catalog_api.items("all", "MOSSY") == #catalog_api.items("all", "mossy"), "search ignores case")

	local list = catalog_api.items("all")
	local slice, page, pages = catalog_api.page(list, 2, 24)
	assert(#slice == 24 and page == 2 and pages == math.ceil(#list / 24))
	_, page = catalog_api.page(list, 9999, 24)
	assert(page == pages, "a page past the end is clamped")
	_, page = catalog_api.page(list, -3, 24)
	assert(page == 1)
	callback()
end)

mtt.register("shop catalog: items that cannot be traded either way are left out", function(callback)
	pricing_api.generate({
		base = { ["default:dirt"] = 1, ["default:sand"] = 1, ["default:gravel"] = 1 },
		recipes = {}, groups = {}, hooks = {},
		flags = { ["default:dirt"] = { no_buy = true, no_sell = true }, ["default:sand"] = { no_buy = true } },
	})
	local names = {}
	for _, r in ipairs(catalog_api.items("all")) do names[r.name] = true end
	assert(not names["default:dirt"], "neither buyable nor sellable")
	assert(names["default:sand"] and names["default:gravel"])
	pricing_api.generate()
	local again = {}
	for _, r in ipairs(catalog_api.items("all")) do again[r.name] = true end
	assert(again["default:dirt"], "the catalog follows the regenerated prices")
	callback()
end)

---------------------------------------------------------------- shop: window

local function capture()
	local sent = {}
	local original = ui.send
	ui.send = function(name, spec) sent[name] = spec end
	return sent, function() ui.send = original end
end

local function click(name, fields)
	ui.handle(name, ui.state(name), fields)
end

local function pick_item(name, wanted)
	local state = ui.state(name)
	for i, record in ipairs(state.page_items or {}) do
		if record.name == wanted then return "item_" .. i end
	end
end

mtt.register("shop window: from search to a finished purchase and sale", function(callback)
	use("currency")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_win1", function(_, inv)
			inv:add_item("main", ItemStack("currency:minegeld")) -- 100 cents

			ui.open("shop_win1", "cobble")
			local state = ui.state("shop_win1")
			assert(state.screen == "items" and sent.shop_win1:find("formspec_version[6]", 1, true))
			assert(sent.shop_win1:find("Balance", 1, true) and sent.shop_win1:find("1.00", 1, true))
			local button = assert(pick_item("shop_win1", "default:cobble"), "cobblestone is listed")
			assert(sent.shop_win1:find(button, 1, true))
			assert(sent.shop_win1:find("tooltip[" .. button, 1, true), "items carry a tooltip")

			click("shop_win1", { [button] = "" })
			assert(state.screen == "trade" and state.item == "default:cobble" and state.amount == 1)
			assert(sent.shop_win1:find("BUY", 1, true) and sent.shop_win1:find("SELL", 1, true))

			click("shop_win1", { amount = "10", buy = "BUY" })
			assert(state.message and state.message.ok, "the purchase succeeded")
			assert(has_stack(inv, "default:cobble 10") and count_value(inv, CENTS) == 50)
			assert(sent.shop_win1:find("Bought", 1, true))

			click("shop_win1", { amount = "10", sellall = "x" })
			assert(state.message.ok and not has_stack(inv, "default:cobble"))
			assert(count_value(inv, CENTS) == 75, "sold 10 for 25: " .. count_value(inv, CENTS))
		end)
	end)
	restore()
	assert(ok, err)
	callback()
end)

mtt.register("shop window: amount controls and clamping", function(callback)
	use("currency")
	pricing_api.generate()
	local _, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_win2", function()
			ui.open("shop_win2", "cobble")
			click("shop_win2", { [pick_item("shop_win2", "default:cobble")] = "" })
			local state = ui.state("shop_win2")
			click("shop_win2", { p10 = "+10" })
			assert(state.amount == 11)
			click("shop_win2", { p64 = "+64" })
			assert(state.amount == 75)
			click("shop_win2", { m64 = "-64" })
			assert(state.amount == 11)
			click("shop_win2", { m64 = "-64", m10 = "-10" })
			assert(state.amount == 1, "never below 1")
			click("shop_win2", { amount = "abc" })
			assert(state.amount == 1, "text that is not a number is ignored")
			click("shop_win2", { amount = "99999999" })
			assert(state.amount == trade.max_amount(), "clamped to the purchase limit")
			click("shop_win2", { amount = "7.9" })
			assert(state.amount == 7)
		end)
	end)
	restore()
	assert(ok, err)
	callback()
end)

mtt.register("shop window: navigation and forged fields", function(callback)
	use("currency")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_win3", function(_, inv)
			inv:add_item("main", ItemStack("currency:minegeld"))
			ui.open("shop_win3")
			local state = ui.state("shop_win3")
			assert(state.screen == "categories" and state.page_categories[1] == "all")

			click("shop_win3", { cat_9999 = "" })
			click("shop_win3", { cat_0 = "" })
			click("shop_win3", { ["cat_1; evil"] = "" })
			click("shop_win3", { ["cat_1_t_x"] = "" })
			assert(state.screen == "categories", "positions that do not exist are ignored")
			click("shop_win3", { buy = "BUY", sell = "x", sellall = "x" })
			assert(not has_stack(inv, "default:cobble") and count_value(inv, CENTS) == 100,
				"trade buttons do nothing outside the trade screen")

			click("shop_win3", { cat_1 = "" })
			assert(state.screen == "items" and state.category == "all")
			click("shop_win3", { item_99999 = "" })
			assert(state.screen == "items", "no such item position")

			click("shop_win3", { next = "x" })
			assert(state.page == 2)
			click("shop_win3", { prev = "x" })
			click("shop_win3", { prev = "x" })
			assert(state.page == 1, "page never goes below 1")

			click("shop_win3", { do_search = "x", query = "stone" })
			assert(state.query == "stone" and state.page == 1)
			click("shop_win3", { back = "x" })
			assert(state.screen == "categories" and state.query == "")

			-- closing the window forgets the state
			assert(ui.on_fields(core.get_player_by_name("shop_win3"), "mine_shop_gui:shop", { quit = "true" }))
			assert(ui.state("shop_win3") == nil)
			assert(ui.on_fields(core.get_player_by_name("shop_win3"), "somebody_else:form", {}) == nil,
				"other forms are left alone")
		end)
	end)
	restore()
	assert(ok, err)
	callback()
end)

mtt.register("shop window: trade screen follows what an item allows", function(callback)
	use("currency")
	pricing_api.generate({
		base = { ["default:dirt"] = 1, ["default:sand"] = 1 },
		recipes = {}, groups = {}, hooks = {},
		flags = { ["default:dirt"] = { no_buy = true }, ["default:sand"] = { no_sell = true } },
	})
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_win4", function(_, inv)
			inv:set_stack("main", 1, ItemStack("default:dirt 20"))
			ui.open("shop_win4", "dirt")
			click("shop_win4", { [pick_item("shop_win4", "default:dirt")] = "" })
			assert(sent.shop_win4:find("Not sold by the shop", 1, true), "dirt cannot be bought")
			assert(not sent.shop_win4:find("button[1,7.5;3.6,1;buy;", 1, true), "so there is no buy button")
			assert(sent.shop_win4:find("sellall", 1, true), "but it can be sold")

			ui.open("shop_win4", "sand")
			click("shop_win4", { [pick_item("shop_win4", "default:sand")] = "" })
			assert(sent.shop_win4:find("The shop does not buy this", 1, true))
			assert(sent.shop_win4:find(";buy;", 1, true))
			assert(not sent.shop_win4:find(";sell;", 1, true), "sand cannot be sold")
		end)
	end)
	restore()
	pricing_api.generate()
	assert(ok, err)
	callback()
end)

mtt.register("shop window: the /shop command", function(callback)
	use("currency")
	pricing_api.generate()
	local command = core.registered_chatcommands["shop"]
	assert(command, "the command is registered")
	local sent, restore = capture()
	local ok, err = pcall(function()
		local done, message = command.func("shop_cmd1", "")
		assert(done == true and ui.state("shop_cmd1").screen == "categories" and sent.shop_cmd1)
		done = command.func("shop_cmd2", "cobble")
		assert(done == true and ui.state("shop_cmd2").screen == "items" and ui.state("shop_cmd2").query == "cobble")

		api.active = nil
		done, message = command.func("shop_cmd3", "")
		assert(done == false and message, "no currency, no shop")
		api.resolve()

		local was = pricing_api.generated
		pricing_api.generated = false
		done, message = command.func("shop_cmd4", "")
		pricing_api.generated = was
		assert(done == false and message, "prices not ready")
	end)
	restore()
	api.resolve()
	assert(ok, err)
	callback()
end)

---------------------------------------------------------------- shop: window syntax (formspec_ast)

local check_syntax -- defined below when formspec_ast is installed

if core.get_modpath("formspec_ast") then

-- Every element the window builder writes must survive parsing: the parser
-- drops anything malformed, so the counts per element type must agree.
local ELEMENTS = { "label", "button", "item_image_button", "item_image", "field", "tooltip",
	"field_close_on_enter", "box", "style" }

local function written(spec)
	local counts = {}
	for name in spec:gmatch("([%a_]+)%[") do counts[name] = (counts[name] or 0) + 1 end
	return counts
end

local function parsed(tree)
	local counts = {}
	for node in formspec_ast.walk(tree) do counts[node.type] = (counts[node.type] or 0) + 1 end
	return counts
end

function check_syntax(spec, what)
	local tree = formspec_ast.parse(spec)
	assert(tree, what .. ": the parser rejected the window")
	local want, got = written(spec), parsed(tree)
	for _, element in ipairs(ELEMENTS) do
		assert((want[element] or 0) == (got[element] or 0), string.format(
			"%s: %d x %s written but %d parsed", what, want[element] or 0, element, got[element] or 0))
	end
	assert(want.formspec_version == 1 and want.size == 1, what .. ": one version and one size")
end

mtt.register("shop window: every screen is valid formspec syntax", function(callback)
	use("currency")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_syntax", function(_, inv)
			inv:set_stack("main", 1, ItemStack("default:cobble 5"))
			inv:set_stack("main", 2, ItemStack("currency:minegeld"))

			ui.open("shop_syntax")
			check_syntax(sent.shop_syntax, "categories")

			click("shop_syntax", { cat_1 = "" })
			check_syntax(sent.shop_syntax, "items")
			click("shop_syntax", { next = "x" })
			check_syntax(sent.shop_syntax, "items, page 2")

			ui.open("shop_syntax", "cobble")
			check_syntax(sent.shop_syntax, "search results")
			ui.open("shop_syntax", "no such thing at all")
			check_syntax(sent.shop_syntax, "empty search")

			ui.open("shop_syntax", "cobble")
			click("shop_syntax", { [pick_item("shop_syntax", "default:cobble")] = "" })
			check_syntax(sent.shop_syntax, "trade")
			click("shop_syntax", { amount = "3", buy = "BUY" })
			check_syntax(sent.shop_syntax, "trade after a purchase")
			ui.state("shop_syntax").message = { ok = false, text = "a message, with [brackets]; and commas" }
			ui.show("shop_syntax")
			check_syntax(sent.shop_syntax, "trade with a message")
		end)
	end)
	restore()
	assert(ok, err)
	callback()
end)

end

---------------------------------------------------------------- shop: currency picture and symbol

mtt.register("currency icons: each adapter names a picture and a text mark", function(callback)
	local c = use("currency")
	assert(api.icon() == "currency:minegeld", "the 1.00 note stands for Minegeld")
	assert(c.number(125) == "1.25" and c.format_symbol(125) == "$1.25")

	local items = use("items")
	assert(api.icon() == "default:gold_ingot", "an item currency is shown by its smallest item: " .. tostring(api.icon()))
	assert(items.number(7) == "7")
	core.settings:set("mine_shop_gui_item_currency_label", "Gold")
	local text = items.format_symbol(7)
	core.settings:remove("mine_shop_gui_item_currency_label")
	assert(text == "7 Gold", "the label is the mark: " .. text)

	if api.adapters.credits.available() then
		local cr = use("credits")
		assert(api.icon() == "credits:credits" and cr.format_symbol(15) == "15 cr" and api.number(15) == "15")
	end
	if api.adapters.unified_money.available() then
		local um = use("unified_money")
		assert(api.icon() == nil, "Unified Money has no item")
		assert(um.format_symbol(15) == "$15" and api.number(15) == "15")
	end
	api.resolve()
	callback()
end)

mtt.register("currency icons: an icon that is not a registered item is ignored", function(callback)
	local fake = { name = "icon_test", icon = function() return "no_such_mod:coin" end,
		format = function(n) return tostring(n) end }
	local before = api.active
	api.active = fake
	local ok = api.icon() == nil and api.number(5) == "5" and api.format_symbol(5) == "5"
	api.active = before
	assert(ok)
	api.active = nil
	assert(api.icon() == nil and api.number(5) == "5" and api.format_symbol(5) == "5", "no currency at all")
	api.resolve()
	callback()
end)

mtt.register("shop window: prices and balance are drawn with the currency picture", function(callback)
	use("currency")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_icon1", function(_, inv)
			inv:set_stack("main", 1, ItemStack("currency:minegeld"))
			ui.open("shop_icon1")
			assert(sent.shop_icon1:find("item_image[10.9,0.45;0.5,0.5;currency:minegeld]", 1, true),
				"the balance has the note beside it")
			assert(sent.shop_icon1:find("label[11.5,0.7;1.00]", 1, true), "followed by the number")

			ui.open("shop_icon1", "cobble")
			local _, count = sent.shop_icon1:gsub("item_image%[[%d%.]+,[%d%.]+;0%.5,0%.5;currency:minegeld%]", "")
			assert(count == 1 + #ui.state("shop_icon1").page_items, "one in the header and one per priced item: " .. count)

			click("shop_icon1", { [pick_item("shop_icon1", "default:cobble")] = "" })
			assert(sent.shop_icon1:find("Buy (each):", 1, true) and sent.shop_icon1:find("You pay:", 1, true))
			assert(sent.shop_icon1:find("item_image[6.3,2.35;0.5,0.5;currency:minegeld]", 1, true),
				"the price per item has the note beside it")
			click("shop_icon1", { amount = "4", buy = "BUY" })
			assert(sent.shop_icon1:find("Bought", 1, true) and sent.shop_icon1:find("$0.20", 1, true),
				"messages use the text mark")
		end)
	end)
	restore()
	assert(ok, err)
	callback()
end)

mtt.register("shop window: a currency without an item uses its text mark", function(callback)
	if not api.adapters.unified_money.available() then callback() return end
	use("unified_money")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_icon2", function()
			unified_money.set_balance_safe("shop_icon2", 40)
			ui.open("shop_icon2")
			-- formspec text escapes the dollar sign as \$, which the client shows as $
			assert(sent.shop_icon2:find([=[label[10.9,0.7;\$40]]=], 1, true), "balance as text: " .. sent.shop_icon2:sub(1, 300))
			assert(not sent.shop_icon2:find("item_image[", 1, true), "no currency picture (the category buttons are separate)")
			ui.open("shop_icon2", "cobble")
			click("shop_icon2", { [pick_item("shop_icon2", "default:cobble")] = "" })
			assert(sent.shop_icon2:find("$1", 1, true), "prices with the dollar mark")
		end)
	end)
	restore()
	api.resolve()
	assert(ok, err)
	callback()
end)

if core.get_modpath("formspec_ast") then

mtt.register("shop window: the currency pictures keep the syntax valid", function(callback)
	use("currency")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_player("shop_icon3", function(_, inv)
			inv:set_stack("main", 1, ItemStack("currency:minegeld"))
			ui.open("shop_icon3")
			check_syntax(sent.shop_icon3, "categories with balance picture")
			ui.open("shop_icon3", "cobble")
			check_syntax(sent.shop_icon3, "items with price pictures")
			click("shop_icon3", { [pick_item("shop_icon3", "default:cobble")] = "" })
			check_syntax(sent.shop_icon3, "trade with price pictures")
		end)
	end)
	restore()
	assert(ok, err)
	callback()
end)

end

---------------------------------------------------------------- item currency: worth, format, money is not goods

mtt.register("item currency: an item without a value counts as 1", function(callback)
	local parse = api.adapters.items.parse_setting
	local list = parse("default:steel_ingot")
	assert(#list == 1 and list[1].name == "default:steel_ingot" and list[1].value == 1)
	list = parse(" mcl_core:emerald_block = 9 , mcl_core:emerald ,  default:gold_ingot=1")
	assert(#list == 3 and list[1].value == 9 and list[2].value == 1 and list[3].value == 1)
	assert(#parse("two words here") == 0, "something that is not an item name is ignored")
	assert(#parse("") == 0 and #parse(nil) == 0)
	callback()
end)

mtt.register("item currency: worth comes from the setting or from the shop's own price", function(callback)
	local items = use("items")
	pricing_api.generate()
	local smallest = items.smallest()
	assert(smallest.name == "default:gold_ingot" and smallest.value == 1, "the smallest item of the test currency")

	-- no setting: the shop's own price for the smallest item
	with_setting("mine_shop_gui_item_currency_worth", nil, function()
		local own = pricing_api.get("default:gold_ingot").price
		assert(near(items.worth(), own), "worth " .. items.worth() .. " against the price " .. own)
		assert(near(api.scale(), 1 / own))
	end)
	-- the owner decides
	with_setting("mine_shop_gui_item_currency_worth", "8", function()
		assert(items.worth() == 8 and near(api.scale(), 0.125))
		assert(api.price(16, "buy") == 2, "16 units cost 2 items when one item is worth 8")
		assert(api.price(40, "sell") == 3, "40 units sell for 2.5, rounded to 3 items")
	end)
	-- nonsense is ignored
	for _, bad in ipairs({ "0", "-4", "abc" }) do
		with_setting("mine_shop_gui_item_currency_worth", bad, function()
			assert(items.worth() > 0, "worth after '" .. bad .. "'")
		end)
	end
	-- an explicit scale still wins over the worth
	with_setting("mine_shop_gui_scale_items", "0.5", function()
		assert(api.scale() == 0.5)
	end)
	api.resolve()
	callback()
end)

mtt.register("item currency: the currency's own items are never sold in the shop", function(callback)
	use("items")
	pricing_api.generate()
	assert(api.is_money("default:gold_ingot") and not api.is_money("default:cobble"))
	local price, why = trade.quote("default:gold_ingot", 1, "buy")
	assert(price == nil and why == "not_for_sale", "no buying money")
	price, why = trade.quote("default:gold_ingot", 1, "sell")
	assert(price == nil and why == "not_for_sale", "no selling money")
	for _, record in ipairs(catalog_api.items("all")) do
		assert(record.name ~= "default:gold_ingot", "the catalog does not list the currency")
	end
	assert(catalog_api.items("all", "cobble")[1], "other items are still listed")

	-- with another currency active the same item is an ordinary good again
	use("currency")
	assert(not api.is_money("default:gold_ingot"))
	local found = false
	for _, record in ipairs(catalog_api.items("all")) do
		if record.name == "default:gold_ingot" then found = true end
	end
	assert(found, "listed again when it is not the currency")
	assert(trade.quote("default:gold_ingot", 1, "buy"))

	if api.adapters.credits.available() then
		use("credits")
		assert(api.is_money("credits:credits") and api.is_money("credits:credits_mkii"))
		assert(not api.is_money("default:gold_ingot"))
	end
	api.resolve()
	callback()
end)

mtt.register("item currency: the shop works end to end with an item currency", function(callback)
	local items = use("items")
	pricing_api.generate()
	local sent, restore = capture()
	local ok, err = pcall(function()
		with_setting("mine_shop_gui_item_currency_worth", "10", function()
			with_player("shop_item1", function(_, inv)
				inv:set_stack("main", 1, ItemStack("default:gold_ingot 3"))
				ui.open("shop_item1", "cobble")
				assert(sent.shop_item1:find("item_image[10.9,0.45;0.5,0.5;default:gold_ingot]", 1, true),
					"the currency item is the picture beside the balance")
				click("shop_item1", { [pick_item("shop_item1", "default:cobble")] = "" })
				-- 10 cobblestone = 10 units = 1 ingot
				click("shop_item1", { amount = "20", buy = "BUY" })
				assert(ui.state("shop_item1").message.ok, "bought")
				assert(has_stack(inv, "default:cobble 20") and trade.sellable_count("shop_item1", "default:cobble") == 20)
				assert(items.balance("shop_item1") == 1, "3 ingots - 2 = 1: " .. tostring(items.balance("shop_item1")))
				click("shop_item1", { sellall = "x" })
				-- 20 units * 0.5 = 10 units = 1 ingot
				assert(ui.state("shop_item1").message.ok and items.balance("shop_item1") == 2)
			end)
		end)
	end)
	restore()
	api.resolve()
	assert(ok, err)
	callback()
end)
