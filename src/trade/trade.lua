-- Player to player trading: a request, then a shared window where each side
-- puts items (up to everything in their inventory) and, when a currency is
-- available, an amount of money on the table. Both sides lock their half; when
-- both are locked the exchange happens at once, or not at all. No interface
-- code here; the window and the /trade command call these functions.
--
-- Items on offer stay in the player's own inventory, in an extra list
-- ("mine_shop_gui_trade") that exists only during a trade and is as big as
-- their main list. Because it is part of the player's inventory it is saved with
-- the player, so a crash or a restart cannot lose anything: the list is emptied
-- back into the main list when the player joins again. Money is not set aside;
-- it is checked and taken when the trade completes.
--
-- Any change to either side (an item moved, the money changed) removes both
-- locks, so nobody can swap the goods after the other side agreed.
--
-- Functions that can fail return true plus a result, or false plus a reason:
-- "unavailable", "self", "offline", "busy", "not_allowed", "not_found", "choose",
-- "no_trade", "locked", "invalid_amount", "insufficient_funds", "no_room".

local api = mine_shop_gui.currency
local S = core.get_translator(core.get_current_modname())

local T = {}

T.LIST = "mine_shop_gui_trade"
T.REQUEST_SECONDS = 60

-- Replaced by tests to move time along.
T.now = os.time

-- May this player trade? Replaced by tests, whose players have no privileges.
function T.allowed(name)
	return core.check_player_privs(name, { interact = true, shout = true })
end

local requests = {}  -- player asked -> { player who asked -> time the request runs out }
local outgoing = {}  -- player who asked -> player asked
local trades = {}    -- player name -> trade (both partners point at the same table)

-- Listeners hear about a trade: fn(event, trade, info).
-- Events: "started", "changed" (items or money), "locked", "completed", "failed"
-- (info.reason, info.who), "cancelled" (info.reason).
T.listeners = {}

function T.on(fn)
	T.listeners[#T.listeners + 1] = fn
end

local function emit(event, trade, info)
	for _, fn in ipairs(T.listeners) do
		local ok, err = pcall(fn, event, trade, info or {})
		if not ok then core.log("error", "[mine_shop_gui] trade listener failed: " .. tostring(err)) end
	end
end

---------------------------------------------------------------- helpers

function T.notify(name, text)
	if core.get_player_by_name(name) then
		core.chat_send_player(name, core.colorize("#7fd2ff", "[Trade] ") .. text)
	end
end

local function inventory_of(name)
	local player = core.get_player_by_name(name)
	return player and player:get_inventory()
end

-- The trade a player is in, or nil.
function T.get(name)
	return trades[name]
end

function T.partner(trade, name)
	return trade.players[1] == name and trade.players[2] or trade.players[1]
end

-- What a player has put on the table, as a list of ItemStacks (no empty ones).
function T.offer(name)
	local inv = inventory_of(name)
	local list = {}
	for _, stack in ipairs(inv and inv:get_list(T.LIST) or {}) do
		if not stack:is_empty() then list[#list + 1] = stack end
	end
	return list
end

-- The money a player has put on the table.
function T.money(name)
	local trade = trades[name]
	return trade and trade.money[name] or 0
end

function T.is_locked(name)
	local trade = trades[name]
	return trade ~= nil and trade.locked[name] == true
end

---------------------------------------------------------------- the mirror

-- Each player's offer is shown to the partner through a read-only copy.
function T.mirror_name(name)
	return "mine_shop_gui_trade_" .. name
end

local function create_mirror(name)
	local inv = core.create_detached_inventory(T.mirror_name(name), {
		allow_move = function() return 0 end,
		allow_put = function() return 0 end,
		allow_take = function() return 0 end,
	})
	local own = inventory_of(name)
	local size = own and own:get_size(T.LIST) or 0
	inv:set_size("offer", size)
	return inv
end

-- Copy a player's offer into their mirror.
function T.refresh_mirror(name)
	local inv = core.get_inventory({ type = "detached", name = T.mirror_name(name) })
	local own = inventory_of(name)
	if inv and own then inv:set_list("offer", own:get_list(T.LIST) or {}) end
end

---------------------------------------------------------------- ending a trade

-- Put everything a player left on the table back into their inventory. What
-- does not fit waits in the auction house's delivery queue.
function T.recover(name)
	local inv = inventory_of(name)
	if not inv or inv:get_size(T.LIST) == 0 then return end
	local rest = {}
	for _, stack in ipairs(inv:get_list(T.LIST)) do
		if not stack:is_empty() then
			local left = inv:add_item("main", stack)
			if not left:is_empty() then rest[#rest + 1] = left end
		end
	end
	inv:set_size(T.LIST, 0)
	if #rest > 0 then mine_shop_gui.auction.deliver_items(name, rest) end
end

local function forget_requests(name)
	requests[name] = nil
	local target = outgoing[name]
	if target and requests[target] then requests[target][name] = nil end
	outgoing[name] = nil
	for to, list in pairs(requests) do
		list[name] = nil
		if next(list) == nil then requests[to] = nil end
	end
end

local function finish(trade, event, info)
	for _, name in ipairs(trade.players) do
		trades[name] = nil
		T.recover(name)
		core.remove_detached_inventory(T.mirror_name(name))
	end
	emit(event, trade, info)
end

-- End a trade without an exchange. Everyone gets their items back.
function T.cancel(name, reason)
	local trade = trades[name]
	if not trade then return false, "no_trade" end
	finish(trade, "cancelled", { reason = reason or "cancelled", by = name })
	return true
end

---------------------------------------------------------------- requests

local function valid_requests(name)
	local list, now = {}, T.now()
	for from, expires in pairs(requests[name] or {}) do
		if expires > now and core.get_player_by_name(from) then
			list[#list + 1] = from
		else
			requests[name][from] = nil
		end
	end
	table.sort(list)
	return list
end

-- Who has asked this player to trade and is still waiting.
function T.incoming(name)
	return valid_requests(name)
end

-- Start a trade between two players who are both free.
local function start(a, b)
	for _, name in ipairs({ a, b }) do
		if trades[name] then return false, "busy" end
		if not core.get_player_by_name(name) then return false, "offline" end
		if not T.allowed(name) then return false, "not_allowed" end
	end
	forget_requests(a)
	forget_requests(b)

	local trade = { players = { a, b }, money = { [a] = 0, [b] = 0 }, locked = { [a] = false, [b] = false } }
	for _, name in ipairs(trade.players) do
		T.recover(name) -- anything left over from a crash goes back first
		local inv = inventory_of(name)
		inv:set_size(T.LIST, inv:get_size("main"))
		create_mirror(name)
		trades[name] = trade
	end
	emit("started", trade)
	return true, trade
end

-- Ask someone to trade. If they have asked you, the trade starts. Returns true
-- plus "sent" or "started" (and the trade).
function T.request(from, to)
	if from == to then return false, "self" end
	if not core.get_player_by_name(to) then return false, "offline" end
	if trades[from] or trades[to] then return false, "busy" end
	if not T.allowed(to) then return false, "not_allowed" end

	for _, asker in ipairs(valid_requests(from)) do
		if asker == to then
			local ok, result = start(from, to)
			if not ok then return false, result end
			return true, "started", result
		end
	end

	-- one open request at a time
	local old = outgoing[from]
	if old and requests[old] then requests[old][from] = nil end
	requests[to] = requests[to] or {}
	requests[to][from] = T.now() + T.REQUEST_SECONDS
	outgoing[from] = to
	T.notify(to, S("@1 wants to trade with you. Type /trade accept or /trade decline.", from))
	return true, "sent"
end

-- Accept a request. Without a name, the only one waiting.
function T.accept(name, from)
	local list = valid_requests(name)
	if from then
		if not requests[name] or not requests[name][from] then return false, "not_found" end
	elseif #list == 0 then
		return false, "not_found"
	elseif #list > 1 then
		return false, "choose", list
	else
		from = list[1]
	end
	local ok, result = start(name, from)
	if not ok then return false, result end
	return true, "started", result
end

-- Turn a request down. Without a name, every request waiting.
function T.decline(name, from)
	local list = valid_requests(name)
	if from then
		if not requests[name] or not requests[name][from] then return false, "not_found" end
		list = { from }
	elseif #list == 0 then
		return false, "not_found"
	end
	for _, asker in ipairs(list) do
		requests[name][asker] = nil
		if outgoing[asker] == name then outgoing[asker] = nil end
		T.notify(asker, S("@1 declined your trade request.", name))
	end
	return true, #list
end

-- Take back your own request.
function T.withdraw_request(name)
	local target = outgoing[name]
	if not target then return false, "not_found" end
	if requests[target] then requests[target][name] = nil end
	outgoing[name] = nil
	return true
end

---------------------------------------------------------------- the table

local function unlock_both(trade)
	for _, name in ipairs(trade.players) do trade.locked[name] = false end
end

-- Something on the table changed: nobody has agreed to this yet.
function T.changed(name)
	local trade = trades[name]
	if not trade then return false, "no_trade" end
	unlock_both(trade)
	for _, player in ipairs(trade.players) do T.refresh_mirror(player) end
	emit("changed", trade, { who = name })
	return true
end

-- Put an amount of money on the table (0 takes it back). The player must have
-- it now; it is checked again when the trade completes.
function T.set_money(name, amount)
	local trade = trades[name]
	if not trade then return false, "no_trade" end
	if trade.locked[name] then return false, "locked" end
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount > 0 then
		if not api.get() then return false, "unavailable" end
		if api.round(amount) ~= amount then return false, "invalid_amount" end
		local balance = api.balance(name)
		if not balance or balance < amount then return false, "insufficient_funds" end
	end
	if trade.money[name] == amount then return true end
	trade.money[name] = amount
	return T.changed(name)
end

-- Give up on a failed exchange: the trade stays open, nobody is locked.
local function fail(trade, reason, who)
	unlock_both(trade)
	emit("failed", trade, { reason = reason, who = who })
	return false, reason, who
end

local function restore(trade, before, snapshots)
	local a, b = trade.players[1], trade.players[2]
	api.restore(a, snapshots[a])
	api.restore(b, snapshots[b])
	for i, name in ipairs(trade.players) do
		local inv = inventory_of(name)
		inv:set_list("main", before[i].main)
		inv:set_list(T.LIST, before[i].offer)
	end
end

-- Exchange everything at once. On any problem, nothing at all changes.
local function complete(trade)
	local a, b = trade.players[1], trade.players[2]
	local ia, ib = inventory_of(a), inventory_of(b)
	if not ia or not ib then return fail(trade, "unavailable") end

	local before = {
		{ main = ia:get_list("main"), offer = ia:get_list(T.LIST) },
		{ main = ib:get_list("main"), offer = ib:get_list(T.LIST) },
	}
	local snapshots = { [a] = api.snapshot(a), [b] = api.snapshot(b) }
	local function abort(reason, who)
		restore(trade, before, snapshots)
		return fail(trade, reason, who)
	end

	-- money first: both must be able to pay
	local ma, mb = trade.money[a], trade.money[b]
	if ma > 0 or mb > 0 then
		if not api.get() then return abort("unavailable") end
		for _, entry in ipairs({ { a, ma }, { b, mb } }) do
			if entry[2] > 0 then
				local paid, reason = api.withdraw(entry[1], entry[2])
				if not paid then return abort(reason or "unavailable", entry[1]) end
			end
		end
		if ma > 0 then
			local paid, reason = api.deposit(b, ma)
			if not paid then return abort(reason or "unavailable", b) end
		end
		if mb > 0 then
			local paid, reason = api.deposit(a, mb)
			if not paid then return abort(reason or "unavailable", a) end
		end
	end

	-- then the items, each into the other's main list
	local gifts = { { ia, ib, before[1].offer }, { ib, ia, before[2].offer } }
	for _, gift in ipairs(gifts) do gift[1]:set_list(T.LIST, {}) end
	for i, gift in ipairs(gifts) do
		for _, stack in ipairs(gift[3]) do
			if not stack:is_empty() and not gift[2]:add_item("main", stack):is_empty() then
				return abort("no_room", trade.players[3 - i])
			end
		end
	end

	finish(trade, "completed", { gave = { [a] = before[1].offer, [b] = before[2].offer }, money = { [a] = ma, [b] = mb } })
	return true
end

-- Agree to the trade as it stands. When both sides have, it happens.
-- Returns true plus "locked" or "completed", or false plus a reason.
function T.lock(name)
	local trade = trades[name]
	if not trade then return false, "no_trade" end
	if trade.locked[name] then return true, "locked" end
	trade.locked[name] = true
	if trade.locked[T.partner(trade, name)] then
		local ok, reason, who = complete(trade)
		if not ok then return false, reason, who end
		return true, "completed"
	end
	emit("locked", trade, { who = name })
	return true, "locked"
end

function T.unlock(name)
	local trade = trades[name]
	if not trade then return false, "no_trade" end
	if not trade.locked[name] then return true end
	trade.locked[name] = false
	emit("changed", trade, { who = name })
	return true
end

---------------------------------------------------------------- inventory hooks

local function touches_offer(info)
	return info.from_list == T.LIST or info.to_list == T.LIST
end

-- Items go in and out of the offer list only while a trade is open and the
-- player has not locked their side.
function T.allow_action(player, action, _, info)
	if action ~= "move" or not touches_offer(info) then return end
	local name = player:get_player_name()
	local trade = trades[name]
	if not trade or trade.locked[name] then return 0 end
end

function T.on_action(player, action, _, info)
	if action == "move" and touches_offer(info) then T.changed(player:get_player_name()) end
end

core.register_allow_player_inventory_action(T.allow_action)
core.register_on_player_inventory_action(T.on_action)

local function leave(player)
	local name = player:get_player_name()
	if trades[name] then T.cancel(name, "left") end
	forget_requests(name)
end

core.register_on_leaveplayer(leave)

core.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	if trades[name] then T.cancel(name, "died") end
end)

-- Anything a crash left on the table goes back.
core.register_on_joinplayer(function(player)
	T.recover(player:get_player_name())
end)

core.register_on_shutdown(function()
	for name in pairs(trades) do T.cancel(name, "shutdown") end
end)

-- Forget every trade and request. For tests only.
function T.reset()
	for name in pairs(trades) do T.cancel(name, "reset") end
	requests, outgoing = {}, {}
end

mine_shop_gui.trade = T
