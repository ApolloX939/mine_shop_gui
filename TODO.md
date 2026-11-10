# TODO

Decisions go in `PLAN.md` once answered.

## Open questions

All answered; see `PLAN.md`.

- [x] When several currencies are installed, should a server setting pick one, or should the player choose? (Suggested: setting with auto-detection as the default.)
- [x] Base prices: use a Lua/JSON file of hand-set prices for raw items, seeded from the installed mods' ores?
- [x] Sell price: a fixed fraction of the buy price (for example 50%) set in `settingtypes.txt`?
- [x] How should prices finer than 5 cents be handled for `currency` (round to nearest 5)?

## Tasks

- [x] Pricing derivation core (`src/pricing/derive.lua`) with tests.
- [x] Recipe collector, flags (`no_buy` / `no_sell`), markup settings and the whole-table price hook. See `PLAN.md`.
- [x] Base price file format (Lua) and loader, with tests.
- [x] Price files split into `prices/games/` and `prices/mods/`, seeded for Minetest Game and Technic.
- [ ] After the collector exists, run the derivation on the real recipes and add anchors for items that are still unpriced (cycles, items only made by skipped recipes).
- [ ] Decide prices for Ethereal, Everness, Techage and other content mods (currently unpriced).
- [ ] Add price files for the other games (`mineclonia`, `mineclone2`) when you want to support them.
- [x] Run the derivation on the real recipes (51-mod world): 410 priced, no unstable loops.
- [ ] Review the 410 derived prices for odd values (for example Technic dusts and machine-made items).
- [ ] Anchors for natural items: clay lump, cactus, papyrus, ice, snow, obsidian, wheat, cotton, string. Needs your price values.
- [ ] Document the flags and the price hook for other mod authors in `README.md`.

- [x] Write the currency adapter layer (`currency`, `unified_money`, `credits`, `items` behind one interface).
- [x] Check Technic's recipe registration API for machine recipes. See `PLAN.md`.
- [x] Add `mod.conf` and `init.lua`.
- [ ] Build the base price list and the recipe-derived pricing.
- [ ] Build the Buy/Sell formspec with a variable amount.
- [ ] Verify the `credits_old` item-prefix load failure in a test world.
- [ ] Test the `credits` V1.2.3 code path in the engine (needs a world with only the old version, and `credits_old` item-prefix handling).
- [x] Decide how prices are scaled across currencies (cents vs whole credits vs item units). See `PLAN.md`.
- [ ] Check that `unified_money` accepts the amounts we pass (it may allow fractions; the adapter currently only accepts whole numbers).
- [ ] Add a `.luarc.json` or `.luacheckrc` so editors know the Minetest globals.
