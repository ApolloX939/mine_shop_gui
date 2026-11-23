-- Adapter for the Noclip Cookie mod (a custom mod that is also named `currency`).
-- Whole cookies only.
--
-- A player's cookies are in two places: the "jar" (a stored balance, read and
-- written with cookies.get / cookies.set) and cookie items in the inventory.
-- Spending takes from the jar first, then from the inventory. Payouts always go
-- to the jar, so they never need inventory room.

local ITEM = "currency:cookie"

local adapter = { name = "cookies" }

local function jar_api()
	return rawget(_G, "cookies")
end

function adapter.available()
	local c = jar_api()
	return type(c) == "table"
		and type(c.get) == "function"
		and type(c.set) == "function"
		and core.registered_items[ITEM] ~= nil
end

adapter.default_scale = 1

function adapter.unit()
	return 1
end

function adapter.round(amount)
	return math.floor(amount + 0.5)
end

function adapter.is_money(item)
	return item == ITEM
end

function adapter.stack_value(stack)
	if stack:get_name() ~= ITEM then return nil end
	return stack:get_count()
end

local function get_inventory(player)
	local obj = core.get_player_by_name(player)
	return obj and obj:get_inventory()
end

local function refresh_hud(player)
	local c = jar_api()
	if type(c.hud_update) == "function" then c.hud_update(player) end
end

local function in_inventory(inv)
	local total = 0
	for _, stack in ipairs(inv:get_list("main")) do
		if stack:get_name() == ITEM then total = total + stack:get_count() end
	end
	return total
end

function adapter.snapshot(player)
	local inv = get_inventory(player)
	if not inv then return nil end
	return { jar = jar_api().get(player), list = inv:get_list("main") }
end

function adapter.restore(player, snapshot)
	local inv = get_inventory(player)
	if not inv then return end
	inv:set_list("main", snapshot.list)
	jar_api().set(player, snapshot.jar)
	refresh_hud(player)
end

function adapter.balance(player)
	local inv = get_inventory(player)
	if not inv then return nil end
	return jar_api().get(player) + in_inventory(inv)
end

function adapter.withdraw(player, amount)
	local api = mine_shop_gui.currency
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount == 0 then return true end
	local inv = get_inventory(player)
	if not inv then return false, "unavailable" end

	local c = jar_api()
	local jar = c.get(player)
	if jar + in_inventory(inv) < amount then return false, "insufficient_funds" end

	local from_jar = math.min(jar, amount)
	local from_inv = amount - from_jar
	local list = inv:get_list("main")
	if from_inv > 0 then
		local removed = inv:remove_item("main", ItemStack(ITEM .. " " .. from_inv))
		if removed:get_count() ~= from_inv then
			inv:set_list("main", list)
			return false, "unavailable"
		end
	end
	if from_jar > 0 and not c.set(player, jar - from_jar) then
		inv:set_list("main", list)
		return false, "unavailable"
	end
	refresh_hud(player)
	return true
end

function adapter.deposit(player, amount)
	local api = mine_shop_gui.currency
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount == 0 then return true end
	local c = jar_api()
	if not get_inventory(player) or not c.set(player, c.get(player) + amount) then
		return false, "unavailable"
	end
	refresh_hud(player)
	return true
end

function adapter.format(amount)
	return amount .. (amount == 1 and " cookie" or " cookies")
end

function adapter.number(amount)
	return tostring(amount)
end

function adapter.format_symbol(amount)
	return amount .. " ck"
end

function adapter.icon()
	return ITEM
end

mine_shop_gui.currency.register(adapter)
