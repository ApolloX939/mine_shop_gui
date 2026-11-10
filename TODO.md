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
- [ ] Recipe collector: `core.get_all_craft_recipes` plus `technic.recipes`, single-output only, group membership, after technic's callback (add `technic` to `optional_depends`).
- [ ] Base price file (format, loading) and a seed list from the raw items in the installed mods.
- [ ] Markup settings per recipe type in `settingtypes.txt`.
- [ ] Run the derivation on the real recipes and review the results for odd prices.

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
