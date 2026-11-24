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

## Auction house

Players trade with each other in the auction house: press **Auction** in the shop, or type `/ah`.

- **Sell** puts 1 to 8 stacks up at a fixed price. The price can be money, items (up to 8 stacks, so 8 stacks can buy 8 stacks), or both. The first buyer gets it. If the price is made of currency items (for example one 100 note), a buyer can pay with smaller ones (ten 10 notes) and the owner receives the 100 note.
- **Bid** starts at a minimum bid. Each new bid has to beat the last by a few percent, up to a buy-out price (5 times the start unless the owner chooses). Bidding is in money only and the goods cannot be money. When the time runs out the highest bidder gets the goods and the owner is paid; if nobody bid, the items go back. A buy-out ends it at once.
- Owners are paid only when an offer succeeds. Money and items that cannot be delivered (the player is offline, or their inventory is full) wait in the **Claims** tab and are handed over on join or with `/ah claim`.
- **My offers** shows what you have up and the auctions you lead. Taking an offer down returns the items and pays every bid back. Admins (privilege `server` or `auction_admin`) can take down any offer and receive its items.

Commands: `/ah`, `/ah sell hand|<itemstring>|<item name> [<amount>|all]`, `/ah bid ...` (the same), `/ah claim`, `/ah revoke <number>`. `sell` and `bid` take the items out of your inventory and open the window where you set the price. While that window is open the items are held in it; closing it gives them back.

### Discord (optional)

Offers can be posted to Discord. In your server make a **Forum** channel, then Channel settings, Integrations, Webhooks, New Webhook, and copy its URL. On the Luanti server:

```
mine_shop_gui_discord_webhook = https://discord.com/api/webhooks/<id>/<token>
secure.http_mods = mine_shop_gui
```

For an ordinary **text** channel that should still get one thread per offer, also set the channel's id and a bot's token (the bot must be in the server and may view the channel, create public threads and send messages in threads): `mine_shop_gui_discord_channel = <channel id>` and `mine_shop_gui_discord_bot_token = <token>`. The webhook posts the opening message, the bot starts a thread on it, and everything else goes into that thread. If the thread cannot be created the offer falls back to plain messages in the channel. Every new offer becomes a thread (items, price, owner, when it ends); bids, the sale or win, the end without a buyer and take-downs are posted into it. The first post is edited as the offer changes: it shows the current bid, and when the offer ends it is rewritten to start with **SOLD**, **EXPIRED** or **TAKEN DOWN** and shows the time it ended. While an offer runs, "Ends" is a Discord relative time ("in 3 hours") that counts down by itself in everyone's Discord. Editing needs Luanti 5.7 or newer. Posts use emoji (a price tag for sales, a hammer for bids, a check mark for SOLD, a trophy for a won auction, an hourglass for EXPIRED, a prohibited sign for TAKEN DOWN, and so on). Turn them off with `mine_shop_gui_discord_emojis = false`, or swap any for your own server emoji with `mine_shop_gui_discord_emoji_overrides = sold=<:sold:123456789012345678>, bid=<:gavel:123456789012345679>` (keys: sell, bid, goods, price, start, current_bid, buyout, ends, ended, sold, won, expired, taken_down). Mentions are switched off, so a player name or item title cannot ping anyone. Only offers made after the setup are posted. For an ordinary text channel set `mine_shop_gui_discord_threads = false`: the same messages are then posted to the channel as plain messages (a webhook cannot start threads there). Keep the URL secret: anyone who has it can post in the channel. It is never written to the log. Sending is one message at a time and a failure is logged and skipped, never affecting an offer.

Settings: `mine_shop_gui_ah_max_offers`, `mine_shop_gui_ah_duration`, `mine_shop_gui_ah_max_hours`, `mine_shop_gui_ah_bid_step`.

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
| `mine_shop_gui_ah_max_offers` | offers one player can have running (10) |
| `mine_shop_gui_ah_duration` | default length of an offer in hours (24) |
| `mine_shop_gui_ah_max_hours` | longest an offer may run (168) |
| `mine_shop_gui_ah_bid_step` | percent a bid must beat the last by (5) |

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
