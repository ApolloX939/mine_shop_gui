-- The /sell chat command:
--   /sell hand [amount|all]            the item in the hand
--   /sell <itemstring> [amount|all]    for example default:cobble 20
--   /sell <item name> [amount|all]     for example Gold Ingot all
-- Without an amount, one item is sold; "hand" sells the whole stack in the hand.

local api = mine_shop_gui.currency
local pricing = mine_shop_gui.pricing
local trade = mine_shop_gui.shop.trade
local catalog = mine_shop_gui.shop.catalog
local ui = mine_shop_gui.shop.ui
local collect = pricing.collect

local S = core.get_translator(core.get_current_modname())

local M = {}

-- Split "Gold Ingot 5" into "Gold Ingot" and 5. The amount is a number, "all",
-- or nothing. Returns target, amount, or nil plus a message for a bad amount.
function M.parse(param)
	local words = {}
	for word in (param or ""):gmatch("%S+") do words[#words + 1] = word end
	local amount
	local last = words[#words]
	if #words > 1 and last then
		if last:lower() == "all" then
			amount = "all"
			words[#words] = nil
		elseif tonumber(last) then
			local number = tonumber(last)
			if number ~= math.floor(number) or number < 1 then
				return nil, ui.REASONS.invalid_amount
			end
			amount = number
			words[#words] = nil
		end
	end
	return table.concat(words, " "), amount
end

-- The item a name or itemstring stands for among what the player holds.
-- Returns the item name, or nil plus a message.
local function find_item(player_name, target)
	if target:find(":", 1, true) then
		local item = collect.resolve(target)
		if not core.registered_items[item] then
			return nil, S("Unknown item: @1", target)
		end
		return item
	end

	local held = trade.sellable_items(player_name)
	local wanted = target:lower()
	local exact, partial = {}, {}
	for _, entry in ipairs(held) do
		local title = catalog.title(entry.name):lower()
		if title == wanted then
			exact[#exact + 1] = entry.name
		else
			local haystack = title .. " " .. entry.name:lower()
			local all = true
			for word in wanted:gmatch("%S+") do
				if not haystack:find(word, 1, true) then all = false break end
			end
			if all then partial[#partial + 1] = entry.name end
		end
	end
	local matches = #exact > 0 and exact or partial
	if #matches == 0 then
		return nil, S("You have nothing the shop will buy that matches \"@1\".", target)
	end
	if #matches > 1 then
		local names = {}
		for i = 1, math.min(#matches, 8) do
			names[i] = catalog.title(matches[i]) .. " (" .. matches[i] .. ")"
		end
		return nil, S("More than one item matches: @1. Use the full name.", table.concat(names, ", "))
	end
	return matches[1]
end

function M.run(player_name, param)
	if not pricing.generated then
		return false, S("The shop is not ready yet. Try again in a moment.")
	end
	if not api.get() then
		return false, S("The shop has no currency to trade with.")
	end
	local player = core.get_player_by_name(player_name)
	if not player then return false, ui.REASONS.unavailable end

	local target, amount = M.parse(param)
	if not target then return false, amount end
	if target == "" then
		return false, S("Usage: /sell hand|<itemstring>|<item name> [<amount>|all]")
	end

	local item
	if target:lower() == "hand" then
		local wielded = player:get_wielded_item()
		if wielded:is_empty() then return false, S("You are not holding anything.") end
		item = collect.resolve(wielded:get_name())
		if amount == nil then amount = wielded:get_count() end
	else
		local why
		item, why = find_item(player_name, target)
		if not item then return false, why end
	end
	amount = amount or 1

	local ok, result
	if amount == "all" then
		ok, result = trade.sell_all(player_name, item)
	else
		ok, result = trade.sell(player_name, item, amount)
	end
	if not ok then return false, ui.REASONS[result] or ui.REASONS.unavailable end
	return true, S("Sold @1 x @2 for @3.", result.amount, catalog.title(item), api.format_symbol(result.payout))
end

core.register_chatcommand("sell", {
	params = S("hand|<itemstring>|<item name> [<amount>|all]"),
	description = S("Sell items from your inventory to the shop"),
	func = M.run,
})

mine_shop_gui.shop.sell_command = M
