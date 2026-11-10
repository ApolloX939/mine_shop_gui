-- Adapter for plain items used as money, configured by the
-- `mine_shop_gui_item_currency` setting (for example emeralds under
-- Mineclonia or VoxeLibre).
--
-- Setting format: "itemname=value, itemname=value". Values are whole numbers
-- of the smallest unit. An item written without a value ("default:steel_ingot")
-- is worth 1.
--
-- How much one unit is worth in the shop is set with
-- `mine_shop_gui_item_currency_worth`, in price units (1 = one cobblestone).
-- Left empty, the shop's own price for the smallest item is used.

local function parse(text)
	local list = {}
	for entry in (text or ""):gmatch("[^,]+") do
		local name, value = entry:match("^%s*([^=%s]+)%s*=%s*(%d+)%s*$")
		if not name then
			name = entry:match("^%s*([^=%s]+)%s*$")
			value = name and "1"
		end
		if name then
			list[#list + 1] = { name = name, value = tonumber(value) }
		else
			core.log("warning", "[mine_shop_gui] ignoring invalid item currency entry: '"
				.. entry:gsub("^%s+", ""):gsub("%s+$", "") .. "'")
		end
	end
	return list
end

local adapter = mine_shop_gui.currency_denominations.new({
	name = "items",
	warn_missing = true,
	get_denominations = function()
		return parse(core.settings:get("mine_shop_gui_item_currency"))
	end,
	format = function(amount)
		local label = core.settings:get("mine_shop_gui_item_currency_label")
		if label and label ~= "" then
			return amount .. " " .. label
		end
		return tostring(amount)
	end,
	number = function(amount) return tostring(amount) end,
})

-- Price units that one unit of this currency is worth. The owner can set it;
-- otherwise the smallest currency item is worth what the shop prices it at.
local DEFAULT_WORTH = 20

function adapter.worth()
	local worth = tonumber(core.settings:get("mine_shop_gui_item_currency_worth"))
	if worth and worth > 0 then return worth end
	local smallest = adapter.smallest()
	local entry = smallest and mine_shop_gui.pricing and mine_shop_gui.pricing.get(smallest.name)
	if entry and entry.price > 0 then return entry.price / smallest.value end
	return DEFAULT_WORTH
end

-- amount per price unit: the inverse of what one unit is worth
function adapter.scale()
	return 1 / adapter.worth()
end

adapter.parse_setting = parse

mine_shop_gui.currency.register(adapter)
