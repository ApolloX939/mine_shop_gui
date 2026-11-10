-- Buying and selling. No interface code here: the shop window calls these.
--
-- Every function returns true plus a table of details, or false plus a reason:
--   "invalid_amount", "not_for_sale", "not_enough", "too_cheap",
--   "insufficient_funds", "no_room", "unavailable".
-- A trade is atomic: the payment and the goods both happen, or neither does.

local api = mine_shop_gui.currency
local pricing = mine_shop_gui.pricing
local collect = pricing.collect

local T = {}

-- The largest amount that can be bought at once (setting mine_shop_gui_max_amount).
function T.max_amount()
	local value = tonumber(core.settings:get("mine_shop_gui_max_amount")) or 1000
	return math.max(1, math.floor(value))
end

local function inventory_of(player_name)
	local player = core.get_player_by_name(player_name)
	return player and player:get_inventory()
end

-- Slots holding `item` that may be sold: undamaged, not flagged no_sell, and
-- the item itself not flagged. Returns the slots and how many items they hold.
local function sellable_slots(inv, item)
	local slots, total = {}, 0
	for index, stack in ipairs(inv:get_list("main")) do
		if not stack:is_empty() and collect.resolve(stack:get_name()) == item
				and stack:get_wear() == 0 and pricing.can_sell(stack) then
			slots[#slots + 1] = { index = index, count = stack:get_count() }
			total = total + stack:get_count()
		end
	end
	return slots, total
end

-- How many of `item` the player holds that the shop would accept.
function T.sellable_count(player_name, item)
	local inv = inventory_of(player_name)
	if not inv then return 0 end
	local _, total = sellable_slots(inv, collect.resolve(item))
	return total
end

-- The price of `amount` of `item` in the active currency, or nil plus a reason.
-- mode is "buy" (what the player pays) or "sell" (what the player receives).
function T.quote(item, amount, mode)
	item = collect.resolve(item)
	local entry = pricing.get(item)
	if not entry or api.is_money(item) then return nil, "not_for_sale" end
	if (mode == "buy" and entry.no_buy) or (mode == "sell" and entry.no_sell) then
		return nil, "not_for_sale"
	end
	if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < 1 then
		return nil, "invalid_amount"
	end
	if mode == "buy" and amount > T.max_amount() then return nil, "invalid_amount" end
	return api.price(entry.price * amount, mode)
end

-- The smallest amount worth selling (the payout must reach one coin), or nil.
function T.min_sell_amount(item)
	local entry = pricing.get(collect.resolve(item))
	if not entry or entry.no_sell then return nil end
	for n = 1, 10000 do
		if T.quote(item, n, "sell") then return n end
	end
	return nil
end

-- Undo a payment: the money and the inventory go back to how they were.
local function undo(player_name, inv, inventory_before, money_before)
	api.restore(player_name, money_before)
	inv:set_list("main", inventory_before)
end

function T.buy(player_name, item, amount)
	item = collect.resolve(item)
	local cost, why = T.quote(item, amount, "buy")
	if not cost then return false, why end
	local inv = inventory_of(player_name)
	if not inv then return false, "unavailable" end

	local inventory_before = inv:get_list("main")
	local money_before = api.snapshot(player_name)
	local paid, reason = api.withdraw(player_name, cost)
	if not paid then return false, reason end

	-- hand over the goods, one stack at a time
	local stack_max = core.registered_items[item].stack_max or 99
	local remaining = amount
	while remaining > 0 do
		local n = math.min(remaining, stack_max)
		local leftover = inv:add_item("main", ItemStack({ name = item, count = n }))
		if not leftover:is_empty() then
			undo(player_name, inv, inventory_before, money_before)
			return false, "no_room"
		end
		remaining = remaining - n
	end
	return true, { item = item, amount = amount, cost = cost }
end

function T.sell(player_name, item, amount)
	item = collect.resolve(item)
	local payout, why = T.quote(item, amount, "sell")
	if not payout then return false, why end
	local inv = inventory_of(player_name)
	if not inv then return false, "unavailable" end

	local slots, total = sellable_slots(inv, item)
	if total < amount then return false, "not_enough" end

	local inventory_before = inv:get_list("main")
	local money_before = api.snapshot(player_name)

	-- take exactly `amount`, only from slots the shop accepts
	local list = inv:get_list("main")
	local remaining = amount
	for _, slot in ipairs(slots) do
		if remaining == 0 then break end
		local take = math.min(remaining, slot.count)
		list[slot.index]:take_item(take)
		remaining = remaining - take
	end
	inv:set_list("main", list)

	local paid, reason = api.deposit(player_name, payout)
	if not paid then
		undo(player_name, inv, inventory_before, money_before)
		return false, reason
	end
	return true, { item = item, amount = amount, payout = payout }
end

-- Sell everything the shop will accept of `item`.
function T.sell_all(player_name, item)
	local count = T.sellable_count(player_name, item)
	if count == 0 then return false, "not_enough" end
	return T.sell(player_name, item, count)
end

mine_shop_gui.shop = mine_shop_gui.shop or {}
mine_shop_gui.shop.trade = T
