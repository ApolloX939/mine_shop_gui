-- The /ah chat command:
--   /ah                                  open the auction house
--   /ah sell hand|<itemstring>|<name> [<amount>|all]   offer items at a fixed price
--   /ah bid  hand|<itemstring>|<name> [<amount>|all]   offer items for bidding
--   /ah claim                            collect deliveries that were waiting
--   /ah revoke <number>                  take an offer down (yours, or any as an admin)
--
-- sell and bid take the items out of your inventory and open the window where
-- you set the price. "hand" takes the stack in your hand; anything else takes
-- one item unless you say how many.

local api = mine_shop_gui.currency
local A = mine_shop_gui.auction
local ui = A.ui
local sell_command = mine_shop_gui.shop.sell_command

local S = core.get_translator(core.get_current_modname())

local M = {}

-- Names of the items in an inventory, with how many of each.
local function held(inv)
	local totals = {}
	for _, stack in ipairs(inv:get_list("main")) do
		if not stack:is_empty() then
			totals[stack:get_name()] = (totals[stack:get_name()] or 0) + stack:get_count()
		end
	end
	return totals
end

-- The held item a name or itemstring stands for. Returns the item, or nil plus a message.
local function find_item(inv, target)
	local totals = held(inv)
	if target:find(":", 1, true) then
		if not core.registered_items[target] then return nil, S("Unknown item: @1", target) end
		if not totals[target] then return nil, S("You do not have any @1.", target) end
		return target
	end
	local wanted, exact, partial = target:lower(), {}, {}
	for name in pairs(totals) do
		local title = A.title(name):lower()
		if title == wanted then
			exact[#exact + 1] = name
		else
			local haystack, all = title .. " " .. name:lower(), true
			for word in wanted:gmatch("%S+") do
				if not haystack:find(word, 1, true) then all = false break end
			end
			if all then partial[#partial + 1] = name end
		end
	end
	local matches = #exact > 0 and exact or partial
	table.sort(matches)
	if #matches == 0 then return nil, S("You have nothing that matches \"@1\".", target) end
	if #matches > 1 then
		local names = {}
		for i = 1, math.min(#matches, 8) do names[i] = A.title(matches[i]) .. " (" .. matches[i] .. ")" end
		return nil, S("More than one item matches: @1. Use the full name.", table.concat(names, ", "))
	end
	return matches[1]
end

-- Take up to `amount` of `item` out of the inventory, whole stacks first, with
-- their wear and metadata. At most 8 stacks. Returns a list of ItemStacks.
local function take(inv, item, amount)
	local max = (core.registered_items[item].stack_max or 99)
	local list, taken = inv:get_list("main"), {}
	amount = math.min(amount, max * A.MAX_STACKS)
	for _, stack in ipairs(list) do
		if amount == 0 or #taken == A.MAX_STACKS then break end
		if stack:get_name() == item then
			local part = stack:take_item(math.min(amount, stack:get_count()))
			amount = amount - part:get_count()
			taken[#taken + 1] = part
		end
	end
	inv:set_list("main", list)
	return taken
end

-- Take what the player named. Returns a list of stacks, or nil plus a message.
function M.take_items(player_name, target, amount)
	local player = core.get_player_by_name(player_name)
	if not player then return nil, ui.REASONS.unavailable end
	local inv = player:get_inventory()

	if target:lower() == "hand" then
		local wielded = player:get_wielded_item()
		if wielded:is_empty() then return nil, S("You are not holding anything.") end
		local count = amount == "all" and wielded:get_count() or math.min(amount or wielded:get_count(), wielded:get_count())
		local part = wielded:take_item(count)
		player:set_wielded_item(wielded)
		return { part }
	end

	local item, why = find_item(inv, target)
	if not item then return nil, why end
	if amount == "all" then amount = held(inv)[item] end
	return take(inv, item, amount or 1)
end

local function open_offer_window(name, kind, param)
	local target, amount = sell_command.parse(param)
	if not target then return false, amount end
	if target == "" then
		ui.open_create(name, kind)
		return true
	end
	local stacks, why = M.take_items(name, target, amount)
	if not stacks then return false, why end
	ui.open_create(name, kind, stacks)
	return true
end

function M.run(name, param)
	if not api.get() then return false, S("The auction house has no currency to trade with.") end
	param = (param or ""):gsub("^%s+", "")
	local command, rest = param:match("^(%S+)%s*(.*)$")
	command = command and command:lower()

	if not command then
		ui.open(name)
		return true
	elseif command == "sell" or command == "bid" then
		return open_offer_window(name, command, rest)
	elseif command == "claim" then
		local items, money, left = A.claim(name)
		if items == 0 and money == 0 and left == 0 then return true, S("Nothing is waiting for you.") end
		return true, S("Received @1 items and @2.", items, api.format_symbol(money))
			.. (left > 0 and " " .. S("@1 still waiting.", left) or "")
	elseif command == "revoke" then
		local id = tonumber(rest)
		if not id then return false, S("Usage: /ah revoke <offer number>") end
		local ok, result = A.revoke(name, id)
		if not ok then return false, ui.REASONS[result] or ui.REASONS.unavailable end
		return true, S("Offer #@1 was taken down.", id)
	end
	return false, S("Usage: /ah [sell|bid hand|<itemstring>|<item name> [<amount>|all]] | claim | revoke <number>")
end

core.register_chatcommand("ah", {
	params = S("[sell|bid hand|<itemstring>|<item name> [<amount>|all]] | claim | revoke <number>"),
	description = S("Open the auction house"),
	func = M.run,
})

A.command = M
