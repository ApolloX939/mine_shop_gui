-- Adapter for plain items used as money, configured by the
-- `mine_shop_gui_item_currency` setting (for example emeralds under
-- Mineclonia or VoxeLibre).
--
-- Setting format: "itemname=value, itemname=value". Values are whole numbers
-- of the smallest unit.

local function parse(text)
	local list = {}
	for entry in (text or ""):gmatch("[^,]+") do
		local name, value = entry:match("^%s*([^=%s]+)%s*=%s*(%d+)%s*$")
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
})

mine_shop_gui.currency.register(adapter)
