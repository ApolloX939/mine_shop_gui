# Version 2 plan: price inference

**Status:** a proposal for consideration. Nothing here is built, scheduled or decided. Version 1 (see `PLAN.md`) prices raw items from hand-written files and everything else from recipes. This plan asks whether a computer can supply most of those hand-written prices.

## Why

After pricing Ethereal, Everness and Techage by hand, the shipped price files hold about 500 lines for raw items alone, and each new mod or game needs more. Most of those lines are the same few decisions repeated: "a tree trunk costs 4", "a leaf costs 1", "a sapling costs 3". If the game already tells us an item is a tree trunk (through its groups), we should not have to say it once per item per mod.

The goal is to shrink the hand-written part to a small set of overrides and anchors, and to make the shop usable on mods and games nobody has written a price file for (Mineclonia, VoxeLibre, and any mod pack the owner installs).

## What was measured

All numbers come from the 51-mod test world (Minetest Game, Technic, Techage, Ethereal, Everness and others) and compare against the prices written for version 1. Those prices were chosen by Claude using the same kind of categories the rules use, so they show how well the categories compress, not that the values are correct.

### Rules from item properties

| Result | Items | Share of the 492 hand-set items |
|---|---|---|
| a rule applies | 415 | 84% |
| rule gives exactly the hand-set price | 253 | 51% |
| within a factor of 2 | 324 | 66% |

| Rule | Fires | Exact |
|---|---|---|
| leaves | 38 | 38 |
| saplings | 33 | 33 |
| tree trunks | 30 | 29 |
| soils and sands | 52 | 46 |
| plants and flowers | 88 | 44 |
| other snappy nodes | 65 | 43 |
| food | 35 | 9 |
| stone-like nodes with no recipe | 74 | 11 |

The weak rows (food, stone-like) hide special cases: fish, crystals, deep-sea corals, lanterns, obsidian.

### Rarity of ores

For each ore, sum `clust_num_ores / clust_scarcity` over all its worldgen definitions to get a density. Fitting the seven Minetest Game ores gives `price = 2.09 * density^-0.74` with R² = 0.68. On ores that were not part of the fit:

| Ore | Predicted | Hand-set |
|---|---|---|
| lead lump | 13.7 | 14 |
| zinc lump | 17.6 | 14 |
| etherium dust | 42 | 40 |
| uranium lump | 46 | 60 |
| chromium lump | 31 | 60 |
| quartz crystal | 55 | 20 |
| pyrite lump | 60 | 20 |

It also priced Techage's baborium lump, which had no price, at about 39. It fails on bulk and decorative spawns: ceramic sherds come out at 224.

### What cannot be inferred

- Design intent: why diamond costs more than mese, what a golden apple is worth.
- Items with no recipe and no worldgen: Techage chips, vacuum tubes and other machine-made parts, fishing and mob drops.
- Anything that depends on a mod's own rules rather than the engine's data.

## Proposed design

### Layers, lowest priority first

1. **Inferred defaults** (new): a price for every raw item the rules can reach.
2. **Price files** (exists): `prices/games/*.lua` and `prices/mods/*.lua`, now used as anchors and overrides. Same format as today.
3. **World override file** (exists): `<world>/mine_shop_gui_prices.lua`.
4. **Recipe derivation** (exists): runs on top of all base prices, cheapest route.
5. **Price hook** (exists): other mods edit the final table.

### The rule file

A Lua data file, `prices/rules.lua`, run in an empty environment like the price files. A rule matches an item by properties and gives a price:

```lua
return {
  { match = { group = "tree" },                 price = 4 },
  { match = { group = "sapling" },              price = 3 },
  { match = { group = "leaves" },               price = 1 },
  { match = { group = "soil" },                 price = 1 },
  { match = { group = "flora" },                price = 1 },
  { match = { light_source_min = 8 },           add = 3 },
  { match = { name_pattern = "fish_" },         price = 6 },
}
```

Rules are tried in order; the first `price` wins, and `add` / `multiply` adjust it. Games and mods may add rule files under `prices/rules/games/` and `prices/rules/mods/`, named the same way as price files (mod.conf name preferred).

### The ore estimator

Only for items dropped by ore nodes and classed as a lump or crystal. It uses the fit above, recalibrated at load time from the game's own anchor prices (coal, iron, gold, mese, diamond, ...), so it adapts to a game with a different price scale. Bulk spawns (sand, gravel, clay) and decoration-like ore nodes are excluded.

### Other inference sources worth testing

- **Drops:** an ore node costs what its drop costs. A leaf node that drops a sapling gets a share of that sapling's price.
- **Loop anchors:** items that are only made by uncrafting slabs, stairs or blocks (the "cobble anchors" written by hand in version 1) can take the price of the nearest known stone-like item.
- **Reading Techage's own machine recipes.** Techage has its own recipe system for its grinder, furnace and similar machines, which the collector does not read (the way it reads Technic's). Before this is built, check the real API. If it is usable, powders and ingots like `techage:iron_ingot` could be derived instead of hand-set. This was noticed, not verified.

### Safety

Every table entry already carries `source`. Inferred entries would carry `inferred:<rule>`, so the shop and the owner can tell them apart. A server setting, `mine_shop_gui_inferred_mode`, would control how inferred prices behave:

| Mode | Effect |
|---|---|
| `off` | no inference, version 1 behaviour |
| `sell_only` | players can sell inferred items but not buy them |
| `buy_only` | the reverse (rarely useful) |
| `full` | inferred items are traded like any other |

Suggested default: `sell_only`, so a wrong guess cannot give away valuable items, and a price file entry always upgrades an item to full trading.

## Migration

1. Build the rule engine and run it over the existing price files.
2. Delete every file entry whose rule gives the same number (about 250 lines, no price changes).
3. Review the entries that differ by a factor of 2 or less and decide per rule whether to keep the rule or the file entry.
4. Keep the rest as overrides. Estimated size after a few more rules (light, crystal and coral names, fish): roughly 100 lines across all price files.

## Work breakdown

Each step is tested with `mtt` in the real engine, like version 1.

1. Rule file loader and validator (same safety as price files).
2. Property rules and the `inferred:<rule>` source label.
3. The inferred-mode setting and its effect on `can_buy` / `can_sell`.
4. Migration tool: report which file entries are redundant.
5. Ore estimator with load-time calibration.
6. Drop-based inference and loop anchors.
7. Check Techage's recipe API and, if usable, add a collector for it.
8. Run on Mineclonia and VoxeLibre and write their rule overrides.

## Open questions

1. What should the default inferred mode be (`sell_only` is suggested)?
2. Should rules be one shared file, or per game and per mod, or both?
3. Is a price within a factor of 2 acceptable for inferred items, or should rules only fire when the result is expected to be tighter?
4. Should rarity-based ore pricing be on by default, or opt in per game?
5. Do Mineclonia and VoxeLibre use the same group names as Minetest Game? This is unchecked, and it decides how much carries over.

## Risks

- A bad rule affects hundreds of items at once. Mitigation: the source label, the inferred mode, and a report of how many items each rule priced.
- Calibration rests on a handful of hand-set anchors. Mitigation: recalibrate at load time and expose the fit in the log.
- Rules can interact with recipe derivation in surprising ways (a cheap inferred ingredient cheapens everything built from it). Mitigation: a report of the most-used inferred ingredients.

## How to tell it worked

- The share of items priced with no hand-written entry (today about 25% of priced items are raw and hand-priced; the target is under 5%).
- The number of lines across all price files (today about 500; the target is about 100).
- A fresh mod pack with no price files gets sensible, if rough, sell prices.
- All tests pass in both test worlds, plus a Mineclonia or VoxeLibre world.
