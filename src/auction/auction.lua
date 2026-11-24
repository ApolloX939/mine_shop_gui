-- The auction house: offers, buying, bidding, expiry and payouts. No interface
-- code here; the window and the /ah command call these functions.
--
-- Two kinds of offer, both holding 1 to 8 stacks of goods:
--   "sell"  a fixed price, paid in the currency, in items, or both. The first
--           buyer takes it.
--   "bid"   a starting bid and a buy-out price, currency only. Each bid must
--           beat the last; the highest bidder wins when time runs out, or at
--           once by paying the buy-out price.
--
-- The goods are held by the offer from the moment it is created (the caller
-- has already taken them from the owner). A bid's money is taken from the
-- bidder at once and paid back if somebody outbids them or the offer is
-- revoked. The owner is paid only when the offer succeeds.
--
-- Anything that cannot be handed over right now (the person is offline, or
-- their inventory is full) waits in a per-player queue and is delivered on
-- join or with /ah claim.
--
-- Every function that can fail returns true plus a result, or false plus a
-- reason: "unavailable", "invalid_items", "money_goods", "invalid_price",
-- "invalid_amount", "too_many_offers", "not_found", "wrong_kind", "own_offer",
-- "already_leading", "bid_too_low", "missing_items", "insufficient_funds",
-- "no_room", "not_allowed".

local api = mine_shop_gui.currency
local S = core.get_translator(core.get_current_modname())

local A = {}

A.MAX_STACKS = 8

-- Replaced by tests to move time along.
A.now = os.time

local storage = core.get_mod_storage()
local data

local function load()
	local text = storage:get_string("auction")
	local loaded = text ~= "" and core.deserialize(text)
	data = type(loaded) == "table" and loaded or {}
	data.next_id = data.next_id or 1
	data.offers = data.offers or {}
	data.pending = data.pending or {}
end

local function save()
	storage:set_string("auction", core.serialize(data))
end

A.save = save

-- Listeners hear about every change to an offer: fn(event, offer, info).
-- Events: "created", "bid" (info.bidder, info.amount), "sold" (info.buyer),
-- "bought_out" (info.buyer), "won" (the highest bidder took it at the end),
-- "expired" (nobody bought it), "revoked" (info.actor, info.by_admin).
A.listeners = {}

function A.on(fn)
	A.listeners[#A.listeners + 1] = fn
end

local function emit(event, offer, info)
	for _, fn in ipairs(A.listeners) do
		local ok, err = pcall(fn, event, offer, info or {})
		if not ok then core.log("error", "[mine_shop_gui] auction listener failed: " .. tostring(err)) end
	end
end

load()

-- Forget every offer and queued delivery. For tests only.
function A.reset()
	data = { next_id = 1, offers = {}, pending = {} }
	save()
end

---------------------------------------------------------------- settings

local function number_setting(key, default)
	local value = tonumber(core.settings:get(key))
	if value and value > 0 then return value end
	return default
end

local DURATIONS = { 1, 6, 12, 24, 48, 72, 168 }

-- The longest an offer may run, in hours.
function A.max_hours()
	return math.floor(number_setting("mine_shop_gui_ah_max_hours", 168))
end

-- The offer lengths a player can choose from, in hours.
function A.durations()
	local list, max = {}, A.max_hours()
	for _, hours in ipairs(DURATIONS) do
		if hours <= max then list[#list + 1] = hours end
	end
	if #list == 0 then list[1] = max end
	return list
end

function A.default_hours()
	return math.min(math.floor(number_setting("mine_shop_gui_ah_duration", 24)), A.max_hours())
end

function A.max_offers()
	return math.floor(number_setting("mine_shop_gui_ah_max_offers", 10))
end

-- How much a bid must beat the last one by, in percent.
function A.step_percent()
	return number_setting("mine_shop_gui_ah_bid_step", 5)
end

---------------------------------------------------------------- helpers

function A.is_admin(name)
	return core.check_player_privs(name, { server = true })
		or core.check_player_privs(name, { auction_admin = true })
end

function A.notify(name, text)
	if core.get_player_by_name(name) then
		core.chat_send_player(name, core.colorize("#ffd27f", "[Auction] ") .. text)
	end
end

local function inventory_of(name)
	local player = core.get_player_by_name(name)
	return player and player:get_inventory()
end

-- The title a player knows an item by.
function A.title(name)
	local def = core.registered_items[name]
	local text = def and def.description or ""
	text = text:gsub("\n.*", "")
	if core.strip_escapes then text = core.strip_escapes(text) end
	if text == "" then return name end
	return text
end

local function usable(offer)
	return api.get() ~= nil and offer.currency == api.get().name
end

-- Stacks of `count` items, none larger than the item's stack size.
local function stacks_of(name, count)
	local list = {}
	local max = (core.registered_items[name] or {}).stack_max or 99
	while count > 0 do
		local n = math.min(count, max)
		list[#list + 1] = ItemStack({ name = name, count = n })
		count = count - n
	end
	return list
end

local function valid_money(amount)
	return api.valid_amount(amount) and amount > 0 and api.round(amount) == amount
end

---------------------------------------------------------------- deliveries

local function queue(name, entry)
	local list = data.pending[name]
	if not list then
		list = {}
		data.pending[name] = list
	end
	list[#list + 1] = entry
end

-- Pay money to a player now, or queue it if they are away or the payment fails.
local function deliver_money(name, amount)
	if amount <= 0 then return end
	if core.get_player_by_name(name) and api.deposit(name, amount) then return end
	queue(name, { type = "money", amount = amount, currency = api.get().name })
end

-- Give items to a player now, or queue whatever does not fit.
local function deliver_items(name, stacks)
	local inv = inventory_of(name)
	for _, stack in ipairs(stacks) do
		local rest = stack
		if inv then rest = inv:add_item("main", stack) end
		if not rest:is_empty() then queue(name, { type = "items", stack = rest:to_string() }) end
	end
end

A.deliver_items = deliver_items

-- How many deliveries wait for a player.
function A.pending_count(name)
	return #(data.pending[name] or {})
end

-- What waits for a player: a list of { type = "money", amount } and { type = "items", stack }.
function A.pending(name)
	return data.pending[name] or {}
end

-- Hand over everything that waits. Returns how many items and how much money
-- arrived, and how many deliveries are still waiting (no room, wrong currency).
function A.claim(name)
	local list = data.pending[name]
	local inv = inventory_of(name)
	if not list or not inv then return 0, 0, #(list or {}) end
	local kept, items, money = {}, 0, 0
	for _, entry in ipairs(list) do
		if entry.type == "money" then
			if usable(entry) and api.deposit(name, entry.amount) then
				money = money + entry.amount
			else
				kept[#kept + 1] = entry
			end
		else
			local stack = ItemStack(entry.stack)
			local rest = inv:add_item("main", stack)
			items = items + stack:get_count() - rest:get_count()
			if not rest:is_empty() then kept[#kept + 1] = { type = "items", stack = rest:to_string() } end
		end
	end
	data.pending[name] = #kept > 0 and kept or nil
	save()
	return items, money, #kept
end

---------------------------------------------------------------- reading offers

function A.get(id)
	local offer = data.offers[id]
	if offer and offer.expires > A.now() then return offer end
	return nil
end

-- The goods of an offer as ItemStacks.
function A.goods(offer)
	local list = {}
	for i, text in ipairs(offer.goods) do list[i] = ItemStack(text) end
	return list
end

-- What a sell offer asks for besides money: { { name, count }, ... }.
function A.price_items(offer)
	return offer.items or {}
end

-- The least a bidder can bid now.
function A.next_bid(offer)
	if not offer.bidder then return offer.start end
	local unit = api.get().unit()
	local step = api.round(offer.bid * A.step_percent() / 100)
	return math.min(offer.bid + math.max(step, unit), offer.buyout)
end

-- Seconds until the offer ends.
function A.time_left(offer)
	return math.max(0, offer.expires - A.now())
end

-- Active offers, newest first. filter: kind ("sell" / "bid"), owner, query
-- (words that must all appear in an item's name or title, or the owner's name).
function A.list(filter)
	filter = filter or {}
	A.process_expired()
	local words = {}
	for word in (filter.query or ""):lower():gmatch("%S+") do words[#words + 1] = word end

	local list = {}
	for _, offer in pairs(data.offers) do
		local keep = usable(offer)
			and (not filter.kind or offer.kind == filter.kind)
			and (not filter.owner or offer.owner == filter.owner)
		if keep and #words > 0 then
			local text = { offer.owner:lower() }
			for _, stack in ipairs(A.goods(offer)) do
				text[#text + 1] = stack:get_name():lower()
				text[#text + 1] = A.title(stack:get_name()):lower()
			end
			local haystack = table.concat(text, " ")
			for _, word in ipairs(words) do
				if not haystack:find(word, 1, true) then keep = false break end
			end
		end
		if keep then list[#list + 1] = offer end
	end
	table.sort(list, function(a, b) return a.id > b.id end)
	return list
end

-- How many active offers a player has.
function A.count_offers(owner)
	local n = 0
	for _, offer in pairs(data.offers) do
		if offer.owner == owner then n = n + 1 end
	end
	return n
end

-- Offers a player leads in, as a bidder.
function A.leading(name)
	local list = {}
	for _, offer in pairs(A.list({ kind = "bid" })) do
		if offer.bidder == name then list[#list + 1] = offer end
	end
	return list
end

---------------------------------------------------------------- creating

-- Put an offer on the auction house. The caller has already taken the goods
-- from the owner: on failure, they are still the caller's to give back.
--
--   spec.kind         "sell" or "bid"
--   spec.goods        list of ItemStacks (empty ones are skipped), 1 to 8
--   spec.money        sell: price in currency (default 0)
--   spec.price_items  sell: list of ItemStacks asked for. Stacks of the
--                     currency's own items count as money instead.
--   spec.start        bid: the starting bid
--   spec.buyout       bid: the buy-out price (default 5 times the start)
--   spec.hours        how long the offer runs (default from the settings)
function A.create(owner, spec)
	if not api.get() then return false, "unavailable" end
	if spec.kind ~= "sell" and spec.kind ~= "bid" then return false, "invalid_items" end

	local goods, has_money_goods = {}, false
	for _, stack in ipairs(spec.goods or {}) do
		if not stack:is_empty() then
			if not core.registered_items[stack:get_name()] then return false, "invalid_items" end
			if api.stack_value(stack) then has_money_goods = true end
			goods[#goods + 1] = stack:to_string()
		end
	end
	if #goods < 1 or #goods > A.MAX_STACKS then return false, "invalid_items" end

	local hours = tonumber(spec.hours) or A.default_hours()
	hours = math.max(1, math.min(math.floor(hours), A.max_hours()))
	if A.count_offers(owner) >= A.max_offers() then return false, "too_many_offers" end

	local offer = {
		kind = spec.kind, owner = owner, goods = goods, currency = api.get().name,
		created = A.now(), expires = A.now() + hours * 3600,
	}

	if spec.kind == "bid" then
		-- money cannot be auctioned for money
		if has_money_goods then return false, "money_goods" end
		local start = spec.start
		if not valid_money(start) then return false, "invalid_price" end
		local buyout = spec.buyout or api.round(start * 5)
		if not valid_money(buyout) or buyout <= start then return false, "invalid_price" end
		offer.start, offer.buyout = start, buyout
	else
		local money, wanted, order = spec.money or 0, {}, {}
		if money ~= 0 and not valid_money(money) then return false, "invalid_price" end
		for _, stack in ipairs(spec.price_items or {}) do
			if not stack:is_empty() then
				local name = stack:get_name()
				if not core.registered_items[name] then return false, "invalid_price" end
				local value = api.stack_value(stack)
				if value then
					-- the currency's own items are paid through the currency, so
					-- ten small notes can pay for one big one
					if value <= 0 then return false, "invalid_price" end
					money = money + value
				else
					if not wanted[name] then
						wanted[name] = 0
						order[#order + 1] = name
					end
					wanted[name] = wanted[name] + stack:get_count()
				end
			end
		end
		if money ~= 0 and not valid_money(money) then return false, "invalid_price" end
		if money == 0 and #order == 0 then return false, "invalid_price" end
		if money > 0 and has_money_goods then return false, "money_goods" end
		offer.money, offer.items = money, {}
		for i, name in ipairs(order) do offer.items[i] = { name = name, count = wanted[name] } end
	end

	offer.id = data.next_id
	data.next_id = data.next_id + 1
	data.offers[offer.id] = offer
	save()
	emit("created", offer)
	return true, offer
end

---------------------------------------------------------------- closing

local function remove(offer)
	data.offers[offer.id] = nil
end

-- The stacks a sell offer's buyer pays in items.
local function price_stacks(offer)
	local list = {}
	for _, entry in ipairs(offer.items or {}) do
		for _, stack in ipairs(stacks_of(entry.name, entry.count)) do list[#list + 1] = stack end
	end
	return list
end

-- How many undamaged `name` items an inventory holds.
local function count_whole(inv, name)
	local total = 0
	for _, stack in ipairs(inv:get_list("main")) do
		if stack:get_name() == name and stack:get_wear() == 0 then total = total + stack:get_count() end
	end
	return total
end

local function take_whole(inv, name, count)
	local list = inv:get_list("main")
	for _, stack in ipairs(list) do
		if count == 0 then break end
		if stack:get_name() == name and stack:get_wear() == 0 then
			local n = math.min(count, stack:get_count())
			stack:take_item(n)
			count = count - n
		end
	end
	inv:set_list("main", list)
end

local function undo(buyer, inv, inventory_before, money_before)
	api.restore(buyer, money_before)
	inv:set_list("main", inventory_before)
end

-- Hand every stack to the buyer's inventory, or undo everything.
local function add_goods(offer, buyer, inv, inventory_before, money_before)
	for _, stack in ipairs(A.goods(offer)) do
		if not inv:add_item("main", stack):is_empty() then
			undo(buyer, inv, inventory_before, money_before)
			return false
		end
	end
	return true
end

local function open_offer(id, kind)
	local offer = A.get(id)
	if not offer then return nil, "not_found" end
	if offer.kind ~= kind then return nil, "wrong_kind" end
	if not usable(offer) then return nil, "unavailable" end
	return offer
end

-- Buy a sell offer at its price.
function A.buy(buyer, id)
	local offer, why = open_offer(id, "sell")
	if not offer then return false, why end
	if offer.owner == buyer then return false, "own_offer" end
	local inv = inventory_of(buyer)
	if not inv then return false, "unavailable" end

	for _, entry in ipairs(offer.items) do
		if count_whole(inv, entry.name) < entry.count then return false, "missing_items" end
	end

	local inventory_before = inv:get_list("main")
	local money_before = api.snapshot(buyer)
	if offer.money > 0 then
		local paid, reason = api.withdraw(buyer, offer.money)
		if not paid then return false, reason end
	end
	for _, entry in ipairs(offer.items) do
		if count_whole(inv, entry.name) < entry.count then
			undo(buyer, inv, inventory_before, money_before)
			return false, "missing_items"
		end
		take_whole(inv, entry.name, entry.count)
	end
	if not add_goods(offer, buyer, inv, inventory_before, money_before) then return false, "no_room" end

	remove(offer)
	deliver_money(offer.owner, offer.money)
	deliver_items(offer.owner, price_stacks(offer))
	save()
	A.notify(offer.owner, S("@1 bought your offer #@2.", buyer, offer.id))
	emit("sold", offer, { buyer = buyer })
	return true, { offer = offer }
end

-- Pay the buy-out price of a bid offer and take the goods at once.
function A.buyout(buyer, id)
	local offer, why = open_offer(id, "bid")
	if not offer then return false, why end
	if offer.owner == buyer then return false, "own_offer" end
	local inv = inventory_of(buyer)
	if not inv then return false, "unavailable" end

	local inventory_before = inv:get_list("main")
	local money_before = api.snapshot(buyer)
	-- the highest bidder's money is already held: they only pay the rest
	local leading = offer.bidder == buyer
	local paid, reason = api.withdraw(buyer, leading and offer.buyout - offer.bid or offer.buyout)
	if not paid then return false, reason end
	if not add_goods(offer, buyer, inv, inventory_before, money_before) then return false, "no_room" end

	remove(offer)
	if offer.bidder and not leading then
		deliver_money(offer.bidder, offer.bid)
		A.notify(offer.bidder, S("Offer #@1 was bought out. Your bid was paid back.", offer.id))
	end
	deliver_money(offer.owner, offer.buyout)
	save()
	A.notify(offer.owner, S("@1 bought out your offer #@2.", buyer, offer.id))
	emit("bought_out", offer, { buyer = buyer })
	return true, { offer = offer, cost = offer.buyout }
end

-- Place a bid. Without an amount, the least that is allowed. A bid of the
-- buy-out price is a buy-out.
function A.bid(bidder, id, amount)
	local offer, why = open_offer(id, "bid")
	if not offer then return false, why end
	if offer.owner == bidder then return false, "own_offer" end
	if offer.bidder == bidder then return false, "already_leading" end

	amount = amount or A.next_bid(offer)
	if not valid_money(amount) or amount > offer.buyout then return false, "invalid_amount" end
	if amount < A.next_bid(offer) then return false, "bid_too_low" end
	if amount == offer.buyout then return A.buyout(bidder, id) end

	local paid, reason = api.withdraw(bidder, amount)
	if not paid then return false, reason end

	local previous, previous_bid = offer.bidder, offer.bid
	offer.bidder, offer.bid = bidder, amount
	if previous then
		deliver_money(previous, previous_bid)
		A.notify(previous, S("You were outbid on offer #@1.", offer.id))
	end
	save()
	A.notify(offer.owner, S("@1 bid @2 on your offer #@3.", bidder, api.format_symbol(amount), offer.id))
	emit("bid", offer, { bidder = bidder, amount = amount })
	return true, { offer = offer, amount = amount }
end

-- Take an offer down: the bid is paid back and the goods go to `actor`, who
-- is the owner or an admin.
function A.revoke(actor, id)
	local offer = A.get(id)
	if not offer then return false, "not_found" end
	if actor ~= offer.owner and not A.is_admin(actor) then return false, "not_allowed" end
	if offer.bidder and not usable(offer) then return false, "unavailable" end

	remove(offer)
	if offer.bidder then
		deliver_money(offer.bidder, offer.bid)
		A.notify(offer.bidder, S("Offer #@1 was taken down. Your bid was paid back.", offer.id))
	end
	deliver_items(actor, A.goods(offer))
	save()
	if actor ~= offer.owner then
		A.notify(offer.owner, S("An admin took down your offer #@1.", offer.id))
	end
	emit("revoked", offer, { actor = actor, by_admin = actor ~= offer.owner })
	return true, { offer = offer }
end

-- Close every offer whose time is up. Returns how many were closed.
function A.process_expired()
	local now, closed = A.now(), 0
	for _, offer in pairs(data.offers) do
		if offer.expires <= now then
			if offer.bidder then
				-- a won auction: the winner gets the goods, the owner the money
				if usable(offer) then
					remove(offer)
					deliver_items(offer.bidder, A.goods(offer))
					deliver_money(offer.owner, offer.bid)
					A.notify(offer.bidder, S("You won offer #@1.", offer.id))
					A.notify(offer.owner, S("Your offer #@1 sold for @2.", offer.id, api.format_symbol(offer.bid)))
					emit("won", offer)
					closed = closed + 1
				end
			else
				remove(offer)
				deliver_items(offer.owner, A.goods(offer))
				A.notify(offer.owner, S("Your offer #@1 ended without a buyer. The items were returned.", offer.id))
				emit("expired", offer)
				closed = closed + 1
			end
		end
	end
	if closed > 0 then save() end
	return closed
end

---------------------------------------------------------------- timers and joining

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 30 then return end
	timer = 0
	A.process_expired()
end)

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	core.after(3, function()
		if not core.get_player_by_name(name) then return end
		A.process_expired()
		local count = A.pending_count(name)
		if count > 0 then
			local items, money, left = A.claim(name)
			if items > 0 or money > 0 then
				A.notify(name, S("Auction deliveries arrived: @1 items, @2.", items, api.format_symbol(money)))
			end
			if left > 0 then
				A.notify(name, S("@1 auction deliveries are waiting. Make room and use /ah claim.", left))
			end
		end
	end)
end)

core.register_privilege("auction_admin", {
	description = S("Can take down any offer on the auction house"),
	give_to_singleplayer = false,
})

mine_shop_gui.auction = A
