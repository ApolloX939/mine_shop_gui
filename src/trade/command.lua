-- The /trade chat command:
--   /trade <player>            ask a player to trade (or accept, if they asked you)
--   /trade accept [player]     accept a request
--   /trade decline [player]    turn requests down
--   /trade cancel              end your trade, or take back your request
--   /trade                     show the window again, or who is asking
--
-- Needs the shout and interact privileges, and so does the other player.

local T = mine_shop_gui.trade
local ui = T.ui

local S = core.get_translator(core.get_current_modname())

local M = {}

local REASONS = {
	self = S("You cannot trade with yourself."),
	busy = S("One of you is already in a trade."),
	not_allowed = S("That player is not allowed to trade."),
	not_found = S("Nobody is asking you to trade."),
	unavailable = S("The trade cannot do that right now."),
}

-- The online player a typed name stands for: exact first, then ignoring case.
local function find_player(text)
	if core.get_player_by_name(text) then return text end
	local wanted = text:lower()
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_player_name():lower() == wanted then return player:get_player_name() end
	end
	return nil
end

local function failure(code, who)
	if code == "offline" then return false, S("@1 is not online.", who or "?") end
	if code == "choose" then return false, S("More than one player asked: @1. Say which one.", who or "") end
	return false, REASONS[code] or REASONS.unavailable
end

local function started(result)
	if result == "started" then return true end
	return true, S("Trade request sent. It runs out in @1 seconds.", T.REQUEST_SECONDS)
end

function M.run(name, param)
	param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local command, rest = param:match("^(%S+)%s*(.*)$")
	local lowered = command and command:lower()

	if not command then
		if T.get(name) then
			ui.show(name)
			return true
		end
		local waiting = T.incoming(name)
		if #waiting == 0 then return false, S("Usage: /trade <player> | accept | decline | cancel") end
		return true, S("Waiting for your answer: @1. Type /trade accept or /trade decline.", table.concat(waiting, ", "))
	elseif lowered == "cancel" then
		if T.get(name) then
			T.cancel(name, "cancelled")
			return true
		end
		if T.withdraw_request(name) then return true, S("Your request was taken back.") end
		return false, S("You are not trading with anybody.")
	elseif lowered == "accept" or lowered == "decline" then
		local from
		if rest ~= "" then
			from = find_player(rest)
			if not from then return failure("offline", rest) end
		end
		if lowered == "decline" then
			local ok, result = T.decline(name, from)
			if not ok then return failure(result) end
			return true, S("Request declined.")
		end
		local ok, result, extra = T.accept(name, from)
		if not ok then return failure(result, type(extra) == "table" and table.concat(extra, ", ") or nil) end
		return true
	end

	local target = find_player(param)
	if not target then return failure("offline", param) end
	local ok, result = T.request(name, target)
	if not ok then return failure(result, target) end
	return started(result)
end

core.register_chatcommand("trade", {
	params = S("<player> | accept [player] | decline [player] | cancel"),
	description = S("Trade items and money with another player"),
	privs = { shout = true, interact = true },
	func = M.run,
})

T.command = M
