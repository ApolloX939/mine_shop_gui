-- Adapter for the `credits` mod, both V1.2.3 and V1.3. Whole numbers only.
--
-- V1.2.3: credits:credits = 1, credits_mkii = 9, credits_mkiii = 81.
-- V1.3:   credits:credits is worth count * its "value" metadata. A stack with
--         no value is worth 0 (the mod itself ignores it), and Mk2/Mk3 are worth 0.
--
-- Spending takes the digital balance first, then physical stacks. Any surplus
-- from a physical stack is returned to the digital balance, so we never have
-- to create valued stacks. Payouts are always digital.

local adapter = { name = "credits" }

local function mod()
	return rawget(_G, "credits")
end

function adapter.available()
	local c = mod()
	return type(c) == "table"
		and type(c.get_balance_digital) == "function"
		and type(c.add_coin) == "function"
		and core.registered_items["credits:credits"] ~= nil
end

-- V1.3 adds get_balance_physical_all and a `value` field on the item.
local function is_valued()
	local c = mod()
	if c.get_balance_physical_all then return true end
	local def = core.registered_items["credits:credits"]
	return def ~= nil and def.value ~= nil
end

local OLD_MULTIPLIER = {
	["credits:credits"] = 1,
	["credits:credits_mkii"] = 9,
	["credits:credits_mkiii"] = 81,
}

local function stack_value(stack, valued)
	local name = stack:get_name()
	if valued then
		if name ~= "credits:credits" then return 0 end
		local meta = stack:get_meta()
		if not meta:contains("value") then return 0 end
		return math.max(0, meta:get_int("value")) * stack:get_count()
	end
	return (OLD_MULTIPLIER[name] or 0) * stack:get_count()
end

local function get_inventory(player)
	local obj = core.get_player_by_name(player)
	return obj and obj:get_inventory()
end

adapter.default_scale = 1

function adapter.unit()
	return 1
end

function adapter.round(amount)
	return math.floor(amount + 0.5)
end

function adapter.is_money(item)
	return item == "credits:credits" or item == "credits:credits_mkii" or item == "credits:credits_mkiii"
end

function adapter.stack_value(stack)
	if not adapter.is_money(stack:get_name()) then return nil end
	return stack_value(stack, is_valued())
end

function adapter.snapshot(player)
	local inv = get_inventory(player)
	if not inv then return nil end
	return { digital = mod().get_balance_digital(player), list = inv:get_list("main") }
end

function adapter.restore(player, snapshot)
	local inv = get_inventory(player)
	if inv then inv:set_list("main", snapshot.list) end
	-- add_coin changes the balance by an amount, so apply the difference
	local difference = snapshot.digital - mod().get_balance_digital(player)
	if difference ~= 0 then mod().add_coin(player, difference) end
end

function adapter.balance(player)
	local inv = get_inventory(player)
	if not inv then return nil end
	local valued = is_valued()
	local total = mod().get_balance_digital(player)
	for _, stack in ipairs(inv:get_list("main")) do
		total = total + stack_value(stack, valued)
	end
	return total
end

function adapter.withdraw(player, amount)
	local api = mine_shop_gui.currency
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount == 0 then return true end
	local inv = get_inventory(player)
	if not inv then return false, "unavailable" end

	local c = mod()
	local valued = is_valued()
	local list = inv:get_list("main")
	local digital = c.get_balance_digital(player)
	local physical = 0
	for _, stack in ipairs(list) do
		physical = physical + stack_value(stack, valued)
	end
	if digital + physical < amount then return false, "insufficient_funds" end

	local from_digital = math.min(digital, amount)
	local need = amount - from_digital
	local surplus = 0
	if need > 0 then
		local removed = 0
		for i, stack in ipairs(list) do
			if removed >= need then break end
			local value = stack_value(stack, valued)
			if value > 0 then
				removed = removed + value
				list[i] = ItemStack()
			end
		end
		inv:set_list("main", list)
		surplus = removed - need
	end

	-- add_coin clamps silently at 0, but we checked the balance above.
	if from_digital > 0 then c.add_coin(player, -from_digital) end
	if surplus > 0 then c.add_coin(player, surplus) end
	return true
end

function adapter.deposit(player, amount)
	local api = mine_shop_gui.currency
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount == 0 then return true end
	mod().add_coin(player, amount)
	return true
end

function adapter.format(amount)
	return tostring(amount)
end

function adapter.format_symbol(amount)
	return tostring(amount) .. " cr"
end

function adapter.icon()
	return "credits:credits"
end

mine_shop_gui.currency.register(adapter)
