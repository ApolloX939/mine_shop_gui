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
load("src/currency/items")

-- Pricing: derives item prices from base prices and recipes.
mine_shop_gui.pricing = {
	derive = dofile(mine_shop_gui.modpath .. "/src/pricing/derive.lua"),
}

-- Integration tests, only when the mtt test framework is enabled.
if core.get_modpath("mtt") and mtt and mtt.enabled then
	load("mtt")
end

-- Adapters are only usable once every mod has registered its items and globals.
core.register_on_mods_loaded(mine_shop_gui.currency.resolve)
