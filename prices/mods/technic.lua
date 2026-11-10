-- Technic (the `technic` mod itself).
--
-- Nothing is listed on purpose. Technic's grinder turns 1 ore lump into 2 dust,
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

return {}
