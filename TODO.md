# TODO

Decisions go in `PLAN.md` once answered.

## Open questions

- [ ] When several currencies are installed, should a server setting pick one, or should the player choose? (Suggested: setting with auto-detection as the default.)
- [ ] Base prices: use a Lua/JSON file of hand-set prices for raw items, seeded from the installed mods' ores?
- [ ] Sell price: a fixed fraction of the buy price (for example 50%) set in `settingtypes.txt`?
- [ ] How should prices finer than 5 cents be handled for `currency` (round to nearest 5)?

## Tasks

- [ ] Write the currency adapter layer (`currency`, `unified_money`, `credits` behind one interface).
- [ ] Check Technic's recipe registration API for machine recipes.
- [ ] Add `mod.conf` and `init.lua`.
- [ ] Build the base price list and the recipe-derived pricing.
- [ ] Build the Buy/Sell formspec with a variable amount.
- [ ] Verify the `credits_old` item-prefix load failure in a test world.
