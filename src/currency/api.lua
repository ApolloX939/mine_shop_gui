-- Currency API.
--
-- Every supported currency is an adapter registered here. Shop code only ever
-- talks to mine_shop_gui.currency, never to a currency mod directly.
--
-- Amounts are whole numbers in the active currency's smallest unit
-- (cents for `currency`, credits for `credits`, and so on).
--
-- Adapter interface:
--   name                    unique id, also the value of the `mine_shop_gui_currency` setting
--   available()             true if the adapter can be used on this server
--   round(amount)           round an amount to something the adapter can pay exactly
--   balance(player)         amount the player has, or nil if unavailable (e.g. offline)
--   withdraw(player, amt)   take amt from the player; returns true, or false + reason
--   deposit(player, amt)    give amt to the player; returns true, or false + reason
--   format(amount)          human readable string
--   snapshot(player)        remember everything a payment could change
--   restore(player, snap)   put it back (used to undo a payment when the goods
--                           cannot be delivered)
--   number(amount)          the amount as plain text, no currency name (default: format)
--   format_symbol(amount)   the amount with a short currency mark, for text ("$1.25")
--   icon()                  an item that stands for the currency, or nil
--   unit()                  smallest amount the adapter can pay (a whole number)
--   default_scale           currency amount per price unit; overridden by the
--                           `mine_shop_gui_scale_<name>` setting
--
-- Failure reasons: "invalid_amount", "insufficient_funds", "no_room", "unavailable".
-- withdraw and deposit are atomic: on failure nothing has changed.

local api = {
	adapters = {},
	order = {},
	active = nil,
}

mine_shop_gui.currency = api

function api.register(adapter)
	assert(type(adapter.name) == "string", "currency adapter needs a name")
	api.adapters[adapter.name] = adapter
	api.order[#api.order + 1] = adapter.name
end

local function log(level, msg)
	core.log(level, "[mine_shop_gui] " .. msg)
end

-- Choose the active adapter from the setting. Called once, after all mods load.
function api.resolve()
	api.active = nil
	local wanted = core.settings:get("mine_shop_gui_currency") or "auto"

	local configured_items = (core.settings:get("mine_shop_gui_item_currency") or "") ~= ""

	-- An item currency that has been set up is meant to be used.
	if wanted == "auto" and configured_items and api.adapters.items and api.adapters.items.available() then
		api.active = api.adapters.items
	end

	if wanted ~= "auto" then
		local adapter = api.adapters[wanted]
		if adapter and adapter.available() then
			api.active = adapter
		else
			log("warning", "currency '" .. wanted .. "' is not available, falling back to auto")
		end
	end

	if not api.active then
		for _, name in ipairs(api.order) do
			if api.adapters[name].available() then
				api.active = api.adapters[name]
				break
			end
		end
	end

	if configured_items and api.active and api.active.name ~= "items" then
		log("warning", "mine_shop_gui_item_currency is set but the currency in use is '" .. api.active.name
			.. "'. Set mine_shop_gui_currency to 'items' (or 'auto') to use the item currency.")
	end

	if api.active then
		log("action", "using currency '" .. api.active.name .. "'")
	else
		log("warning", "no supported currency found; the shop cannot take payment")
	end
	return api.active
end

function api.get()
	return api.active
end

-- An amount must be a non-negative whole number.
function api.valid_amount(amount)
	return type(amount) == "number"
		and amount >= 0
		and amount == math.floor(amount)
		and amount < math.huge
end

function api.round(amount)
	if not api.active then return amount end
	return api.active.round(amount)
end

function api.balance(player)
	if not api.active then return nil end
	return api.active.balance(player)
end

function api.withdraw(player, amount)
	if not api.active then return false, "unavailable" end
	return api.active.withdraw(player, amount)
end

function api.deposit(player, amount)
	if not api.active then return false, "unavailable" end
	return api.active.deposit(player, amount)
end

-- Currency amount that one price unit is worth (1 unit = one cobblestone).
function api.scale()
	local adapter = api.active
	if not adapter then return 1 end
	local value = tonumber(core.settings:get("mine_shop_gui_scale_" .. adapter.name))
	if value and value > 0 then return value end
	if adapter.scale then return adapter.scale() end
	return adapter.default_scale or 1
end

-- Is this item the active currency itself? Money is not for sale.
function api.is_money(item)
	local adapter = api.active
	return adapter ~= nil and adapter.is_money ~= nil and adapter.is_money(item) or false
end

local function sell_ratio()
	local value = tonumber(core.settings:get("mine_shop_gui_sell_ratio")) or 0.5
	return math.min(1, math.max(0, value))
end

-- Convert a total in price units (the buy price, already multiplied by the
-- quantity) into an amount of the active currency the player can pay.
--   mode "buy":  never free unless the price is 0; at least the smallest unit.
--   mode "sell": the buy price times the sell ratio; refused ("too_cheap")
--                if that is less than the smallest unit.
function api.price(units, mode)
	local adapter = api.active
	if not adapter then return nil, "unavailable" end
	if mode ~= "buy" and mode ~= "sell" then return nil, "invalid_mode" end
	if type(units) ~= "number" or units ~= units or units < 0 or units == math.huge then
		return nil, "invalid_amount"
	end
	if mode == "buy" and units == 0 then return 0 end

	if mode == "sell" then units = units * sell_ratio() end
	local unit = adapter.unit()
	local amount = adapter.round(units * api.scale())
	if mode == "buy" then return math.max(amount, unit) end
	if amount < unit then return nil, "too_cheap" end
	return amount
end

-- Remember the player's money so a payment can be undone. Returns nil if there
-- is nothing to remember (no currency, or the player is offline).
function api.snapshot(player)
	if not api.active then return nil end
	return api.active.snapshot(player)
end

function api.restore(player, snapshot)
	if api.active and snapshot ~= nil then api.active.restore(player, snapshot) end
end

-- The amount as plain text without a currency name, for drawing next to an icon.
function api.number(amount)
	local adapter = api.active
	if not adapter then return tostring(amount) end
	return (adapter.number or adapter.format)(amount)
end

-- The amount with a short currency mark, for places that only hold text.
function api.format_symbol(amount)
	local adapter = api.active
	if not adapter then return tostring(amount) end
	return (adapter.format_symbol or adapter.format)(amount)
end

-- An item that stands for the active currency (shown next to prices), or nil.
function api.icon()
	local adapter = api.active
	local icon = adapter and adapter.icon and adapter.icon()
	if icon and core.registered_items[icon] then return icon end
	return nil
end

function api.format(amount)
	if not api.active then return tostring(amount) end
	return api.active.format(amount)
end
