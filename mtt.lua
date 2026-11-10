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
