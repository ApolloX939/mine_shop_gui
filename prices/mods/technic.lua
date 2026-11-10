-- Technic (the `technic` mod itself).
--
-- Ingot prices are not listed on purpose. Technic's grinder turns 1 ore lump into 2 dust,
-- and a dust smelts to 1 ingot, so with Technic installed an ingot really costs
-- half of its lump. The price derivation assumes players always grind (it takes
-- the cheapest route), so the drop happens by itself and only when Technic is
-- present: the lump prices in prices/games/*.lua stay as they are.
--
--   Minetest Game alone:   iron lump 16 -> steel ingot 16
--   with Technic:          iron lump 16 -> steel ingot  8
--
-- Do not set ingot prices here. A fixed ingot price would override the
-- derivation and go stale when a lump price changes. To soften the drop, raise
-- the `mine_shop_gui_markup_grinding` setting (100 makes ingots cost the same
-- as their lump again).

-- Uranium enrichment. The centrifuge makes the dusts of other enrichments from
-- natural uranium (technic:uranium_dust, about 30 once ground), but it has two
-- outputs, which the price derivation skips. So the dusts are listed here:
-- 30 * (0.5 + percent / 14), natural uranium (0.7%) being 30. The ingots and
-- fuel are priced from these.

return {
	["technic:uranium0_dust"] = 15,
	["technic:uranium1_dust"] = 17.1,
	["technic:uranium2_dust"] = 19.3,
	["technic:uranium3_dust"] = 21.4,
	["technic:uranium4_dust"] = 23.6,
	["technic:uranium5_dust"] = 25.7,
	["technic:uranium6_dust"] = 27.9,
	["technic:uranium8_dust"] = 32.1,
	["technic:uranium9_dust"] = 34.3,
	["technic:uranium10_dust"] = 36.4,
	["technic:uranium11_dust"] = 38.6,
	["technic:uranium12_dust"] = 40.7,
	["technic:uranium13_dust"] = 42.9,
	["technic:uranium14_dust"] = 45,
	["technic:uranium15_dust"] = 47.1,
	["technic:uranium16_dust"] = 49.3,
	["technic:uranium17_dust"] = 51.4,
	["technic:uranium18_dust"] = 53.6,
	["technic:uranium19_dust"] = 55.7,
	["technic:uranium20_dust"] = 57.9,
	["technic:uranium21_dust"] = 60,
	["technic:uranium22_dust"] = 62.1,
	["technic:uranium23_dust"] = 64.3,
	["technic:uranium24_dust"] = 66.4,
	["technic:uranium25_dust"] = 68.6,
	["technic:uranium26_dust"] = 70.7,
	["technic:uranium27_dust"] = 72.9,
	["technic:uranium28_dust"] = 75,
	["technic:uranium29_dust"] = 77.1,
	["technic:uranium30_dust"] = 79.3,
	["technic:uranium31_dust"] = 81.4,
	["technic:uranium32_dust"] = 83.6,
	["technic:uranium33_dust"] = 85.7,
	["technic:uranium34_dust"] = 87.9,
	["technic:uranium35_dust"] = 90,
}
