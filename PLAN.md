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

## Testing notes

- `credits_old/mod.conf` was renamed to `name = credits_old` to avoid a load-time name clash. It still registers `credits:` items and the `/credits` command, so it will probably fail to load and conflicts with the new `credits`. Treat it as reference code. Test each credits version in its own world with only that version present.
- Test mods in the parent folder: currency, unified_money, um_atm, credits, credits_old, technic, techage_modpack, ethereal, everness, 3d_armor, pipeworks, i3, unified_inventory.

## Pricing outline (not yet decided in detail)

- Compute derived prices after all mods load, using `core.get_all_craft_recipes` plus Technic's registered machine recipes (API not yet checked).
- Detect recipe cycles (for example currency coin and note recipes).
