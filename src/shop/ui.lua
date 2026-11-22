-- The shop window: categories, an item grid, and a trade panel.
--
-- Everything the player clicks arrives as form fields. Item and category
-- buttons carry only a position on the current page; the server looks the real
-- item up in its own state, so a forged field cannot name an arbitrary item.

local api = mine_shop_gui.currency
local pricing = mine_shop_gui.pricing
local trade = mine_shop_gui.shop.trade
local catalog = mine_shop_gui.shop.catalog

local S = core.get_translator(core.get_current_modname())
local esc = core.formspec_escape

local FORM = "mine_shop_gui:shop"
local CATEGORY_COLUMNS, CATEGORY_ROWS = 3, 5
local ITEM_COLUMNS, ITEM_ROWS = 6, 3
local PER_PAGE = ITEM_COLUMNS * ITEM_ROWS

local ui = {}
local states = {}

-- Replaced by tests so a window can be inspected without a connected player.
ui.send = function(name, formspec)
	core.show_formspec(name, FORM, formspec)
end

local REASONS = {
	invalid_amount = S("That amount is not allowed."),
	not_for_sale = S("The shop does not trade this item."),
	not_enough = S("You do not have that many to sell."),
	too_cheap = S("That is worth less than the smallest coin. Sell more at once."),
	insufficient_funds = S("You cannot afford that."),
	no_room = S("There is no room in your inventory."),
	unavailable = S("The shop cannot do that right now."),
}

ui.REASONS = REASONS

-- An amount as text, with the currency mark (tooltips and messages).
local function money(amount)
	return api.format_symbol(amount)
end

-- An amount drawn as the currency's picture followed by the number, on a row
-- 0.5 high whose top edge is at y. Without a picture the text form is used.
local ICON_SIZE = 0.5
local function money_widget(x, y, amount)
	if amount == nil then
		return string.format("label[%g,%g;-]", x, y + ICON_SIZE / 2)
	end
	local icon = api.icon()
	if not icon then
		return string.format("label[%g,%g;%s]", x, y + ICON_SIZE / 2, esc(money(amount)))
	end
	return string.format("item_image[%g,%g;%g,%g;%s]label[%g,%g;%s]", x, y, ICON_SIZE, ICON_SIZE, esc(icon),
		x + ICON_SIZE + 0.1, y + ICON_SIZE / 2, esc(api.number(amount)))
end

-- Cut text to `limit` characters (not bytes, so accents survive), ending in "..".
local function shorten(text, limit)
	local characters = {}
	for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		characters[#characters + 1] = character
	end
	if #characters <= limit then return text end
	return table.concat(characters, "", 1, limit - 2) .. ".."
end

-- A text field on a dark box: the default field is bright green in some themes.
local function input_field(x, y, width, height, name, value)
	return table.concat({
		string.format("box[%g,%g;%g,%g;#1c1c1c]", x, y, width, height),
		string.format("style[%s;border=false;textcolor=#ffffff]", name),
		string.format("field[%g,%g;%g,%g;%s;;%s]", x, y, width, height, name, esc(value)),
	})
end

---------------------------------------------------------------- pieces

local function header(name, title)
	local balance = api.balance(name)
	return table.concat({
		"formspec_version[6]size[15,11]",
		"label[0.5,0.7;", esc(title), "]",
		"label[9.4,0.7;", esc(S("Balance:")), "]",
		money_widget(10.9, 0.45, balance),
	})
end

local function paging(page, pages)
	if pages <= 1 then return "" end
	return table.concat({
		"button[4.6,10.1;2,0.7;prev;<]",
		"label[7.0,10.45;", esc(S("Page @1 / @2", page, pages)), "]",
		"button[8.8,10.1;2,0.7;next;>]",
	})
end

local function search_bar(state, x, width)
	return table.concat({
		input_field(x, 1.2, width, 0.8, "query", state.query),
		"field_close_on_enter[query;false]",
		string.format("button[%g,1.2;2.2,0.8;do_search;%s]", x + width + 0.2, esc(S("Search"))),
		string.format("button[13.1,1.2;1.4,0.8;show_sell;%s]", esc(S("Sell"))),
	})
end

-- What a hover over an item shows.
local function tooltip_for(record)
	local lines = { record.title, record.name }
	local buy = trade.quote(record.name, 1, "buy")
	lines[#lines + 1] = buy and S("Buy: @1 each", money(buy)) or S("Not sold by the shop")
	local sell = trade.quote(record.name, 1, "sell")
	if sell then
		lines[#lines + 1] = S("Sell: @1 each", money(sell))
	else
		local entry = pricing.get(record.name)
		local from = entry and not entry.no_sell and trade.min_sell_amount(record.name)
		lines[#lines + 1] = from and S("Sell: only @1 or more at once", from) or S("The shop does not buy this")
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------- screens

local function categories_screen(name, state)
	local slice, page, pages = catalog.page(catalog.categories(), state.page, CATEGORY_COLUMNS * CATEGORY_ROWS)
	state.page, state.page_categories = page, {}

	local out = { header(name, S("Shop")), search_bar(state, 0.5, 10) }
	for i, category in ipairs(slice) do
		state.page_categories[i] = category.id
		local column, row = (i - 1) % CATEGORY_COLUMNS, math.floor((i - 1) / CATEGORY_COLUMNS)
		local x, y = 0.5 + column * 4.7, 2.3 + row * 1.5
		-- two buttons that both pick the category: the picture, and the title beside it
		out[#out + 1] = string.format("item_image_button[%g,%g;1.3,1.3;%s;cat_%d;]", x, y, esc(category.icon), i)
		out[#out + 1] = string.format("button[%g,%g;3.2,1.3;cat_%d_t;%s]", x + 1.3, y, i,
			esc(category.title .. " (" .. category.count .. ")"))
	end
	out[#out + 1] = paging(page, pages)
	return table.concat(out)
end

local function items_screen(name, state)
	local list = catalog.items(state.category, state.query)
	local slice, page, pages = catalog.page(list, state.page, PER_PAGE)
	state.page, state.page_items = page, {}
	local category = catalog.category(state.category)

	local out = {
		header(name, category and category.title or S("Shop")),
		string.format("button[0.5,1.2;2,0.8;back;%s]", esc(S("< Back"))),
		search_bar(state, 2.7, 7.5),
	}
	if #list == 0 then
		out[#out + 1] = "label[0.5,3;" .. esc(S("Nothing found.")) .. "]"
	end
	for i, record in ipairs(slice) do
		state.page_items[i] = record
		local column, row = (i - 1) % ITEM_COLUMNS, math.floor((i - 1) / ITEM_COLUMNS)
		local x, y = 0.5 + column * 2.3, 2.3 + row * 2.5
		local buy = trade.quote(record.name, 1, "buy")
		out[#out + 1] = string.format("item_image_button[%g,%g;1.5,1.5;%s;item_%d;]", x + 0.4, y, esc(record.name), i)
		out[#out + 1] = string.format("tooltip[item_%d;%s]", i, esc(tooltip_for(record)))
		out[#out + 1] = string.format("label[%g,%g;%s]", x + 0.1, y + 1.85, esc(shorten(record.title, 16)))
		out[#out + 1] = money_widget(x + 0.1, y + 2.05, buy)
	end
	out[#out + 1] = paging(page, pages)
	return table.concat(out)
end

-- Everything in the player's inventory the shop buys, with what it would pay.
local function sell_screen(name, state)
	local list = trade.sellable_items(name)
	local slice, page, pages = catalog.page(list, state.page, PER_PAGE)
	state.page, state.page_items = page, {}

	local out = {
		header(name, S("Sell")),
		string.format("button[0.5,1.2;2,0.8;back;%s]", esc(S("< Back"))),
	}
	if #list == 0 then
		out[#out + 1] = "label[0.5,3;" .. esc(S("You have nothing the shop will buy.")) .. "]"
	end
	for i, entry in ipairs(slice) do
		local title = catalog.title(entry.name)
		state.page_items[i] = { name = entry.name, title = title }
		local column, row = (i - 1) % ITEM_COLUMNS, math.floor((i - 1) / ITEM_COLUMNS)
		local x, y = 0.5 + column * 2.3, 2.3 + row * 2.5
		out[#out + 1] = string.format("item_image_button[%g,%g;1.5,1.5;%s;item_%d;]", x + 0.4, y, esc(entry.name), i)
		out[#out + 1] = string.format("tooltip[item_%d;%s]", i,
			esc(table.concat({ title, entry.name, S("You hold: @1", entry.count) }, "\n")))
		out[#out + 1] = string.format("label[%g,%g;%s]", x + 0.1, y + 1.85,
			esc(shorten(title, 12) .. " x" .. entry.count))
		out[#out + 1] = money_widget(x + 0.1, y + 2.05, entry.payout)
	end
	out[#out + 1] = paging(page, pages)
	return table.concat(out)
end

local function trade_screen(name, state)
	local item = state.item
	local entry = pricing.get(item)
	local amount = state.amount
	local held = trade.sellable_count(name, item)

	local out = { header(name, state.item_title), string.format("button[0.5,1.2;2,0.8;back;%s]", esc(S("< Back"))) }
	out[#out + 1] = string.format("item_image[0.8,2.2;2.5,2.5;%s]", esc(item))

	-- prices for one
	local buy_one = trade.quote(item, 1, "buy")
	local sell_one = trade.quote(item, 1, "sell")
	if buy_one then
		out[#out + 1] = "label[4,2.6;" .. esc(S("Buy (each):")) .. "]" .. money_widget(6.3, 2.35, buy_one)
	else
		out[#out + 1] = "label[4,2.6;" .. esc(S("Not sold by the shop")) .. "]"
	end
	if sell_one then
		out[#out + 1] = "label[4,3.3;" .. esc(S("Sell (each):")) .. "]" .. money_widget(6.3, 3.05, sell_one)
	else
		local from = entry and not entry.no_sell and trade.min_sell_amount(item)
		out[#out + 1] = "label[4,3.3;" .. esc(from and S("Sell: only @1 or more at once", from)
			or S("The shop does not buy this")) .. "]"
	end
	out[#out + 1] = "label[4,4.0;" .. esc(S("You hold: @1", held)) .. "]"

	-- amount
	local steps = { { "m64", "-64", 1.0 }, { "m10", "-10", 2.5 }, { "m1", "-1", 4.0 },
		{ "p1", "+1", 8.6 }, { "p10", "+10", 10.1 }, { "p64", "+64", 11.6 } }
	for _, step in ipairs(steps) do
		out[#out + 1] = string.format("button[%g,5.2;1.4,0.9;%s;%s]", step[3], step[1], step[2])
	end
	out[#out + 1] = input_field(5.6, 5.2, 2.8, 0.9, "amount", tostring(amount))
	out[#out + 1] = "field_close_on_enter[amount;false]"

	-- totals and actions
	local buy_total = trade.quote(item, amount, "buy")
	local sell_total = trade.quote(item, amount, "sell")
	if buy_total then
		out[#out + 1] = "label[1,6.8;" .. esc(S("You pay:")) .. "]" .. money_widget(2.4, 6.55, buy_total)
		out[#out + 1] = string.format("button[1,7.5;3.6,1;buy;%s]", esc(S("BUY")))
	end
	if sell_total then
		out[#out + 1] = "label[5.4,6.8;" .. esc(S("You get:")) .. "]" .. money_widget(6.8, 6.55, sell_total)
		out[#out + 1] = string.format("button[5.4,7.5;3.6,1;sell;%s]", esc(S("SELL")))
	end
	local all_total = held > 0 and trade.quote(item, held, "sell")
	if all_total then
		out[#out + 1] = string.format("button[9.8,7.5;4.2,1;sellall;%s]", esc(S("SELL ALL (@1)", held)))
		out[#out + 1] = "label[9.8,6.8;" .. esc(S("All:")) .. "]" .. money_widget(10.6, 6.55, all_total)
	end

	if state.message then
		local color = state.message.ok and "#9cff9c" or "#ff9c9c"
		out[#out + 1] = "label[1,9.3;" .. esc(core.colorize(color, state.message.text)) .. "]"
	end
	return table.concat(out)
end

function ui.formspec(name, state)
	if state.screen == "trade" then return trade_screen(name, state) end
	if state.screen == "sell" then return sell_screen(name, state) end
	if state.screen == "items" then return items_screen(name, state) end
	return categories_screen(name, state)
end

---------------------------------------------------------------- state and input

function ui.state(name)
	return states[name]
end

function ui.show(name)
	local state = states[name]
	if state then ui.send(name, ui.formspec(name, state)) end
end

-- Open the shop. With search words it goes straight to matching items.
function ui.open(name, query)
	query = query and query ~= "" and query:sub(1, 60) or nil
	states[name] = {
		screen = query and "items" or "categories",
		category = "all", query = query or "", page = 1, amount = 1,
	}
	ui.show(name)
end

local function parse_amount(text, fallback)
	local number = tonumber(text)
	if not number then return fallback end
	return math.max(1, math.min(math.floor(number), trade.max_amount()))
end

local function say(state, ok, text)
	state.message = { ok = ok, text = text }
end

local function do_trade(name, state, action)
	local title = state.item_title
	local ok, result
	if action == "buy" then
		ok, result = trade.buy(name, state.item, state.amount)
		if ok then say(state, true, S("Bought @1 x @2 for @3.", result.amount, title, money(result.cost))) end
	elseif action == "sell" then
		ok, result = trade.sell(name, state.item, state.amount)
		if ok then say(state, true, S("Sold @1 x @2 for @3.", result.amount, title, money(result.payout))) end
	else
		ok, result = trade.sell_all(name, state.item)
		if ok then say(state, true, S("Sold @1 x @2 for @3.", result.amount, title, money(result.payout))) end
	end
	if not ok then say(state, false, REASONS[result] or REASONS.unavailable) end
end

local AMOUNT_STEP = { m64 = -64, m10 = -10, m1 = -1, p1 = 1, p10 = 10, p64 = 64 }

-- Apply one batch of form fields to a player's shop state.
function ui.handle(name, state, fields)
	if state.screen == "trade" and fields.amount then
		state.amount = parse_amount(fields.amount, state.amount)
	end

	if fields.do_search or fields.key_enter_field == "query" then
		if fields.query then
			state.query = fields.query:sub(1, 60)
			state.page = 1
			if state.screen == "categories" then
				state.screen, state.category = "items", "all"
			end
		end
	elseif fields.back then
		if state.screen == "trade" then
			state.screen = state.trade_from or "items"
		elseif state.screen == "sell" then
			state.screen, state.page = state.sell_from or "categories", 1
		elseif state.screen == "items" then
			state.screen, state.query, state.page = "categories", "", 1
		end
	elseif fields.show_sell then
		if state.screen ~= "trade" and state.screen ~= "sell" then
			state.sell_from, state.screen, state.page = state.screen, "sell", 1
		end
	elseif fields.prev then
		state.page = (state.page or 1) - 1
	elseif fields.next then
		state.page = (state.page or 1) + 1
	elseif state.screen == "trade" then
		for key, step in pairs(AMOUNT_STEP) do
			if fields[key] then state.amount = parse_amount(state.amount + step, state.amount) end
		end
		for _, action in ipairs({ "buy", "sell", "sellall" }) do
			if fields[action] then do_trade(name, state, action) end
		end
	else
		for key in pairs(fields) do
			local index = tonumber(key:match("^cat_(%d+)$") or key:match("^cat_(%d+)_t$") or "")
			local id = index and state.page_categories and state.page_categories[index]
			if id then
				state.screen, state.category, state.page = "items", id, 1
				break
			end
			index = tonumber(key:match("^item_(%d+)$") or "")
			local record = index and state.page_items and state.page_items[index]
			if record then
				state.trade_from = state.screen
				state.screen, state.item, state.item_title = "trade", record.name, record.title
				state.amount, state.message = 1, nil
				break
			end
		end
	end
	ui.show(name)
end

function ui.on_fields(player, formname, fields)
	if formname ~= FORM then return end
	local name = player:get_player_name()
	if fields.quit then
		states[name] = nil
		return true
	end
	local state = states[name]
	if state then ui.handle(name, state, fields) end
	return true
end

core.register_on_player_receive_fields(ui.on_fields)

core.register_on_leaveplayer(function(player)
	states[player:get_player_name()] = nil
end)

core.register_chatcommand("shop", {
	params = S("[search words]"),
	description = S("Open the shop"),
	func = function(name, param)
		if not pricing.generated then
			return false, S("The shop is not ready yet. Try again in a moment.")
		end
		if not api.get() then
			return false, S("The shop has no currency to trade with.")
		end
		ui.open(name, param)
		return true
	end,
})

mine_shop_gui.shop.ui = ui
