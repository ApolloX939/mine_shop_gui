-- The trade window and the /trade command's messages.
--
-- Left: what you put on the table and your own inventory, to drag from.
-- Right: what the other player put on the table, and the buttons. Both
-- players see the same trade; it is redrawn for both whenever anything changes.
-- Closing the window cancels the trade and everyone gets their items back.
--
-- Everything a player clicks arrives as form fields, which the server checks
-- again: the money is parsed here and validated by the trade itself, and a
-- player with no trade open changes nothing.

local api = mine_shop_gui.currency
local T = mine_shop_gui.trade
local widgets = mine_shop_gui.shop.ui.widgets
local money_widget, input_field = widgets.money_widget, widgets.input_field

local S = core.get_translator(core.get_current_modname())
local esc = core.formspec_escape

local FORM = "mine_shop_gui:trade"

local COLS, PITCH, SLOT = 8, 0.95, 0.85
local LIST_WIDTH = COLS * PITCH - (PITCH - SLOT)

local ui = {}
local messages = {} -- player name -> the last problem, shown in the window
ui.typed = {}      -- player name -> money text that was typed but not accepted

-- Replaced by tests so a window can be inspected without a connected player.
ui.send = function(name, formspec)
	core.show_formspec(name, FORM, formspec)
end

ui.close = function(name)
	core.close_formspec(name, FORM)
end

local REASONS = {
	unavailable = S("The trade cannot do that right now."),
	invalid_amount = S("That is not an amount the currency can pay."),
	insufficient_funds = S("You do not have that much."),
	locked = S("Unlock your offer to change it."),
	no_trade = S("You are not trading with anybody."),
}

ui.REASONS = REASONS

local function rows(count)
	return math.max(1, math.ceil(count / COLS))
end

local function list_height(count)
	return rows(count) * PITCH - (PITCH - SLOT)
end

---------------------------------------------------------------- the window

function ui.formspec(name)
	local trade = T.get(name)
	if not trade then return nil end
	local partner = T.partner(trade, name)
	local player = core.get_player_by_name(name)
	local other = core.get_player_by_name(partner)
	if not player or not other then return nil end
	local inv = player:get_inventory()

	local mine_size, their_size = inv:get_size(T.LIST), other:get_inventory():get_size(T.LIST)
	local locked, their_locked = trade.locked[name], trade.locked[partner]
	local list = T.LIST

	local left, right = 0.5, 0.5 + LIST_WIDTH + 0.6
	local width = right + LIST_WIDTH + 0.5
	local offer_rows = math.max(mine_size, their_size)
	local offer_y = 1.3
	local money_y = offer_y + list_height(offer_rows) + 0.25
	local inv_label_y = money_y + 1.0
	local inv_y = inv_label_y + 0.3
	local height = inv_y + list_height(inv:get_size("main")) + 0.5

	local out = {
		"formspec_version[6]size[", string.format("%g,%g", width, height), "]",
		"style_type[list;size=", SLOT, ";spacing=", PITCH - SLOT, "]",
		"label[", left, ",0.6;", esc(S("Trade with @1", partner)), "]",
	}
	local function add(...) for _, piece in ipairs({ ... }) do out[#out + 1] = piece end end

	if api.get() then
		add("label[", right, ",0.6;", esc(S("Balance:")), "]", money_widget(right + 1.7, 0.35, api.balance(name)))
	end

	-- the two offers
	add("label[", left, ",1.0;", esc(S("You offer")), "]")
	add(string.format("list[current_player;%s;%g,%g;%d,%d;]", list, left, offer_y, COLS, rows(mine_size)))
	add("label[", right, ",1.0;", esc(S("@1 offers", partner)), "]")
	add(string.format("list[detached:%s;offer;%g,%g;%d,%d;]", esc(T.mirror_name(partner)), right, offer_y,
		COLS, rows(their_size)))

	-- the money
	if api.get() then
		add("label[", left, ",", money_y + 0.4, ";", esc(S("Your money:")), "]")
		if locked then
			add(money_widget(2.7, money_y, T.money(name)))
		else
			local text = ui.typed[name]
			if text == nil then text = T.money(name) > 0 and api.number(T.money(name)) or "" end
			add(input_field(2.7, money_y, 3.1, 0.7, "money", text))
			add("button[5.9,", money_y, ";1.6,0.7;set_money;", esc(S("Set")), "]")
		end
		add("label[", right, ",", money_y + 0.4, ";", esc(S("Their money:")), "]")
		add(money_widget(right + 2.2, money_y, T.money(partner)))
	end

	-- your inventory, to drag from
	add("label[", left, ",", inv_label_y, ";", esc(S("Your inventory")), "]")
	add(string.format("list[current_player;main;%g,%g;%d,%d;]", left, inv_y, COLS, rows(inv:get_size("main"))))
	add("listring[current_player;main]listring[current_player;", list, "]")

	-- agreement
	local status
	if locked and their_locked then
		status = S("Both locked.")
	elseif locked then
		status = S("You locked your offer. Waiting for @1.", partner)
	elseif their_locked then
		status = S("@1 locked their offer.", partner)
	else
		status = S("Nobody has locked yet.")
	end
	add("label[", right, ",", inv_label_y, ";", esc(status), "]")
	if locked then
		add("button[", right, ",", inv_y, ";3.6,0.8;unlock;", esc(S("Unlock offer")), "]")
	else
		add("button[", right, ",", inv_y, ";3.6,0.8;lock;", esc(S("Lock offer")), "]")
	end
	add("button_exit[", right + 3.9, ",", inv_y, ";3.6,0.8;cancel;", esc(S("Cancel trade")), "]")
	if messages[name] then
		add("textarea[", right, ",", inv_y + 1.1, ";", LIST_WIDTH, ",1.4;;;", esc(messages[name]), "]")
	end
	return table.concat(out)
end

function ui.show(name)
	local formspec = ui.formspec(name)
	if formspec then ui.send(name, formspec) end
end

local function show_both(trade)
	for _, name in ipairs(trade.players) do ui.show(name) end
end

---------------------------------------------------------------- reading what players do

local function reason_text(code, who, name)
	if code == "no_room" then
		if who == name then return S("There is no room in your inventory for what you would get.") end
		return S("@1 has no room for what they would get.", who or "?")
	elseif code == "insufficient_funds" then
		if who == name then return S("You no longer have the money you offered.") end
		return S("@1 no longer has the money they offered.", who or "?")
	end
	return REASONS[code] or REASONS.unavailable
end

-- Apply one batch of form fields to a player's trade.
function ui.handle(name, fields)
	local trade = T.get(name)
	if not trade then return end

	if fields.cancel or fields.quit then
		T.cancel(name, "cancelled")
		return
	end
	messages[name] = nil

	-- money: take what was typed, unless the side is locked
	if fields.money ~= nil and api.get() and not trade.locked[name] then
		ui.typed[name] = fields.money:sub(1, 20)
		local text = fields.money:gsub("%s", "")
		local amount = text == "" and 0 or api.parse(text)
		if not amount then
			messages[name] = REASONS.invalid_amount
		else
			local ok, why = T.set_money(name, amount)
			if not ok then messages[name] = reason_text(why, name, name) end
		end
		if not messages[name] then ui.typed[name] = nil end
	end

	if fields.lock then
		local ok, why, who = T.lock(name)
		if not ok then
			for _, player in ipairs(trade.players) do messages[player] = reason_text(why, who, player) end
		end
	elseif fields.unlock then
		T.unlock(name)
	end
	if T.get(name) then show_both(T.get(name)) end
end

function ui.on_fields(player, formname, fields)
	if formname ~= FORM then return end
	ui.handle(player:get_player_name(), fields)
	return true
end

core.register_on_player_receive_fields(ui.on_fields)

---------------------------------------------------------------- following the trade

T.on(function(event, trade, info)
	if event == "started" then
		for _, name in ipairs(trade.players) do
			messages[name] = nil
			ui.typed[name] = nil
		end
		show_both(trade)
	elseif event == "changed" or event == "locked" then
		show_both(trade)
	elseif event == "failed" then
		for _, name in ipairs(trade.players) do
			messages[name] = reason_text(info.reason, info.who, name)
		end
		show_both(trade)
	elseif event == "completed" then
		for _, name in ipairs(trade.players) do
			messages[name] = nil
			ui.close(name)
			T.notify(name, S("Trade with @1 complete.", T.partner(trade, name)))
		end
	elseif event == "cancelled" then
		for _, name in ipairs(trade.players) do
			messages[name] = nil
			ui.close(name)
			if name == info.by then
				T.notify(name, S("You cancelled the trade. Your items are back."))
			elseif info.reason == "left" or info.reason == "died" then
				T.notify(name, S("@1 left the trade. Your items are back.", info.by))
			else
				T.notify(name, S("@1 cancelled the trade. Your items are back.", info.by or "?"))
			end
		end
	end
end)

T.ui = ui
