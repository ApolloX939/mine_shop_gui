# Mine ShopGUI

A shop for Luanti (Minetest). Players open it with `/shop`, browse items by category or search, and buy or sell any amount. Prices are not typed in item by item: they are worked out from a short list of base prices and from the recipes of every installed mod, including Technic and Techage machines.

## Using the shop

Type `/shop`, or `/shop <words>` to jump straight to a search.

1. **Categories.** One per mod (small mods are grouped under "Other"), plus "Everything". There is a search box.
2. **Items.** A grid of item pictures with the name and the price to buy under each one; hover for the sell price too. Prices and your balance are shown with a small picture of the currency (for example the Minegeld note).
3. **Trade.** Pick an amount with the `-64 -10 -1 +1 +10 +64` buttons or type it. The total is shown, then **BUY**, **SELL**, or **SELL ALL**.

The **Sell** button (top right of the category and item screens) lists everything in your inventory the shop buys, with what it would pay; pick one to sell it.

Or use the command: `/sell hand|<itemstring>|<item name> [<amount>|all]`, for example `/sell hand`, `/sell default:cobble 20` or `/sell Gold Ingot all`. Without an amount one item is sold (`hand` sells the whole stack in your hand).

Buying and selling are all-or-nothing. If the goods do not fit, or the money cannot be taken, nothing changes. Tools with wear and stacks marked as unsellable are never taken.

## Currencies

The shop picks one automatically, or you choose in the settings. It works with:

- **currency** (Minegeld notes and coins, with change made for you)
- **unified_money** (account balance)
- **credits** (digital balance, and physical credits; both V1.2.3 and V1.3)
- **any items you name**, for example emeralds in Mineclonia or VoxeLibre. A working setup:

  ```
  mine_shop_gui_currency = items
  mine_shop_gui_item_currency = default:steel_ingot
  mine_shop_gui_item_currency_label = Ingots
  mine_shop_gui_item_currency_worth = 8
  ```

  Here one steel ingot is worth 8 cobblestones, so 16 cobblestones cost 2 ingots. The currency items are shown beside prices and are never sold in the shop.

## Settings

All settings are in the Luanti settings menu under "Mine ShopGUI".

| Setting | Meaning |
|---|---|
| `mine_shop_gui_currency` | `auto`, `currency`, `unified_money`, `credits` or `items`. `currency` means the Minegeld mod; to use your own item, choose `items`. On `auto`, an item currency you have set up is used first |
| `mine_shop_gui_sell_ratio` | share of the buy price paid when selling (0.5 = half) |
| `mine_shop_gui_scale_<currency>` | how much of that currency one price unit is worth |
| `mine_shop_gui_markup_<recipe type>` | extra percentage on items made by that kind of recipe |
| `mine_shop_gui_max_amount` | the most a player can buy at once |
| `mine_shop_gui_item_currency` | the items that are the money: `default:steel_ingot`, or `mcl_core:emerald_block=9, mcl_core:emerald=1` (an item with no value is worth 1) |
| `mine_shop_gui_item_currency_worth` | how many price units one unit of the item currency is worth. Empty uses the shop's own price for the smallest item |
| `mine_shop_gui_item_currency_label` | the name shown after amounts, for example `Ingots` |

One price unit is the value of one cobblestone.

## Prices

Raw items (things no recipe makes) get a price from a Lua file; everything else is priced from its cheapest recipe, assuming players always use the best machine. The files are:

- `prices/games/<game id>.lua` for the running game
- `prices/mods/<mod name>.lua` for each installed mod (name it after the `name` in the mod's `mod.conf`)
- `<world>/mine_shop_gui_prices.lua`, your own overrides; `false` removes an item's price

A price is a ceiling: if a recipe makes the item for less, the recipe's cost is used. Write `{ price = 1, fixed = true }` to keep a price whatever recipes say. Items with no price cannot be traded.

On start-up the log tells you about prices that recipes lowered and about machine loops that gain value (for example two mods that together turn sand into more sand), which players can exploit outside the shop.

## For mod authors

Keep an item out of the shop, in either direction, in its definition:

```lua
core.register_craftitem("mymod:thing", {
    _mine_shop_gui = { no_buy = true, no_sell = true },
})
```

Flag a single stack with item metadata, using the string `"true"` (metadata has no boolean setter):

```lua
stack:get_meta():set_string("no_sell", "true")
```

Anything made from a flagged ingredient inherits its flags.

Change prices after they are built, from your own mod:

```lua
mine_shop_gui.register_on_prices_generated(function(items)
    items["mymod:thing"] = { price = 12 }       -- add or change
    items["default:dirt"].no_sell = true         -- flag
    items["default:stone"] = nil                 -- remove
end)
```

## Tests

The tests run in the real Luanti engine through the `mtt` mod. See `AGENTS.md` for how to start them. Other plans and open questions are in `PLAN.md`, `PLAN_V2.md` and `TODO.md`.
