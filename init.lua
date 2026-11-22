-- Mine ShopGUI entry point.

mine_shop_gui = {
	modname = core.get_current_modname(),
}
mine_shop_gui.modpath = core.get_modpath(mine_shop_gui.modname)

local function load(path)
	dofile(mine_shop_gui.modpath .. "/" .. path .. ".lua")
end

-- Currency layer: one interface over every supported currency.
load("src/currency/api")
load("src/currency/denominations")
load("src/currency/currency")
load("src/currency/unified_money")
load("src/currency/credits")
load("src/currency/cookies")
load("src/currency/items")

-- Pricing: derives item prices from base prices and recipes.
mine_shop_gui.pricing = {
	derive = dofile(mine_shop_gui.modpath .. "/src/pricing/derive.lua"),
	base_prices = dofile(mine_shop_gui.modpath .. "/src/pricing/base_prices.lua"),
}

dofile(mine_shop_gui.modpath .. "/src/pricing/generate.lua")

-- Build prices once every mod (and every on_mods_loaded callback, including
-- Technic's own recipe registration) is done.
core.register_on_mods_loaded(function()
	core.after(0, function() mine_shop_gui.pricing.generate() end)
end)

-- The shop window: trading, the item list, and the /shop command.
mine_shop_gui.shop = {}
load("src/shop/trade")
load("src/shop/catalog")
load("src/shop/ui")
load("src/shop/sell_command")

-- Integration tests, only when the mtt test framework is enabled.
if core.get_modpath("mtt") and mtt and mtt.enabled then
	load("mtt")
end

-- Adapters are only usable once every mod has registered its items and globals.
core.register_on_mods_loaded(mine_shop_gui.currency.resolve)
