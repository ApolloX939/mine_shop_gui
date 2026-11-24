-- Optional: post auction offers to Discord through a webhook.
--
-- Setup (all of it is optional; nothing happens without a webhook):
--   * mine_shop_gui_discord_webhook = the webhook URL of the channel.
--   * Luanti only lets trusted mods use the internet: add mine_shop_gui to
--     secure.http_mods in minetest.conf.
--   * For one thread per offer the webhook's channel must be a Forum (or Media)
--     channel: a webhook can only start threads there. Every new offer becomes
--     a thread, and bids, the sale, the end and a take-down are posted into it.
--     For an ordinary text channel set mine_shop_gui_discord_threads = false:
--     each of those becomes a plain message in the channel instead.
--   * The opening message is edited as things change (the current bid, then
--     SOLD, WON, EXPIRED or TAKEN DOWN with the time it ended; this needs
--     Luanti 5.7 or newer for PATCH requests). While an offer runs, its end is
--     a Discord relative time ("in 3 hours") that counts down by itself in
--     everyone's Discord, so it needs no edits.
--
-- Only offer facts go out (items, prices, player names, time). Mentions are
-- switched off, so a player name or item title cannot ping anyone. The URL is
-- a secret and is never logged.
--
-- Messages are sent one at a time with a short pause and retried when Discord
-- says to slow down. A message that fails is logged (without the URL) and
-- dropped; it never affects the offer itself.

local api = mine_shop_gui.currency
local A = mine_shop_gui.auction

local D = {}

local http = core.request_http_api and core.request_http_api()

-- Replaced by tests.
function D.can_send()
	return http ~= nil
end

---------------------------------------------------------------- settings

-- The webhook URL, or nil when none is set or it is not a Discord webhook.
function D.webhook()
	local url = (core.settings:get("mine_shop_gui_discord_webhook") or ""):gsub("%s", ""):gsub("%?.*$", "")
	if url == "" then return nil end
	if not url:match("^https://[%w%-]*%.?discord%.com/api/webhooks/%d+/[%w_%-]+$")
			and not url:match("^https://[%w%-]*%.?discordapp%.com/api/webhooks/%d+/[%w_%-]+$") then
		return nil
	end
	return url
end

function D.threads()
	return core.settings:get_bool("mine_shop_gui_discord_threads", true)
end

function D.enabled()
	return D.webhook() ~= nil and D.can_send()
end

local function sender_name()
	local name = core.settings:get("mine_shop_gui_discord_name") or ""
	if name == "" then name = "Auction House" end
	return name:sub(1, 80)
end

---------------------------------------------------------------- emoji

-- Standard emoji by default (written as byte escapes so the file stays plain
-- ASCII). A server can swap any of them for its own with
-- mine_shop_gui_discord_emoji_overrides, e.g. sold=<:sold:123456789012345678>,
-- or turn them all off with mine_shop_gui_discord_emojis = false.
local EMOJI = {
	sell = "\240\159\143\183\239\184\143", -- price tag
	bid = "\240\159\148\168", -- hammer
	goods = "\240\159\147\166", -- package
	price = "\240\159\146\176", -- money bag
	start = "\240\159\143\129", -- chequered flag
	current_bid = "\240\159\146\181", -- banknote
	buyout = "\226\154\161", -- high voltage
	ends = "\226\143\179", -- hourglass
	ended = "\240\159\143\129", -- chequered flag
	sold = "\226\156\133", -- check mark
	won = "\240\159\143\134", -- trophy
	expired = "\226\140\155", -- hourglass
	taken_down = "\240\159\154\171", -- prohibited
}

local overrides

local function parse_overrides()
	overrides = {}
	for entry in (core.settings:get("mine_shop_gui_discord_emoji_overrides") or ""):gmatch("[^,]+") do
		local key, value = entry:match("^%s*([%w_]+)%s*=%s*(%S*)%s*$")
		if key and EMOJI[key] and #value <= 60 then overrides[key] = value end
	end
end

function D.emojis_on()
	return core.settings:get_bool("mine_shop_gui_discord_emojis", true)
end

-- The emoji for `key` followed by a space, or "" when emoji are off.
local function E(key)
	if not D.emojis_on() then return "" end
	parse_overrides()
	local emoji = overrides[key] or EMOJI[key]
	if not emoji or emoji == "" then return "" end
	return emoji .. " "
end

---------------------------------------------------------------- text

-- Keep player names and item titles from turning into Discord formatting.
local function plain(text)
	return (tostring(text):gsub("([\\*_~`>|#])", "\\%1"):gsub("[\r\n]+", " "))
end

-- Cut to `limit` characters (not bytes), ending in "..".
local function cut(text, limit)
	local characters = {}
	for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do characters[#characters + 1] = character end
	if #characters <= limit then return text end
	return table.concat(characters, "", 1, limit - 2) .. ".."
end

local function describe(stack)
	return stack:get_count() .. "x " .. plain(A.title(stack:get_name()))
end

local function goods_text(offer)
	local parts = {}
	for i, stack in ipairs(A.goods(offer)) do parts[i] = describe(stack) end
	return table.concat(parts, ", ")
end

local function price_text(offer)
	local parts = {}
	if offer.money and offer.money > 0 then parts[#parts + 1] = api.format_symbol(offer.money) end
	for _, entry in ipairs(offer.items or {}) do
		parts[#parts + 1] = entry.count .. "x " .. plain(A.title(entry.name))
	end
	return table.concat(parts, " + ")
end

local function kind_text(offer)
	return offer.kind == "sell" and "Selling" or "Bidding"
end

function D.thread_name(offer)
	local names = {}
	for i, stack in ipairs(A.goods(offer)) do
		names[i] = stack:get_count() .. "x " .. A.title(stack:get_name())
	end
	return cut(E(offer.kind) .. string.format("#%d %s: %s", offer.id, kind_text(offer), table.concat(names, ", ")), 100)
end

-- The message of an offer. `status` is nil while it runs, or the line that
-- says how it ended; then the end time is the moment it ended.
function D.offer_text(offer, status)
	local lines = {}
	if status then lines[1] = "**" .. status .. "**" end
	lines[#lines + 1] = E(offer.kind) .. string.format("**%s #%d** by `%s`", kind_text(offer), offer.id, offer.owner)
	lines[#lines + 1] = E("goods") .. "> " .. goods_text(offer)
	if offer.kind == "sell" then
		lines[#lines + 1] = E("price") .. "**Price:** " .. price_text(offer)
	else
		if offer.bidder then
			lines[#lines + 1] = E("current_bid") .. string.format("**Current bid:** %s by `%s`", api.format_symbol(offer.bid), offer.bidder)
		else
			lines[#lines + 1] = E("start") .. "**Starting bid:** " .. api.format_symbol(offer.start)
		end
		lines[#lines + 1] = E("buyout") .. "**Buy-out:** " .. api.format_symbol(offer.buyout)
	end
	if status then
		lines[#lines + 1] = E("ended") .. string.format("**Ended:** <t:%d:f>", A.now())
	else
		lines[#lines + 1] = E("ends") .. string.format("**Ends:** <t:%d:R> (<t:%d:f>)", offer.expires, offer.expires)
		lines[#lines + 1] = "Open the auction house in game with `/ah`."
	end
	return cut(table.concat(lines, "\n"), 2000)
end

-- How the offer ended, for the edited opening message; nil for events that
-- do not end it.
function D.final_status(event, offer, info)
	if event == "sold" then
		return E("sold") .. string.format("SOLD to `%s` for %s", info.buyer, price_text(offer))
	elseif event == "bought_out" then
		return E("sold") .. string.format("SOLD: bought out by `%s` for %s", info.buyer, api.format_symbol(offer.buyout))
	elseif event == "won" then
		return E("won") .. string.format("SOLD: won by `%s` with %s", offer.bidder, api.format_symbol(offer.bid))
	elseif event == "expired" then
		return E("expired") .. "EXPIRED: nobody bought it"
	elseif event == "revoked" then
		return E("taken_down") .. (info.by_admin and "TAKEN DOWN by an admin" or "TAKEN DOWN by its owner")
	end
end

-- What an event adds to the offer's thread, or nil if it is not worth posting.
function D.update_text(event, offer, info)
	if event == "bid" then
		return E("bid") .. string.format("**New bid:** %s by `%s`. Next bid: %s.", api.format_symbol(info.amount),
			info.bidder, api.format_symbol(A.next_bid(offer)))
	end
	local status = D.final_status(event, offer, info)
	if status then return "**" .. status .. "**" end
end

---------------------------------------------------------------- sending

-- request = { url, body, method (default POST) }; callback({ ok, code, data }). Replaced by tests.
function D.transport(request, callback)
	http.fetch({
		url = request.url,
		method = request.method or "POST",
		timeout = 10,
		extra_headers = { "Content-Type: application/json" },
		data = core.write_json(request.body),
	}, function(result)
		callback({ ok = result.succeeded, code = result.code, data = result.data })
	end)
end

local queue, busy = {}, false
local PAUSE = 0.6

local function log(level, text)
	core.log(level, "[mine_shop_gui] discord: " .. text)
end

local function pump()
	if busy or #queue == 0 then return end
	busy = true
	local job = table.remove(queue, 1)
	D.transport(job.request, function(result)
		local pause = PAUSE
		if result.code == 429 and (job.tries or 0) < 5 then
			-- told to slow down: try again after the wait Discord names
			local reply = result.data and core.parse_json(result.data)
			pause = math.min(60, (type(reply) == "table" and tonumber(reply.retry_after)) or 2) + 0.5
			job.tries = (job.tries or 0) + 1
			table.insert(queue, 1, job)
		elseif result.ok and result.code and result.code < 300 then
			if job.done then
				local reply = result.data and result.data ~= "" and core.parse_json(result.data)
				job.done(type(reply) == "table" and reply or {})
			end
		else
			log("warning", "a message was not delivered (HTTP " .. tostring(result.code) .. ")"
				.. (result.code == 400 and job.thread_name
					and "; the channel must be a Forum channel for threads, or set mine_shop_gui_discord_threads = false" or ""))
			if job.failed then job.failed() end
		end
		core.after(pause, function()
			busy = false
			pump()
		end)
	end)
end

local function send(job)
	queue[#queue + 1] = job
	pump()
end

-- Forget everything waiting to be sent (for tests).
function D.reset()
	queue, busy = {}, false
end

-- Number of messages waiting to go out (for tests).
function D.queued()
	return #queue + (busy and 1 or 0)
end

local function body(text, extra)
	local result = { content = text, username = sender_name(), allowed_mentions = { parse = {} } }
	for key, value in pairs(extra or {}) do result[key] = value end
	return result
end

-- Offers whose Discord post is still being created: updates wait here.
local creating = {}

local reset_queue = D.reset
function D.reset()
	reset_queue()
	creating = {}
end

-- Where this offer's posts go: the thread, or the channel itself.
local function target_url(offer, path)
	local url = D.webhook() .. (path or "")
	if offer.discord.thread then url = url .. "?thread_id=" .. offer.discord.thread end
	return url
end

-- Say something new in the offer's thread (or the channel).
local function post_update(offer, text)
	if not offer.discord.thread then text = string.format("**#%d** %s", offer.id, text) end
	send({ request = { url = target_url(offer), body = body(text) } })
end

-- Rewrite the opening message to match the offer now.
local function edit_offer(offer, status)
	local target = offer.discord
	if not target or not target.message then return end
	send({ request = {
		method = "PATCH",
		url = target_url(offer, "/messages/" .. target.message),
		body = { content = D.offer_text(offer, status), allowed_mentions = { parse = {} } },
	} })
end

local function post_offer(offer)
	local url, threads = D.webhook(), D.threads()
	-- events that happen before Discord has answered wait here
	creating[offer.id] = { events = {} }
	local function finish(target)
		local waiting = creating[offer.id]
		creating[offer.id] = nil
		offer.discord = target
		A.save()
		for _, item in ipairs(waiting.events) do
			if item.text then post_update(offer, item.text) end
		end
		-- one edit brings the opening message up to date with all of them
		if #waiting.events > 0 then edit_offer(offer, waiting.status) end
	end
	send({
		request = {
			url = url .. "?wait=true",
			body = body(D.offer_text(offer), threads and { thread_name = D.thread_name(offer) } or nil),
		},
		thread_name = threads,
		done = function(reply)
			local message = reply.id and tostring(reply.id) or nil
			if threads and reply.channel_id then
				finish({ thread = tostring(reply.channel_id), message = message })
			else
				finish({ plain = true, message = message })
			end
		end,
		failed = function()
			-- nothing was posted: later events have nowhere to go
			creating[offer.id] = nil
		end,
	})
end

function D.on_event(event, offer, info)
	if not D.enabled() then return end
	if event == "created" then
		post_offer(offer)
		return
	end
	local text = D.update_text(event, offer, info)
	local status = D.final_status(event, offer, info)
	if offer.discord then
		if text then post_update(offer, text) end
		edit_offer(offer, status)
	elseif creating[offer.id] then
		table.insert(creating[offer.id].events, { text = text })
		if status then creating[offer.id].status = status end
	end
end

A.on(D.on_event)

core.register_on_mods_loaded(function()
	local raw = (core.settings:get("mine_shop_gui_discord_webhook") or ""):gsub("%s", "")
	if raw == "" then return end
	if not D.webhook() then
		log("warning", "mine_shop_gui_discord_webhook is not a Discord webhook URL; nothing will be posted")
	elseif not D.can_send() then
		log("warning", "the webhook is set but the mod may not use the internet: add mine_shop_gui to secure.http_mods")
	else
		log("action", "posting auction offers to Discord" .. (D.threads() and " as threads" or ""))
	end
end)

A.discord = D
