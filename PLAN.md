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
- Covered: currency, items, unified_money, credits V1.3, and price scaling. Tests reset the accounts they use, so the world does not need cleaning between runs. Not covered: credits V1.2.3 (cannot coexist with V1.3 in one world).


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
- **Base prices are fixed:** an item with a base price is never overridden by a recipe.
- **Markup:** configurable percentage per recipe type (crafting, smelting, and each Technic machine type), default 0%. The derivation takes a `markup(recipe_type)` function.
- **Multi-output recipes (Technic separating) are skipped.** They mostly undo alloying, and splitting cost between outputs has no right answer.
- **Groups:** a group ingredient costs as much as its cheapest priced member.
- **Unpriced ingredient means no price** for the result. Items with no price cannot be bought or sold.
- **Value-creating loops** (for example 1 a -> 2 a) never settle. Items in such a loop lose their derived price and are reported, instead of being priced near zero.
- Implemented as a pure function in `src/pricing/derive.lua` (`mine_shop_gui.pricing.derive`), tested with `mtt`. Not yet wired to real recipes.

### Base price file (decided: Lua)

- Format: a Lua file that returns a table of `["mod:item"] = price units`. Comments and decimals are allowed. It runs in an empty environment, so it can only hold data (`src/pricing/base_prices.lua`).
- Two files are merged: `base_prices.lua` in the mod (shipped), and an optional `<world>/mine_shop_gui_prices.lua` that overrides it. `false` in the world file removes an item's price. Invalid entries are logged and skipped.
- Findings from dumping the installed content mods (51 mods, 4318 items): 618 items have no recipe at all. Most are Everness (275) and Ethereal (137), then Techage (89), default (66) and Technic (17).
- Raw items alone are not enough. Items that can only be made inside a cycle (for example cobblestone <-> stone <-> mossy cobblestone) or only by a skipped multi-output recipe (dirt from Technic's separating) also need a base price, and cobblestone is the unit anchor. The derivation shows which items are still unpriced, so the seed list is built by running it and adding anchors until nothing important is missing.

### Still to build

- A collector that turns `core.get_all_craft_recipes` (types `normal`, `shapeless`, `cooking`) and `technic.recipes` into the recipe list, and builds group membership. It must run after technic's own `register_on_mods_loaded` callback.
- The base price file and a seed list generated from the raw items in the installed mods.
- Markup settings in `settingtypes.txt`.
