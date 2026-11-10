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

function api.format(amount)
	if not api.active then return tostring(amount) end
	return api.active.format(amount)
end
