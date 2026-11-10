# PLAN

Design decisions for Mine ShopGUI. Open questions and tasks live in `TODO.md`.

## Goals

1. Base prices come from fixed values for primitive items (stone, ores, anything not craftable but needed to craft other things).
2. Other prices are derived from crafting recipes, including custom machine recipes (Technic alloying, grinding, etc.).
3. A price list offers Buy and Sell, with a variable amount chosen after selecting an item.
4. Payment works through a currency API or directly from the player's inventory. Inventory payment requires making change (breaking a note or coin into smaller denominations).

## Supported currencies (optional, auto-supported)

All three are optional dependencies, reached through one adapter interface.

### currency (mt-mods)
- Support both notes and coins. Exclude `currency:minegeld_bundle`.
- Coins (group `minegeld_coin`): 5, 10, 25 cents. Notes (group `minegeld_note`): 1, 5, 10, 50, 100.
- Work in integer cents internally. Greedy change-making is optimal for these denominations.
- There is no 50 cent coin. Change under 1 is made from 25/10/5 cent coins.

### unified_money
- Only `um_core` plus one backend (`um_backend_plain`) are relevant. Use the `unified_money.*` API only (`get_balance_safe`, `add_balance_safe`, `del_balance`, `transaction`).
- Do not enable the whole modpack. Several parts are incompatible with each other or only for special cases: `um_backend_dummy` is test-only, `um_migrate_plain` and `um_dump_data` are one-off tools. `um_atm` converts account balance to `currency` notes and is separate.

### credits
- Whole values only.
- Two versions must both be supported:
  - **V1.2.3 (old):** `credits:credits` = 1, `credits_mkii` = 9, `credits_mkiii` = 81. No metadata.
  - **V1.3 (new):** `credits:credits` is worth `count * meta "value"`. Unset value counts as 0. Mk2/Mk3 are worth 0.
- Detect the version via API: `credits.get_balance_physical_all` or `registered_items["credits:credits"].value` exists on V1.3 only.
- Digital balance is the same on both: `credits.get_balance_digital(name)` and `credits.add_coin(name, +/-n)`. `add_coin` clamps at 0 silently, so always check the balance first. Do not use `credits.give` or `credits.take` (they need the `give` priv).
- Giving physical change: V1.2.3 uses greedy 81/9/1 stacks. V1.3 uses one stack with `value` set and `description` set to `"Credit\nValue: N"`.
- Check inventory room before adding or removing physical credits.

## Decisions on pricing and currency choice

- **Currency choice:** a server setting in `settingtypes.txt` picks the currency. Default is `auto`, which uses the first supported currency detected. All players use the same currency.
- **Base prices:** a hand-edited Lua/JSON file maps item -> price. It is seeded from the ores in the installed mods and tweaked by hand. Items with no entry and no derivable recipe get no price.
- **Sell price:** buy price multiplied by a configurable fraction (default 50%), set in `settingtypes.txt`.
- **Rounding (`currency`, smallest coin 5 cents):** keep exact prices internally and round only the final transaction total to the nearest 5 cents, so buying many cheap items stays fair.

## Currency layer (implemented)

- `src/currency/api.lua`: registry and the single interface the shop uses (`balance`, `withdraw`, `deposit`, `round`, `format`). Amounts are whole numbers in the active currency's smallest unit. `withdraw` and `deposit` are atomic and return `true` or `false, reason` (`invalid_amount`, `insufficient_funds`, `no_room`, `unavailable`).
- `src/currency/denominations.lua`: shared adapter for item-based currencies. Paying removes all the player's money, then hands back change (greedy, largest first); the inventory is restored if the change does not fit.
- Adapters: `currency` (cents), `unified_money`, `credits`, and `items` (any items listed in the `mine_shop_gui_item_currency` setting, for example emeralds under Mineclonia or VoxeLibre; unknown items are logged and ignored).
- Auto order: currency, unified_money, credits, items. An explicit setting naming an unavailable currency falls back to auto with a warning.
- Callers must pass amounts already rounded with `api.round`. Amounts that are not a whole multiple of the currency's smallest unit are rejected, never silently adjusted.
- `credits` payments spend the digital balance first, then physical stacks. Any surplus from a physical stack is returned to the digital balance, so the shop never has to create valued stacks. Payouts to the player are always digital. (Decided while implementing; revisit if physical change is wanted.)

## Price scaling (decided and implemented)

- The price list uses abstract **price units**, decimals allowed. One unit is the value of one cobblestone.
- Each currency converts units to its own amounts with a scale: `mine_shop_gui_scale_<currency>`, with defaults of `currency` 5 (cents, so a cobblestone costs the smallest coin), `credits` 1, `unified_money` 1, `items` 0.05 (about 20 cobblestones per item). `api.scale()` reads it.
- `api.price(units, mode)` is the only place that turns price units into a payable amount. `units` is the buy price times the quantity.
  - `"buy"`: rounded to the currency's smallest unit, never below one unit (never free unless the price itself is 0).
  - `"sell"`: the buy price times `mine_shop_gui_sell_ratio` (default 0.5), then scaled and rounded. If that is under one unit the sale is refused with `"too_cheap"`, and the shop should show the item as not sellable.
- Rounding happens once, on the final total, never per item.
- Open: `unified_money` may allow fractional balances; its adapter currently treats 1 as the smallest unit.

## Testing notes

- Tests use `mtt` in the real Luanti engine; see `AGENTS.md` for how to run them.
- Covered: currency, items, unified_money, credits V1.3, price scaling, the price files, the collector and the hook. Technic behavior is covered by a second, larger world (the tests guard themselves with `core.get_modpath("technic")`). Tests reset the accounts they use, so the world does not need cleaning between runs. Not covered: credits V1.2.3 (cannot coexist with V1.3 in one world).


- `credits_old/mod.conf` was renamed to `name = credits_old` to avoid a load-time name clash. It still registers `credits:` items and the `/credits` command, so it will probably fail to load and conflicts with the new `credits`. Treat it as reference code. Test each credits version in its own world with only that version present.
- Test mods in the parent folder: currency, unified_money, um_atm, credits, credits_old, technic, techage_modpack, ethereal, everness, 3d_armor, pipeworks, i3, unified_inventory.

## Technic recipe API (checked in the source)

- Recipes are read from `technic.recipes[type].recipes`, a table keyed by a sorted input hash. Each entry is `{time = n, input = {["mod:item"] = count, ...}, output = "mod:item N"}`. For types with `output_size` greater than 1, `output` is a list of itemstrings.
- The recipe types are `alloy` (2 inputs), `grinding`, `compressing`, `extracting`, `freezing` and `separating` (centrifuge, 2 outputs). `technic.recipes[type].input_size` and `.output_size` give the shape. Smelting is not in this table: it is the built-in `cooking` craft type in `core.get_all_craft_recipes`.
- Registration is postponed to `core.register_on_mods_loaded` inside technic, and the table is only complete after that callback. Our pricing must run after it, so `technic` needs to be in `optional_depends` and our callback registered later.
- Technic clears some built-in crafts (for example sand variants), so `core.get_all_craft_recipes` at that point reflects what players can really do.
- Input items may be aliases or groups in other mods, so resolve names through `core.registered_items` and aliases before using them.
- `separating` is mostly the reverse of alloying (bronze dust to copper dust plus tin dust) and also has a 34-step uranium chain. These recipes have several different outputs, so a cost cannot be split between them without a rule.

## Recipe-derived pricing (decided; core implemented)

- **Cheapest route:** an item costs the lowest cost over all its recipes (craft, smelt, machine, uncraft). Computed by relaxing prices until nothing gets cheaper, so cycles such as block <-> ingots settle on their own. With a sell ratio below 100% no buy/sell loop can make money.
- **Base prices are ceilings (decided):** an item costs the lower of its base price and its cheapest recipe, so a base price only says what the item costs when nothing cheaper exists. A price that must never be lowered is written `{ price = 1, fixed = true }`; cobblestone, the price unit itself, is the only one so far. See "Base prices as ceilings" below.
- **Markup:** configurable percentage per recipe type (crafting, smelting, and each Technic machine type), default 0%. The derivation takes a `markup(recipe_type)` function.
- **Multi-output recipes (Technic separating) are skipped.** They mostly undo alloying, and splitting cost between outputs has no right answer.
- **Groups:** a group ingredient costs as much as its cheapest priced member.
- **Unpriced ingredient means no price** for the result. Items with no price cannot be bought or sold.
- **Value-creating loops** (for example 1 a -> 2 a) never settle. Items in such a loop lose their derived price and are reported, instead of being priced near zero.
- Implemented as a pure function in `src/pricing/derive.lua` (`mine_shop_gui.pricing.derive`), tested with `mtt`. Not yet wired to real recipes.

### Base price file (decided: Lua)

- Format: a Lua file that returns a table of `["mod:item"] = price units`. Comments and decimals are allowed. It runs in an empty environment, so it can only hold data (`src/pricing/base_prices.lua`).
- Layout (decided): a `prices/` folder in the mod root.
  - `prices/games/<game_id>.lua` for the running game (for example `minetest`, `mineclonia`, `mineclone2`).
  - `prices/mods/<mod_id>.lua` for each enabled mod, where `<mod_id>` is the `name` in its `mod.conf` (preferred). A file named after the mod's folder is still found when the names differ, but that old style is deprecated and logs a warning.
  - Files are merged in that order (game, then mods alphabetically), then an optional `<world>/mine_shop_gui_prices.lua` overrides everything. `false` removes an item's price from what was loaded before it.
  - Files for a game or mod that is not installed are never read. Invalid entries are logged and skipped, and so are items that are not registered (the load reports them, which catches typos).
- Layout note: a price file is named after the mod that registers the item. Technic's lumps and the rubber tree trunk are registered by `technic_worldgen`, so they are in `prices/mods/technic_worldgen.lua`. `prices/mods/technic.lua` is deliberately empty and only explains the next point.
- **Technic ingot prices (decided):** players are assumed to always grind ore lumps (1 lump becomes 2 dust, 1 dust smelts to 1 ingot). The derivation takes the cheapest route, so with Technic installed an ingot costs half its lump (iron 16 -> steel ingot 8, copper 12 -> 6, tin 12 -> 6, gold 40 -> 20), and without Technic it costs the same as the lump. No ingot price is set by hand: a fixed price would override the derivation and go stale when a lump price changes. Raising `mine_shop_gui_markup_grinding` softens the drop (100 puts ingots back at the lump price). Tested in a Technic world.
- Natural-item anchors added to `prices/games/minetest.lua` (decided): clay lump 2, cactus 2, papyrus 2, ice 3, snow 1, obsidian 25, flint 2, wheat 3, cotton 3, plus mossy cobblestone 1, desert cobblestone 1 and desert sandstone 2 (items that only slab/stair recipes make). In the 51-mod world these price 116 more items.
- Seeded so far (earlier): `prices/games/minetest.lua` (cobblestone anchor, earth, logs, ore lumps, coal, mese, diamond) and `prices/mods/technic.lua` (zinc, lead, chromium, uranium, sulfur). Decorative Everness and Ethereal items are deliberately left unpriced for now. In the 51-mod test world this prices 23 items with none unknown.
- Findings from dumping the installed content mods (51 mods, 4318 items): 618 items have no recipe at all. Most are Everness (275) and Ethereal (137), then Techage (89), default (66) and Technic (17).
- Raw items alone are not enough. Items that can only be made inside a cycle (for example cobblestone <-> stone <-> mossy cobblestone) or only by a skipped multi-output recipe (dirt from Technic's separating) also need a base price, and cobblestone is the unit anchor. The derivation shows which items are still unpriced, so the seed list is built by running it and adding anchors until nothing important is missing.

### Collector, flags and the price hook (decided and implemented)

- **Collector** (`src/pricing/collect.lua`): reads `core.get_all_craft_recipes` (types `normal` and `cooking`) and Technic's machine recipes, skips multi-output recipes, merges repeated ingredients, resolves aliases, and lists the members of every group the recipes use. Output is sorted so ties always resolve the same way.
- **Generation** (`src/pricing/generate.lua`): runs once on the first server step after all `on_mods_loaded` callbacks (so Technic's own recipe registration is done). Result: `mine_shop_gui.pricing.items[name] = {price, source, no_buy, no_sell}`. `source` is `base`, a recipe type, or `hook`.
- **Markup:** `mine_shop_gui_markup_<type>` settings (percent, default 0) for `normal`, `cooking`, `alloy`, `grinding`, `compressing`, `extracting`, `freezing`.
- **Flags `no_buy` / `no_sell`** can be set in two places:
  - Item definition: `_mine_shop_gui = { no_buy = true, no_sell = true }`.
  - Item metadata on a stack: `meta:contains("no_buy")` / `meta:contains("no_sell")` decides, and the flag is only true when the stored value is exactly the string `"true"` (so `meta:set_string("no_sell", "true")`). Any other value (`"false"`, `"1"`, `"yes"`, `"True"`, an integer) leaves it unset. **Metadata has no `set_bool`**; that method only exists on `Settings` objects. A stack flag stops that stack being sold; `no_buy` on a stack is read but nothing uses it yet, because the shop only sells new items.
  - Mod-wide flags are set from the hook below, not from `mod.conf` or price files (decided).
- **Chain rule (decided):** a derived item still gets a price but inherits the flags of every ingredient of the recipe that set its price (for a group ingredient, the member used), plus its own flags. Flags therefore follow the cheapest route.
- **Hook (decided: whole table):** `mine_shop_gui.register_on_prices_generated(function(items) ... end)`. Register while mods load. Runs after the collector and derivation, in registration order, and edits `items` in place: change a price, remove an entry, add an entry, set `no_buy` / `no_sell`. Afterwards the table is checked: entries that are not tables, have a bad price, or name an unregistered item are dropped with a warning, and a hook that throws is skipped without stopping the others. A hook registered late runs immediately with a warning.
- **Trade checks:** `pricing.get(name)`, `pricing.can_buy(name)` and `pricing.can_sell(stack)` (item flags and the stack's own metadata).

### Ethereal prices (drafted by Claude, open to adjustment)

`prices/mods/ethereal.lua` prices all 137 raw Ethereal items by category, relative to cobblestone = 1:

| Group | Price |
|---|---|
| tree trunks (same as Minetest Game logs, so planks cost 1) | 4 |
| bamboo, bush stems, mushroom pores, mangrove roots | 2 |
| saplings | 3 |
| leaves and litter | 1 |
| ordinary soils | 1 |
| crystal, fiery and magical soils | 3 |
| common plants and flowers | 1 |
| rare plants (magical grass, barrel cactus, slime mold) | 2 |
| crystalgrass, wet sponge, illumishrooms | 3 |
| fire flower | 5 |
| corals | 2 |
| basic foods | 2 |
| cactus flower | 3 |
| firethorn jelly | 4 |
| golden apple | 40 |
| edible fish | 6 |
| other sea creatures | 3 |
| thin ice | 3 |
| crystal spike | 10 |
| etherium dust and ore | 40 |
| stairs-only anchors: mushroom trunk 4, blue marble 3, banana 2 | |

To make those recipes work, the Minetest Game file also gained leaves (1), saplings (3), flowers (1), mushrooms and waterlily (2), and `technic_worldgen.lua` gained marble and granite (2). Result in the 51-mod world: 151 of 170 craftable Ethereal items are priced. The other 19 are blocked by the water bucket (the empty bucket's Techage recipe needs the unpriced `techage:iron_ingot`) or by food ingredient groups from mods that are not installed (sushi, teriyaki, fugu). Dyes come out very cheap (0.25) with Technic installed because the extractor makes 4 dyes from one flower.

### Everness prices (drafted by Claude, open to adjustment)

`prices/mods/everness.lua` was generated from category rules and is now a plain hand-editable file. It prices 293 items:

| Group | Price |
|---|---|
| tree trunks | 4 (lava tree with lava 6) |
| saplings | 3 |
| leaves | 1 |
| soils, sands, stones, mosses | 1 |
| stone and volcanic spikes | 2 |
| plants and vines | 1 |
| flowers, cacti, mushrooms | 2 |
| lanterns | 4 |
| deep-ocean and crystal corals | 3 |
| other corals | 2 |
| crystal megaliths | 10 |
| crystal cluster | 15 |
| pyrite lump, quartz crystal | 20 |
| bones, pottery sherds | 2 |
| emerald ice | 8, 12, 20 |
| weeping and crying obsidian | 40 |
| mese tree fruit | 20 |

Anchors for items that only come from uncrafting slabs and stairs: cobbles and plain stones 1, bricks 2, magma cobble 2, volcanic rock with magma 3, coloured crystals 12, dry tree 4, frosted ice 4, pottery sherd blank 2, crystal stone brick 2.

**Deliberately unpriced** (not meant to be traded): flames, water geyser, lava and mineral water sources, buckets of lava or mineral water, termite blocks, cobwebs, skull candles, cursed mud, and ore-bearing nodes (coal, pyrite and quartz ore).

Result in the 51-mod world: all 198 craftable Everness items are priced, 1816 items overall, no unknown names, no unstable loops. With Technic installed, pyrite ingots cost half a lump (10) because of grinding, like the other metals.

### Price inference (moved to version 2)

Inferring raw-item prices from item properties and ore rarity was tested and looks promising (about half of the hand-set prices are reproduced exactly by a handful of group rules). It is not part of version 1. The measurements, design and open questions are in `PLAN_V2.md`.

### Techage prices (drafted by Claude, open to adjustment)

`prices/mods/techage.lua` prices 64 Techage items, plus `basic_materials:silver_wire` (6) and `compost:compost` (1). Techage's raw items are mostly made by its own machines with no craft recipe, so the prices are judgment calls that climb with the tech tier:

| Group | Price |
|---|---|
| basics: charcoal, clay and cement powder, leaf and needle powder, gravel | 1 to 3 |
| graphite powder, redmud, lye, nitrogen | 2 to 6 |
| iron powder | 16 |
| baborium lump | 40 (the ore-rarity estimate gave 39) |
| usmium nuggets and powder | 60 |
| aluminium and aluminium powder | 24 |
| basalt glass | 4 to 10 |
| oil products and gases | 4 to 12 |
| TA3 electronics (vacuum tube, logic block) | 12 to 20 |
| WLAN chip | 30 |
| TA4 chips and ceramics | 10 to 40 |
| TA5 parts | 100 to 250 |

Anchors for items that Techage makes inside a machine or only gets by uncrafting: `techage:iron_ingot` 16 (it was the biggest blocker, 46 recipes, and unlocks the empty and water buckets), basalt cobble 1, red stone 2, bauxite cobble 1, basalt glass 4, sieved basalt gravel 1. Four filled containers that recipes need are priced (epoxy canister 12, lye canister 10, large hydrogen cylinder 40, bitumen barrel 20). Other filled containers, the three gravel sieve machines, admin and test blocks, oil sources and ore nodes stay unpriced.

Result in the 51-mod world: 431 of 437 craftable items in the Techage modpack are priced, and 2215 items overall, with no unknown names and no unstable loops. The six left are the gravel sieves and the bauxite stone slabs and stairs.

Techage has its own machine recipe system (grinder, furnace and similar), which the collector does not read. See `PLAN_V2.md`.

### Techage machine recipes (implemented)

Techage keeps its recipes in several private places, so the collector reads two sources (`src/pricing/collect.lua`):

- **Through Techage's own API, no extra mod needed:** the electronic fabricators (`ta2_`, `ta3_`, `ta4_electronic_fab`) and the chemical doser (`ta4_doser`), read one recipe at a time with `techage.recipes.get({recipe_idx = i}, rtype)`. The type names are the ones Techage registers; a recipe that appears under several tiers is kept once. Waste products (empty spools, red mud) count as free by-products and catalysts are not consumed, so neither adds to the cost. Recipes that need an ingredient that is not a registered item (for example some fluids) are skipped.
- **Through `unified_inventory`'s craft guide, only when that mod is installed:** the iron-age melting pot (`melting`), the TA3 furnace (`ta3_melting`), the grinder (`grinding`) and the mill (`milling`). Techage hands those to the craft guide but keeps them private otherwise. Sieves and the rinser are not read, because their output is random. This relies on `unified_inventory.crafts_for.recipe`, which is not a documented interface, so it is best effort.
- Markup settings exist for the new types (`ta2_electronic_fab`, `ta3_electronic_fab`, `ta4_electronic_fab`, `ta4_doser`, `melting`, `ta3_melting`, `milling`).
- Result in the 51-mod world: 2896 recipes collected; fabricators 1 + 2 + 5, doser 18, melting 4, TA3 furnace 105, grinding 139.
- **Hand-set Techage prices changed accordingly.** Vacuum tube, WLAN and RAM chips, LEDs, both AI chips and the SSD are no longer listed: they are priced from their parts. The vacuum tube comes out at 37 (not my earlier guess of 12) because each pair needs a usmium nugget; chips and LEDs come out much cheaper than my tier guesses (WLAN chip 16, LED 3). Items that depend on the craft guide keep a hand price, now aligned with what the recipes give (silicon wafer 3, carbon fiber 5, magnet shield 38, graphite powder 8, clay and cement powder 1), so servers without `unified_inventory` still price them. A markup on `ta4_electronic_fab` and the others is the way to make later tiers dearer.

### Base prices as ceilings (decided and implemented)

Finding: Techage's machines make some base-priced items for far less than their base price (the melting pot turns cobblestone into obsidian, priced 25; the grinder turns sand into clay, so a clay lump costs 0.25 against a base of 2). With fixed base prices a player could buy the cheap ingredients, craft, and sell back at the 50% sell ratio for a profit.

Decision (chosen from three options): a base price is a ceiling. The derivation lowers it to the cheapest recipe, which matches the Technic ingot rule (players always use the machines). `{ price = n, fixed = true }` keeps a price whatever recipes say; `default:cobble` is fixed because it defines the unit. A lowered item takes the recipe type as its `source`.

Reports (`generate()` returns them, and the server log shows them):
- `report.lowered`: base prices that recipes lowered (31 in the 51-mod world, for example obsidian 25 to 1, clay lump 2 to 0.25, aluminium 24 to 6, basalt glass 6 to 0.5, TA5 control unit 150 to 71).
- `report.below_base`: fixed prices that a recipe could undercut (none in the shipped data; a test checks this).
- `report.held`: items held inside a gaining loop (below).

The change also exposed one inconsistent anchor of mine: desert sandstone was 2 but 4 desert sand make it, so it is now 4.

### Gaining loops (implemented)

Some machine combinations gain value: Technic's compressor turns 2 sand into 1 sandstone and Techage's grinder turns 1 sandstone into 4 sand; a similar loop runs through silver sand, stone and Technic's stone dust. Prices round such a loop never settle. The derivation now cuts them:

- Only loops that nothing unstable feeds into are cut. The block, slab and stair groups below them were only moving because the loop above had not settled, and cutting those too gave nonsense prices (cement came out at 0.000).
- A loop member with a base price is held at that price. A loop with no base-priced member is priced from its routes that do not run round the loop. A member with no outside route stays unpriced (`report.dropped`).
- Everything downstream keeps a sensible price. In the 51-mod world sand (1) and silver sand (1) are held although machines can make them for 0.5 and 0.25; `report.held` lists them.
- Each cut is traced at log level info (`price loop: ...`).
- **Decided: only warn the owner.** Items held inside a gaining loop keep their price, and the server log gets one warning at startup that says players with these mods can make them for less than the shop pays, followed by one line per item (for example sand: priced 1.00, machines make it for 0.50). The owner can then remove a recipe or a mod, or set a lower price in a price file.

A property test checks that after generation no recipe makes an item for less than its price, except for fixed prices and items held in a loop.

### Remaining content prices (drafted by Claude, open to adjustment)

Coverage in the 51-mod world: 2274 of 2421 visible items are priced (94%), with no unknown names and no unstable loops.

Added in this pass:
- `prices/games/minetest.lua`: bush leaves, needles, stems (2) and saplings (3); grasses, ferns and kelp (1); grass, litter, savanna and permafrost soils (1); apple and blueberries (2); corals and coral skeleton (2); wheat and cotton seeds (1) and wild cotton (3); captured butterflies and fireflies (3); river water bucket (27) and lava bucket (30), meaning an empty bucket (24) plus contents.
- `prices/mods/bakedclay.lua` (4 items at 2). Ethereal registers the same nodes itself when the real `bakedclay` mod is absent, so the same four lines are also in `ethereal.lua`.
- `prices/mods/everness.lua`: lava and mineral water buckets (30, 27).
- `prices/mods/technic_worldgen.lua`: rubber tree leaves (1) and sapling (3).
- `prices/mods/techage.lua`: `techage:bauxite_stone` (1), a worldgen stone only reachable by uncrafting slabs.
- `prices/mods/technic.lua`: the 35 enrichment dusts of uranium (`uranium0_dust` to `uranium35_dust`, natural uranium 7 excluded) at 30 * (0.5 + percent / 14), so 15 for 0% up to 90 for 3.5%. The centrifuge that makes them has two outputs, so they cannot be derived. Their ingots and the fuel are priced from them.

Deliberately unpriced (a missing price means the item cannot be traded):
- **Money:** every `currency` note and coin, and `credits:credits`.
- **Not goods:** ore nodes, liquid sources, fire and flames, bones, admin and test blocks, power and oil sources, wrench, prospector, sonic screwdriver, and filled barrels, canisters and cylinders (apart from the four recipes need).
- **Cannot be made here:** mithril and nether armor and shields (need ingots from mods that are not installed); Technic's red and blue energy crystals, silver and mithril chests and dusts (need `moreores`); Ethereal's cooked dishes and Techage's sieve machines; pipeworks deployers and similar (their recipes need `mesecons`); everything that needs rice, soy sauce, sugar, garlic or a saucepan group from food mods that are not installed. If those mods are added, recipes will price what they can, and the rest needs a price file.

### Shop window (implemented)

Decisions (chosen with the owner): open with the `/shop` command first (a placeable block can come later), plain formspec with no extra mod, and an amount control made of a number field plus `-64 -10 -1 +1 +10 +64` buttons with a live total. The layout follows what I remember of the Minecraft EconomyShopGUI plugin the owner pointed to. I could not read the video, which only returned its title.

Three screens, in `src/shop/`:
- **Categories** (`ui.lua`, `catalog.lua`): one per mod with at least 4 tradable items, the rest under "Other", plus "Everything"; 15 per page; the picture is the dearest item of the mod; search box.
- **Items**: 6 by 3 grid of item pictures with the item name (shortened to 16 characters) and the buy price under each, a tooltip with name, buy and sell price (or "only N or more at once" when one item is worth less than a coin). Sorted by title; search words must all match the title or the technical name. Hidden variants and items that cannot be traded in either direction are left out.
- **Trade**: amount controls, total to buy, payout, held count, BUY, SELL and SELL ALL. Buttons that do not apply are not drawn.

Safety and correctness:
- Item and category buttons carry only a position on the current page. The server looks the real item up in its own state, so a forged field cannot name an item; unknown positions and trade buttons outside the trade screen do nothing.
- `trade.lua`: a trade is atomic. Buying pays first, then delivers; if delivery fails the payment is undone. Selling removes the items, then pays; if paying fails the items come back. Undoing uses a snapshot of the player's money that every currency adapter now provides (`snapshot` and `restore`: the inventory list for item currencies, the balance for `unified_money`, balance plus inventory for `credits`).
- Only undamaged stacks without a `no_sell` mark are sold, and only items priced with `no_sell` false. A sale whose payout is under one coin is refused with a hint of the smallest amount that works.
- The purchase limit is `mine_shop_gui_max_amount` (default 1000). Selling everything is not limited.

Tested in the real engine: buying with change, not enough money, undeliverable purchase paid back (for `currency`, `credits` and `unified_money`), selling with flagged and worn stacks, sell all, flags and limits, the catalog (categories, search, paging, regeneration), the whole window flow including forged fields, and a `formspec_ast` syntax check of every screen (the parser must accept all elements that were written).

First look in a real client (screenshots from the owner) showed three problems, now fixed: category pictures stretched over the whole button and hid the title (now a small picture button with a separate title button), the item grid showed no names (now a name under each picture, with fewer rows to make room), and text fields came out bright green (now a dark box with the field's own border turned off). Category names without a `mod.conf` title are capitalised, and "Everything" uses a chest picture. The trade screen needed no change. The tests prove the syntax and the behavior; the appearance still needs the owner's eye.

Currency picture (owner's request: a symbol or a small image of the currency item, the item preferred). Every adapter now says which item stands for its money (`icon()`), how to write an amount as a plain number (`number`), and how to write it with a short mark (`format_symbol`): `currency` shows the 1.00 Minegeld note and `$1.25`; an item currency shows its smallest item; `credits` shows `credits:credits` and `15 cr`; `unified_money` has no item, so it shows text with `$`. The window draws the picture (0.5 high) beside the number for the balance, the price under each grid item, and the buy, sell, pay and receive lines in the trade screen; where there is no picture, or only text fits (tooltips, messages), it uses the text mark. An icon that is not a registered item is ignored.

### Item currency: selection, worth and money (owner report)

The owner set `mine_shop_gui_item_currency = default:steel_ingot` with `mine_shop_gui_currency = currency` and saw no effect. Three causes, all fixed:
- `currency` is the Minegeld mod, not "an item currency" (that is `items`). The server now logs a warning when an item currency is set up but another currency is in use, naming the fix. On `auto`, a configured item currency is chosen first (decided: setting one up means wanting it); an explicit choice still wins.
- An item written without a value was rejected, so the list came out empty. A bare item name now counts as 1.
- There was no way to say what the item is worth. New setting `mine_shop_gui_item_currency_worth`: price units one unit of the currency is worth (1 unit = one cobblestone). Left empty, the shop's own price for the smallest currency item is used (so a steel ingot is worth what the shop prices it at, 8 under Technic). Nonsense falls back to that. The old `mine_shop_gui_scale_items` setting is gone from the settings menu (amount per price unit is the inverse and confusing), though an explicit `mine_shop_gui_scale_items` in `minetest.conf` still wins.
- The currency's own items are money, not goods: they are not listed in the catalog and cannot be bought or sold (`api.is_money`). This also covers `credits`.

### Result on the 51-mod test world

2707 recipes read (2474 crafting, 104 smelting, 83 grinding, 17 compressing, 14 alloy, 14 extracting, 1 freezing). 410 items priced, no unstable loops. 1480 craftable items are still unpriced because something they need has no price: mostly stairs (464), Techage (263), Everness (197), Technic machines (182), Ethereal (158). Natural default items that need anchors are clay lump, cactus, papyrus, ice, snow, obsidian and the farming crops (wheat, cotton, string).

### Still to build

- Anchors for the natural items listed above, and prices for Ethereal, Everness, Techage and other content mods.
- The shop GUI itself.
