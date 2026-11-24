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
	return cut(string.format("#%d %s: %s", offer.id, kind_text(offer), table.concat(names, ", ")), 100)
end

-- The opening message of an offer.
function D.offer_text(offer)
	local lines = {
		string.format("**%s #%d** by `%s`", kind_text(offer), offer.id, offer.owner),
		"> " .. goods_text(offer),
	}
	if offer.kind == "sell" then
		lines[#lines + 1] = "**Price:** " .. price_text(offer)
	else
		lines[#lines + 1] = "**Starting bid:** " .. api.format_symbol(offer.start)
		lines[#lines + 1] = "**Buy-out:** " .. api.format_symbol(offer.buyout)
	end
	lines[#lines + 1] = string.format("**Ends:** <t:%d:R>", offer.expires)
	lines[#lines + 1] = "Open the auction house in game with `/ah`."
	return cut(table.concat(lines, "\n"), 2000)
end

-- What an event adds to the offer's thread, or nil if it is not worth posting.
function D.update_text(event, offer, info)
	if event == "bid" then
		return string.format("**New bid:** %s by `%s`. Next bid: %s.", api.format_symbol(info.amount),
			info.bidder, api.format_symbol(A.next_bid(offer)))
	elseif event == "sold" then
		return string.format("**Sold** to `%s` for %s.", info.buyer, price_text(offer))
	elseif event == "bought_out" then
		return string.format("**Bought out** by `%s` for %s.", info.buyer, api.format_symbol(offer.buyout))
	elseif event == "won" then
		return string.format("**Ended.** `%s` won with %s.", offer.bidder, api.format_symbol(offer.bid))
	elseif event == "expired" then
		return "**Ended** without a buyer."
	elseif event == "revoked" then
		return info.by_admin and "**Taken down** by an admin." or "**Taken down** by its owner."
	end
end

---------------------------------------------------------------- sending

-- request = { url, body }; callback({ ok, code, data }). Replaced by tests.
function D.transport(request, callback)
	http.fetch({
		url = request.url,
		method = "POST",
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

local function post_update(offer, text)
	local target = offer.discord
	if not target then
		if creating[offer.id] then table.insert(creating[offer.id], text) end
		return
	end
	if target.thread then
		send({ request = { url = D.webhook() .. "?thread_id=" .. target.thread, body = body(text) } })
	else
		send({ request = { url = D.webhook(), body = body(string.format("**#%d** %s", offer.id, text)) } })
	end
end

local function post_offer(offer)
	local url, threads = D.webhook(), D.threads()
	creating[offer.id] = {}
	local request = {
		url = url .. "?wait=true",
		body = body(D.offer_text(offer), threads and { thread_name = D.thread_name(offer) } or nil),
	}
	local function finish(target)
		local waiting = creating[offer.id] or {}
		creating[offer.id] = nil
		offer.discord = target
		A.save()
		for _, text in ipairs(waiting) do post_update(offer, text) end
	end
	send({
		request = request,
		thread_name = threads,
		done = function(reply)
			if threads and reply.channel_id then
				finish({ thread = tostring(reply.channel_id) })
			else
				finish({ plain = true })
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
	if text then post_update(offer, text) end
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
