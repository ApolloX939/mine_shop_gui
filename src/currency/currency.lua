-- Adapter for the `currency` mod (Minegeld).
-- Amounts are in cents. The bundle item is deliberately not supported.

local adapter = mine_shop_gui.currency_denominations.new({
	name = "currency",
	get_denominations = function()
		return {
			-- coins
			{ name = "currency:minegeld_cent_5", value = 5 },
			{ name = "currency:minegeld_cent_10", value = 10 },
			{ name = "currency:minegeld_cent_25", value = 25 },
			-- notes
			{ name = "currency:minegeld", value = 100 },
			{ name = "currency:minegeld_5", value = 500 },
			{ name = "currency:minegeld_10", value = 1000 },
			{ name = "currency:minegeld_50", value = 5000 },
			{ name = "currency:minegeld_100", value = 10000 },
		}
	end,
	format = function(cents)
		return string.format("%d.%02d", math.floor(cents / 100), cents % 100)
	end,
})

-- Only offer this adapter when the mod itself is present.
local available = adapter.available
adapter.available = function()
	return core.get_modpath("currency") ~= nil and available()
end

mine_shop_gui.currency.register(adapter)
