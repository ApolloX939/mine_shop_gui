-- The auction house window.
--
-- Screens: browse (every offer, with filters and search), mine (your offers and
-- the auctions you lead), claims (deliveries that waited), offer (one offer in
-- detail) and create (a new sell or bid offer).
--
-- Everything a player clicks arrives as form fields. Offers are named by their
-- position on the current page; the server looks the real offer up, so a
-- forged field cannot name something the page did not show.
--
-- The create screen uses a detached inventory per player: items dragged into
-- its "goods" slots leave the player's inventory and wait there until the
-- offer is published or the window is closed. The "price" slots hold copies
-- of the items asked for (sell offers only); they are not taken from the player.

local api = mine_shop_gui.currency
local A = mine_shop_gui.auction
local widgets = mine_shop_gui.shop.ui.widgets
local money_widget, input_field, shorten = widgets.money_widget, widgets.input_field, widgets.shorten

local S = core.get_translator(core.get_current_modname())
local esc = core.formspec_escape

local FORM = "mine_shop_gui:auction"
local PER_PAGE = 5
local ROW_HEIGHT = 1.3

local ui = {}
local states = {}
local detached = {} -- player name -> the create screen's inventory

-- Replaced by tests so a window can be inspected without a connected player.
ui.send = function(name, formspec)
	core.show_formspec(name, FORM, formspec)
end

local REASONS = {
	unavailable = S("The auction house cannot do that right now."),
	invalid_items = S("Put between 1 and 8 stacks of items on offer."),
	money_goods = S("Money cannot be auctioned for money."),
	invalid_price = S("That is not a price the currency can pay."),
	invalid_amount = S("That amount is not allowed."),
	too_many_offers = S("You have too many offers running."),
	not_found = S("That offer is not there any more."),
	wrong_kind = S("That does not work on this kind of offer."),
	own_offer = S("That is your own offer."),
	already_leading = S("You already have the highest bid."),
	bid_too_low = S("Your bid is too low."),
	missing_items = S("You do not have the items it asks for."),
	insufficient_funds = S("You cannot afford that."),
	no_room = S("There is no room in your inventory."),
	not_allowed = S("You are not allowed to do that."),
}

ui.REASONS = REASONS

local function reason(code)
	return REASONS[code] or REASONS.unavailable
end

---------------------------------------------------------------- the create screen's inventory

local function inventory_name(name)
	return "mine_shop_gui_ah_" .. name
end

-- Give back everything the create screen holds and remove its inventory.
local function release(name)
	local inv = detached[name]
	if not inv then return end
	detached[name] = nil
	A.deliver_items(name, inv:get_list("goods") or {})
	core.remove_detached_inventory(inventory_name(name))
end

-- Is this slot free for `stack`? Returns how many items fit.
local function room_for(inv, listname, index, stack)
	local present = inv:get_stack(listname, index)
	if present:is_empty() then return stack:get_count() end
	if present:get_name() ~= stack:get_name() then return 0 end
	return math.min(stack:get_count(), present:get_free_space())
end

local function callbacks_for(name)
	local function mine(player)
		return player:get_player_name() == name
	end
	local function creating()
		local state = states[name]
		return state and state.screen == "create" and state
	end
	return {
		allow_put = function(inv, listname, index, stack, player)
			local state = creating()
			if not state or not mine(player) then return 0 end
			if listname == "price" then
				-- a price slot holds a copy: it takes one empty slot at a time
				if state.kind ~= "sell" or not inv:get_stack("price", index):is_empty() then return 0 end
				return stack:get_count()
			end
			if state.kind == "bid" and api.stack_value(stack) then return 0 end
			return room_for(inv, listname, index, stack)
		end,
		allow_take = function(_, listname, _, stack, player)
			if not creating() or not mine(player) or listname == "price" then return 0 end
			return stack:get_count()
		end,
		allow_move = function(inv, from_list, _, to_list, to_index, count, player)
			if not creating() or not mine(player) then return 0 end
			if from_list ~= "goods" or to_list ~= "goods" then return 0 end
			local to = inv:get_stack("goods", to_index)
			if to:is_empty() then return count end
			return 0
		end,
		on_put = function(_, listname, _, stack)
			-- the price is only a picture of what is asked for: the items go back
			if listname == "price" then A.deliver_items(name, { stack }) end
		end,
	}
end

---------------------------------------------------------------- pieces

local function duration(seconds)
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if days > 0 then return S("@1d @2h", days, hours) end
	if hours > 0 then return S("@1h @2m", hours, minutes) end
	if minutes > 0 then return S("@1m", minutes) end
	return S("@1s", math.floor(seconds))
end

ui.duration = duration

local function header(name, title, height)
	local balance = api.balance(name)
	return table.concat({
		"formspec_version[6]size[15,", tostring(height or 11), "]",
		"label[0.5,0.7;", esc(title), "]",
		"label[9.4,0.7;", esc(S("Balance:")), "]",
		money_widget(10.9, 0.45, balance),
	})
end

local TABS = {
	{ "tab_browse", S("Browse") },
	{ "tab_mine", S("My offers") },
	{ "tab_claims", S("Claims") },
	{ "new_sell", S("New sale") },
	{ "new_bid", S("New bid") },
	{ "to_shop", S("Shop") },
}

local function tabs(name, state)
	local out = {}
	for i, tab in ipairs(TABS) do
		local label = tab[2]
		if tab[1] == "tab_claims" then
			local count = A.pending_count(name)
			if count > 0 then label = S("Claims (@1)", count) end
		end
		local x = 0.5 + (i - 1) * 2.3
		out[#out + 1] = string.format("button[%g,1.2;2.1,0.8;%s;%s]", x, tab[1], esc(label))
	end
	local current = ({ browse = "tab_browse", mine = "tab_mine", claims = "tab_claims" })[state.screen]
	if current then out[#out + 1] = string.format("style[%s;bgcolor=#3a7a52]", current) end
	return table.concat(out)
end

local function paging(page, pages)
	if pages <= 1 then return "" end
	return table.concat({
		"button[4.6,10.1;2,0.7;prev;<]",
		"label[7.0,10.45;", esc(S("Page @1 / @2", page, pages)), "]",
		"button[8.8,10.1;2,0.7;next;>]",
	})
end

local function message_line(state, y)
	if not state.message then return "" end
	local color = state.message.ok and "#9cff9c" or "#ff9c9c"
	return "label[0.5," .. y .. ";" .. esc(core.colorize(color, state.message.text)) .. "]"
end

local function say(state, ok, text)
	state.message = { ok = ok, text = text }
end

-- A row of item pictures with their counts underneath and a tooltip over each.
-- Returns the formspec and the x where the row ends.
local function strip(stacks, x, y, size, pitch, limit)
	local out = {}
	for i, stack in ipairs(stacks) do
		if i > limit then
			out[#out + 1] = string.format("label[%g,%g;%s]", x, y + size / 2, esc("+" .. (#stacks - limit)))
			x = x + 0.7
			break
		end
		local title = A.title(stack:get_name())
		out[#out + 1] = string.format("item_image[%g,%g;%g,%g;%s]", x, y, size, size, esc(stack:get_name()))
		out[#out + 1] = string.format("label[%g,%g;%s]", x + 0.05, y + size + 0.2, esc("x" .. stack:get_count()))
		out[#out + 1] = string.format("tooltip[%g,%g;%g,%g;%s]", x, y, size, size,
			esc(title .. "\n" .. stack:get_name() .. "\nx" .. stack:get_count()))
		x = x + pitch
	end
	return table.concat(out), x
end

local function price_stacks(offer)
	local list = {}
	for i, entry in ipairs(A.price_items(offer)) do list[i] = ItemStack({ name = entry.name, count = entry.count }) end
	return list
end

local function kind_label(offer)
	return offer.kind == "sell" and S("Selling") or S("Bidding")
end

local function find_offer(state)
	return state.offer_id and A.get(state.offer_id)
end

---------------------------------------------------------------- screens

-- One row per offer, five to a page.
local function offer_rows(state, offers, viewer)
	local slice, page, pages = mine_shop_gui.shop.catalog.page(offers, state.page, PER_PAGE)
	state.page, state.page_offers = page, {}
	local out = {}
	for i, offer in ipairs(slice) do
		state.page_offers[i] = offer.id
		local y = 3.1 + (i - 1) * ROW_HEIGHT
		out[#out + 1] = string.format("box[0.4,%g;14.2,1.2;#ffffff12]", y)
		out[#out + 1] = (strip(A.goods(offer), 0.5, y + 0.1, 0.8, 0.95, 4))

		local role = ""
		if offer.owner == viewer then role = " " .. S("(yours)")
		elseif offer.bidder == viewer then role = " " .. S("(you lead)") end
		out[#out + 1] = string.format("label[5.2,%g;%s]", y + 0.35,
			esc(S("#@1 @2 by @3", offer.id, kind_label(offer), shorten(offer.owner, 16))))
		out[#out + 1] = string.format("label[5.2,%g;%s]", y + 0.85,
			esc(S("Time left: @1", duration(A.time_left(offer))) .. role))

		if offer.kind == "sell" then
			if offer.money > 0 then
				out[#out + 1] = string.format("label[9.6,%g;%s]", y + 0.35, esc(S("Price:")))
				out[#out + 1] = money_widget(10.6, y + 0.1, offer.money)
			end
			if #offer.items > 0 then
				local names = {}
				for j, entry in ipairs(offer.items) do names[j] = entry.count .. " " .. A.title(entry.name) end
				out[#out + 1] = string.format("label[9.6,%g;%s]", y + 0.85,
					esc(shorten((offer.money > 0 and "+ " or "") .. table.concat(names, ", "), 26)))
			end
		else
			out[#out + 1] = string.format("label[9.6,%g;%s]", y + 0.35, esc(offer.bidder and S("Bid:") or S("Start:")))
			out[#out + 1] = money_widget(10.6, y + 0.1, offer.bidder and offer.bid or offer.start)
			out[#out + 1] = string.format("label[9.6,%g;%s]", y + 0.85, esc(S("Buy-out:")))
			out[#out + 1] = money_widget(10.9, y + 0.6, offer.buyout)
		end
		out[#out + 1] = string.format("button[12.7,%g;1.8,0.9;view_%d;%s]", y + 0.15, i, esc(S("View")))
	end
	return table.concat(out), page, pages
end

local FILTERS = { { "all", S("All") }, { "sell", S("Selling") }, { "bid", S("Bidding") } }

local function browse_screen(name, state)
	local offers = A.list({ kind = state.filter ~= "all" and state.filter or nil, query = state.query })
	local rows, page, pages = offer_rows(state, offers, name)
	local out = { header(name, S("Auction House")), tabs(name, state) }
	for i, filter in ipairs(FILTERS) do
		out[#out + 1] = string.format("button[%g,2.1;1.7,0.7;filter_%s;%s]", 0.5 + (i - 1) * 1.9, filter[1], esc(filter[2]))
		if state.filter == filter[1] then
			out[#out + 1] = string.format("style[filter_%s;bgcolor=#3a7a52]", filter[1])
		end
	end
	out[#out + 1] = input_field(6.4, 2.1, 5, 0.7, "query", state.query)
	out[#out + 1] = "field_close_on_enter[query;false]"
	out[#out + 1] = string.format("button[11.6,2.1;1.8,0.7;do_search;%s]", esc(S("Search")))
	if #offers == 0 then out[#out + 1] = "label[0.5,3.8;" .. esc(S("No offers found.")) .. "]" end
	out[#out + 1] = rows
	out[#out + 1] = paging(page, pages)
	out[#out + 1] = message_line(state, 10.5)
	return table.concat(out)
end

local function mine_screen(name, state)
	local offers, seen = A.list({ owner = name }), {}
	for _, offer in ipairs(offers) do seen[offer.id] = true end
	for _, offer in ipairs(A.leading(name)) do
		if not seen[offer.id] then offers[#offers + 1] = offer end
	end
	local rows, page, pages = offer_rows(state, offers, name)
	local out = { header(name, S("My offers")), tabs(name, state) }
	if #offers == 0 then out[#out + 1] = "label[0.5,3.2;" .. esc(S("You have no offers and lead no auctions.")) .. "]" end
	out[#out + 1] = rows
	out[#out + 1] = paging(page, pages)
	out[#out + 1] = message_line(state, 10.5)
	return table.concat(out)
end

local function claims_screen(name, state)
	local list = A.pending(name)
	local out = { header(name, S("Claims")), tabs(name, state) }
	if #list == 0 then
		out[#out + 1] = "label[0.5,3.2;" .. esc(S("Nothing is waiting for you.")) .. "]"
	else
		out[#out + 1] = "label[0.5,2.5;" .. esc(S("These could not be delivered when they were due.")) .. "]"
		for i = 1, math.min(#list, 8) do
			local entry = list[i]
			local y = 3.0 + (i - 1) * 0.7
			if entry.type == "money" then
				out[#out + 1] = string.format("label[0.5,%g;%s]", y + 0.25, esc(S("Payment:")))
				out[#out + 1] = money_widget(2.4, y, entry.amount)
			else
				local stack = ItemStack(entry.stack)
				out[#out + 1] = string.format("item_image[0.5,%g;0.6,0.6;%s]", y, esc(stack:get_name()))
				out[#out + 1] = string.format("label[1.3,%g;%s]", y + 0.3, esc(A.title(stack:get_name()) .. " x" .. stack:get_count()))
			end
		end
		if #list > 8 then out[#out + 1] = "label[0.5,8.8;" .. esc(S("... and @1 more", #list - 8)) .. "]" end
		out[#out + 1] = string.format("button[10.5,3.0;4,1;claim;%s]", esc(S("CLAIM ALL")))
	end
	out[#out + 1] = message_line(state, 10.5)
	return table.concat(out)
end

local function offer_screen(name, state)
	local offer = find_offer(state)
	local out = { header(name, S("Offer")), tabs(name, state) }
	if not offer then
		out[#out + 1] = "label[0.5,3.2;" .. esc(S("That offer is not there any more.")) .. "]"
		out[#out + 1] = message_line(state, 10.5)
		return table.concat(out)
	end

	out[#out + 1] = "label[0.5,2.4;" .. esc(S("Items:")) .. "]"
	out[#out + 1] = (strip(A.goods(offer), 0.5, 2.7, 1.3, 1.7, 8))
	out[#out + 1] = "label[0.5,4.7;" .. esc(S("#@1 @2 by @3", offer.id, kind_label(offer), offer.owner)) .. "]"
	out[#out + 1] = "label[8.0,4.7;" .. esc(S("Time left: @1", duration(A.time_left(offer)))) .. "]"

	local own = offer.owner == name
	if offer.kind == "sell" then
		if offer.money > 0 then
			out[#out + 1] = "label[0.5,5.5;" .. esc(S("Price:")) .. "]" .. money_widget(2.0, 5.25, offer.money)
		end
		if #offer.items > 0 then
			out[#out + 1] = "label[0.5,6.3;" .. esc(offer.money > 0 and S("And these items:") or S("Price, in items:")) .. "]"
			out[#out + 1] = (strip(price_stacks(offer), 4.5, 5.9, 0.9, 1.3, 8))
		end
		if not own then out[#out + 1] = string.format("button[0.5,8.0;3.6,1;buy;%s]", esc(S("BUY"))) end
	else
		out[#out + 1] = "label[0.5,5.5;" .. esc(offer.bidder and S("Current bid:") or S("Starting bid:")) .. "]"
		out[#out + 1] = money_widget(3.0, 5.25, offer.bidder and offer.bid or offer.start)
		if offer.bidder then out[#out + 1] = "label[6.0,5.5;" .. esc(S("Highest bidder: @1", offer.bidder)) .. "]" end
		out[#out + 1] = "label[0.5,6.2;" .. esc(S("Buy-out:")) .. "]" .. money_widget(3.0, 5.95, offer.buyout)
		out[#out + 1] = "label[0.5,6.9;" .. esc(S("Next bid:")) .. "]" .. money_widget(3.0, 6.65, A.next_bid(offer))
		if not own then
			out[#out + 1] = input_field(0.5, 8.0, 2.6, 1, "bid_amount", api.number(state.bid_amount or A.next_bid(offer)))
			out[#out + 1] = "field_close_on_enter[bid_amount;false]"
			out[#out + 1] = string.format("button[3.3,8.0;3.2,1;bid;%s]", esc(S("BID")))
			out[#out + 1] = string.format("button[6.7,8.0;3.6,1;buyout;%s]", esc(S("BUY OUT")))
		end
	end
	if own or A.is_admin(name) then
		out[#out + 1] = string.format("button[10.7,8.0;3.8,1;revoke;%s]",
			esc(own and S("TAKE DOWN") or S("TAKE DOWN (admin)")))
	end
	out[#out + 1] = message_line(state, 9.6)
	return table.concat(out)
end

local function create_screen(name, state)
	local out = { header(name, state.kind == "sell" and S("New sale") or S("New bid"), 12), tabs(name, state) }
	local list = "detached:" .. esc(inventory_name(name))
	out[#out + 1] = "label[0.5,2.4;" .. esc(S("Items you offer (up to 8 stacks):")) .. "]"
	out[#out + 1] = string.format("list[%s;goods;0.5,2.6;8,1;]", list)
	if state.kind == "sell" then
		out[#out + 1] = "label[0.5,4.1;" .. esc(S("Items you ask for as well (optional, you keep what you drop here):")) .. "]"
		out[#out + 1] = string.format("list[%s;price;0.5,4.3;8,1;]", list)
		out[#out + 1] = "label[10.7,2.4;" .. esc(S("Price in money")) .. "]"
		out[#out + 1] = input_field(10.7, 2.6, 3.8, 0.7, "price", state.price_text or "")
	else
		out[#out + 1] = "label[0.5,4.1;" .. esc(S("Bids are paid in money only. The buy-out price is 5 times the start if left empty.")) .. "]"
		out[#out + 1] = "label[10.7,2.4;" .. esc(S("Starting bid")) .. "]"
		out[#out + 1] = input_field(10.7, 2.6, 3.8, 0.7, "start", state.start_text or "")
		out[#out + 1] = "label[10.7,3.6;" .. esc(S("Buy-out price")) .. "]"
		out[#out + 1] = input_field(10.7, 3.8, 3.8, 0.7, "buyout", state.buyout_text or "")
	end
	local y = state.kind == "sell" and 3.6 or 4.8
	local options, selected = {}, 1
	for i, hours in ipairs(A.durations()) do
		options[i] = hours .. " h"
		if hours == (state.hours or A.default_hours()) then selected = i end
	end
	out[#out + 1] = "label[10.7," .. y .. ";" .. esc(S("Duration")) .. "]"
	out[#out + 1] = string.format("dropdown[10.7,%g;3.8,0.7;hours;%s;%d;]", y + 0.2, table.concat(options, ","), selected)
	out[#out + 1] = string.format("button[10.7,%g;3.8,0.9;publish;%s]", y + 1.3, esc(S("PUBLISH")))
	if state.kind == "sell" then
		out[#out + 1] = string.format("button[10.7,%g;3.8,0.8;clear_price;%s]", y + 2.4, esc(S("Clear price items")))
	end
	out[#out + 1] = "label[0.5,6.0;" .. esc(S("Your inventory:")) .. "]"
	out[#out + 1] = "list[current_player;main;0.5,6.3;8,4;]"
	out[#out + 1] = "listring[" .. list .. ";goods]listring[current_player;main]"
	out[#out + 1] = message_line(state, 11.5)
	return table.concat(out)
end

function ui.formspec(name, state)
	if state.screen == "create" then return create_screen(name, state) end
	if state.screen == "offer" then return offer_screen(name, state) end
	if state.screen == "mine" then return mine_screen(name, state) end
	if state.screen == "claims" then return claims_screen(name, state) end
	return browse_screen(name, state)
end

---------------------------------------------------------------- state and input

function ui.state(name)
	return states[name]
end

function ui.show(name)
	local state = states[name]
	if state then ui.send(name, ui.formspec(name, state)) end
end

local function new_state(screen)
	return { screen = screen, filter = "all", query = "", page = 1 }
end

-- Open the auction house.
function ui.open(name, screen)
	release(name)
	states[name] = new_state(screen or "browse")
	ui.show(name)
end

-- Open the create screen. `stacks` are items the caller already took from the
-- player; they are placed in the goods slots (or returned if they do not fit).
function ui.open_create(name, kind, stacks)
	release(name)
	local state = new_state("create")
	state.kind, state.hours = kind, A.default_hours()
	states[name] = state

	local inv = core.create_detached_inventory(inventory_name(name), callbacks_for(name), name)
	inv:set_size("goods", A.MAX_STACKS)
	inv:set_size("price", A.MAX_STACKS)
	detached[name] = inv
	local rest = {}
	for _, stack in ipairs(stacks or {}) do
		local leftover = inv:add_item("goods", stack)
		if not leftover:is_empty() then rest[#rest + 1] = leftover end
	end
	A.deliver_items(name, rest)
	ui.show(name)
end

-- The goods and price slots of a player's create screen (for tests).
function ui.create_inventory(name)
	return detached[name]
end

ui.callbacks_for = callbacks_for

local function go(name, state, screen)
	if state.screen == "create" then release(name) end
	state.screen, state.page, state.message = screen, 1, nil
end

local function parse_hours(text)
	local hours = tonumber(tostring(text or ""):match("^(%d+)"))
	for _, allowed in ipairs(A.durations()) do
		if hours == allowed then return hours end
	end
	return nil
end

local function publish(name, state)
	local inv = detached[name]
	if not inv then return say(state, false, reason("unavailable")) end
	local spec = { kind = state.kind, goods = inv:get_list("goods"), hours = state.hours }

	if state.kind == "sell" then
		local text = (state.price_text or ""):gsub("%s", "")
		spec.money = 0
		if text ~= "" then
			spec.money = api.parse(text)
			if not spec.money then return say(state, false, reason("invalid_price")) end
		end
		spec.price_items = inv:get_list("price")
	else
		spec.start = api.parse(state.start_text)
		if not spec.start then return say(state, false, reason("invalid_price")) end
		if (state.buyout_text or ""):find("%S") then
			spec.buyout = api.parse(state.buyout_text)
			if not spec.buyout then return say(state, false, reason("invalid_price")) end
		end
	end

	local ok, result = A.create(name, spec)
	if not ok then return say(state, false, reason(result)) end

	-- the offer holds the goods now
	inv:set_list("goods", {})
	release(name)
	state.screen, state.offer_id = "offer", result.id
	say(state, true, S("Your offer #@1 is up.", result.id))
end

-- Run a buy, bid, buy-out or take-down on the offer in view.
local function act(name, state, action, fields)
	local offer = find_offer(state)
	if not offer then return say(state, false, reason("not_found")) end
	local ok, result
	if action == "buy" then
		ok, result = A.buy(name, offer.id)
		if ok then say(state, true, S("You bought offer #@1.", offer.id)) end
	elseif action == "buyout" then
		ok, result = A.buyout(name, offer.id)
		if ok then say(state, true, S("You bought out offer #@1 for @2.", offer.id, api.format_symbol(result.cost))) end
	elseif action == "bid" then
		local amount = api.parse(fields.bid_amount)
		if not amount then return say(state, false, reason("invalid_amount")) end
		ok, result = A.bid(name, offer.id, amount)
		if ok then
			if result.amount then
				say(state, true, S("You bid @1.", api.format_symbol(result.amount)))
			else
				say(state, true, S("You bought out offer #@1 for @2.", offer.id, api.format_symbol(result.cost)))
			end
		end
	else
		ok, result = A.revoke(name, offer.id)
		if ok then
			state.screen, state.page = "mine", 1
			say(state, true, S("Offer #@1 was taken down.", offer.id))
		end
	end
	if not ok then say(state, false, reason(result)) end
	state.bid_amount = nil
end

local TAB_SCREEN = { tab_browse = "browse", tab_mine = "mine", tab_claims = "claims" }

-- Apply one batch of form fields to a player's auction state.
function ui.handle(name, state, fields)
	if state.screen == "create" then
		if fields.price then state.price_text = fields.price:sub(1, 20) end
		if fields.start then state.start_text = fields.start:sub(1, 20) end
		if fields.buyout then state.buyout_text = fields.buyout:sub(1, 20) end
		if fields.hours then state.hours = parse_hours(fields.hours) or state.hours end
	elseif fields.query then
		state.query = fields.query:sub(1, 60)
	end
	if state.screen == "offer" and fields.bid_amount then state.bid_amount = api.parse(fields.bid_amount) end

	local handled = false
	for key, screen in pairs(TAB_SCREEN) do
		if fields[key] then go(name, state, screen) handled = true end
	end
	if not handled then
		if fields.new_sell or fields.new_bid then
			ui.open_create(name, fields.new_sell and "sell" or "bid")
			return
		elseif fields.to_shop then
			if state.screen == "create" then release(name) end
			states[name] = nil
			mine_shop_gui.shop.ui.open(name)
			return
		elseif state.screen == "create" then
			if fields.publish then
				publish(name, state)
			elseif fields.clear_price and detached[name] then
				detached[name]:set_list("price", {})
			end
		elseif fields.prev then
			state.page = (state.page or 1) - 1
		elseif fields.next then
			state.page = (state.page or 1) + 1
		elseif fields.claim and state.screen == "claims" then
			local items, money, left = A.claim(name)
			say(state, true, S("Received @1 items and @2.", items, api.format_symbol(money))
				.. (left > 0 and " " .. S("@1 still waiting.", left) or ""))
		elseif state.screen == "browse" and (fields.filter_all or fields.filter_sell or fields.filter_bid
				or fields.do_search or fields.key_enter_field == "query") then
			if fields.filter_all then state.filter = "all"
			elseif fields.filter_sell then state.filter = "sell"
			elseif fields.filter_bid then state.filter = "bid" end
			state.page = 1
		elseif state.screen == "offer" then
			for _, action in ipairs({ "buy", "bid", "buyout", "revoke" }) do
				if fields[action] then act(name, state, action, fields) end
			end
		elseif state.screen == "browse" or state.screen == "mine" then
			for key in pairs(fields) do
				local index = tonumber(key:match("^view_(%d+)$") or "")
				local id = index and state.page_offers and state.page_offers[index]
				if id then
					state.back, state.screen, state.offer_id, state.message = state.screen, "offer", id, nil
					break
				end
			end
		end
	end
	ui.show(name)
end

function ui.on_fields(player, formname, fields)
	if formname ~= FORM then return end
	local name = player:get_player_name()
	if fields.quit then
		release(name)
		states[name] = nil
		return true
	end
	local state = states[name]
	if state then ui.handle(name, state, fields) end
	return true
end

core.register_on_player_receive_fields(ui.on_fields)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	release(name)
	states[name] = nil
end)

A.ui = ui
