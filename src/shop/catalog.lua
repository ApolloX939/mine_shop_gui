-- What the shop window lists: categories, items, search and paging.
-- Built from mine_shop_gui.pricing.items and rebuilt whenever prices are regenerated.

local P = mine_shop_gui.pricing
local api = mine_shop_gui.currency

local C = {}

-- A mod with fewer priced items than this is folded into "Other".
local MIN_CATEGORY = 4

local cache

-- Item description as plain text: first line, translation and colour codes removed.
local function plain(text)
	text = (text or ""):gsub("\n.*", "")
	if core.get_translated_string then
		local ok, translated = pcall(core.get_translated_string, "en", text)
		if ok and translated then text = translated end
	end
	if core.strip_escapes then text = core.strip_escapes(text) end
	return text
end

-- The mod's title from its mod.conf, or its name.
local function mod_title(mod)
	local path = core.get_modpath(mod)
	if path then
		local title = Settings(path .. "/mod.conf"):get("title")
		if title and title ~= "" then return plain(title) end
	end
	-- no title: "stairs" -> "Stairs", "everness_extras" -> "Everness extras"
	local words = mod:gsub("_", " ")
	return words:sub(1, 1):upper() .. words:sub(2)
end

local function build()
	local list, by_mod = {}, {}
	for name, entry in pairs(P.items) do
		local def = core.registered_items[name]
		-- hidden variants and items that cannot be traded either way stay out
		if def and (def.groups or {}).not_in_creative_inventory ~= 1
				and not (entry.no_buy and entry.no_sell) and not api.is_money(name) then
			local record = {
				name = name,
				mod = name:match("^([^:]+):") or "?",
				title = plain(def.description),
				price = entry.price,
			}
			if record.title == "" then record.title = name end
			record.key = record.title:lower()
			list[#list + 1] = record
			by_mod[record.mod] = (by_mod[record.mod] or 0) + 1
		end
	end
	table.sort(list, function(a, b)
		if a.key ~= b.key then return a.key < b.key end
		return a.name < b.name
	end)

	-- a category per mod, small mods together under "other"
	local members, icon_price, categories = { all = list }, {}, {}
	for _, record in ipairs(list) do
		local id = by_mod[record.mod] >= MIN_CATEGORY and record.mod or "other"
		record.category = id
		members[id] = members[id] or {}
		table.insert(members[id], record)
		-- the dearest item stands in as the category's picture
		if not icon_price[id] or record.price > icon_price[id].price then icon_price[id] = record end
	end
	for id, records in pairs(members) do
		if id ~= "all" and id ~= "other" then
			categories[#categories + 1] = { id = id, title = mod_title(id), icon = icon_price[id].name, count = #records }
		end
	end
	table.sort(categories, function(a, b) return a.title:lower() < b.title:lower() end)
	table.insert(categories, 1, { id = "all", title = "Everything", icon = "", count = #list })
	if members.other then
		categories[#categories + 1] = { id = "other", title = "Other", icon = icon_price.other.name, count = #members.other }
	end
	-- "Everything" is shown with the dearest item overall
	local dearest
	for _, record in ipairs(list) do
		if not dearest or record.price > dearest.price then dearest = record end
	end
	-- a chest stands for "Everything" when there is one, so it differs from the mod pictures
	if core.registered_items["default:chest"] and P.items["default:chest"] then
		categories[1].icon = "default:chest"
	elseif dearest then
		categories[1].icon = dearest.name
	end

	return { generation = P.generation, list = list, members = members, categories = categories }
end

local function data()
	local currency = api.active and api.active.name
	if not cache or cache.generation ~= P.generation or cache.currency ~= currency then
		cache = build()
		cache.currency = currency
	end
	return cache
end

-- All categories, "Everything" first and "Other" last.
function C.categories()
	return data().categories
end

function C.category(id)
	for _, category in ipairs(data().categories) do
		if category.id == id then return category end
	end
end

-- Items of a category, optionally narrowed by search words (all must match the
-- item's title or its technical name).
function C.items(category, query)
	local source = data().members[category] or data().list
	local words = {}
	for word in (query or ""):lower():gmatch("%S+") do words[#words + 1] = word end
	if #words == 0 then return source end
	local result = {}
	for _, record in ipairs(source) do
		local haystack = record.key .. " " .. record.name:lower()
		local ok = true
		for _, word in ipairs(words) do
			if not haystack:find(word, 1, true) then ok = false break end
		end
		if ok then result[#result + 1] = record end
	end
	return result
end

-- One page of a list. Returns the slice, the page actually shown, and the page count.
function C.page(list, page, per_page)
	local pages = math.max(1, math.ceil(#list / per_page))
	page = math.min(math.max(1, page or 1), pages)
	local slice = {}
	for i = (page - 1) * per_page + 1, math.min(#list, page * per_page) do
		slice[#slice + 1] = list[i]
	end
	return slice, page, pages
end

mine_shop_gui.shop = mine_shop_gui.shop or {}
mine_shop_gui.shop.catalog = C
