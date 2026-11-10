-- Loads the base price list. Every file is a Lua table of
-- ["mod:item"] = price units, run in an empty environment so it can only hold data.
--
-- Files, merged in this order (later entries replace earlier ones):
--   prices/games/<game_id>.lua      for the running game (for example minetest, mineclonia)
--   prices/mods/<mod_id>.lua        for every enabled mod, in alphabetical order
--   <world>/mine_shop_gui_prices.lua   optional, edited by the server owner
-- Setting an item to `false` removes its price from everything loaded before it.
--
-- <mod_id> is the `name` in the mod's mod.conf (preferred). A file named after
-- the mod's folder is still found when the names differ, but that is the old
-- style and is deprecated. Prices for a game or mod that is not installed are
-- never read.

local M = {}

local function describe(value)
	return type(value) == "string" and ("'" .. value .. "'") or tostring(value)
end

-- Read one file. Returns prices (table), problems (list of strings).
-- A missing file returns nil, "not found". An unusable one returns nil, message.
function M.parse(path)
	local file = io.open(path, "rb")
	if not file then return nil, "not found" end
	local text = file:read("*a")
	file:close()

	local chunk, err = loadstring(text, "@" .. path)
	if not chunk then return nil, err end
	setfenv(chunk, {})
	local ok, result = pcall(chunk)
	if not ok then return nil, tostring(result) end
	if type(result) ~= "table" then return nil, "the file must return a table" end

	local prices, problems = {}, {}
	for name, price in pairs(result) do
		if type(name) ~= "string" or name == "" then
			problems[#problems + 1] = "item name " .. describe(name) .. " is not a string"
		elseif price == false then
			prices[name] = false
		elseif type(price) ~= "number" or price ~= price or price < 0 or price == math.huge then
			problems[#problems + 1] = describe(name) .. " has an invalid price " .. describe(price)
		else
			prices[name] = price
		end
	end
	table.sort(problems)
	return prices, problems
end

-- Merge `override` over `base`. `false` in the override removes an item.
function M.merge(base, override)
	local merged = {}
	for name, price in pairs(base) do merged[name] = price end
	for name, price in pairs(override or {}) do
		if price == false then
			merged[name] = nil
		else
			merged[name] = price
		end
	end
	return merged
end

local function exists(path)
	local file = io.open(path, "rb")
	if file then file:close() return true end
	return false
end

-- Find the price file of a mod inside `dir` (the prices/mods folder).
-- `modname` is the name the engine uses (mod.conf name, else folder name) and
-- `modpath` the mod's folder. Returns the file path and whether it was found
-- through the deprecated folder-name style, or nil if there is none.
function M.mod_file(dir, modname, modpath)
	local preferred = dir .. "/" .. modname .. ".lua"
	if exists(preferred) then return preferred, false end
	local folder = modpath:match("([^/\\]+)[/\\]*$")
	if folder and folder ~= modname then
		local old = dir .. "/" .. folder .. ".lua"
		if exists(old) then return old, true end
	end
	return nil
end

local function log(level, msg)
	core.log(level, "[mine_shop_gui] " .. msg)
end

local function load_file(path, label)
	local prices, problems = M.parse(path)
	if not prices then
		log("warning", label .. " price file could not be used: " .. tostring(problems))
		return nil
	end
	for _, problem in ipairs(problems) do
		log("warning", label .. " price file: " .. problem)
	end
	return prices
end

-- Load every price file that applies to this server.
-- Returns the merged prices and a list of item names that are not registered
-- (usually typos or items from a mod version that is not installed).
-- Call after all mods have loaded.
function M.load(opts)
	opts = opts or {}
	local root = opts.root or (mine_shop_gui.modpath .. "/prices")
	local world_file = opts.world_file or (core.get_worldpath() .. "/mine_shop_gui_prices.lua")
	local prices = {}

	local game = opts.game_id
	if game == nil and core.get_game_info then
		game = (core.get_game_info() or {}).id
	end
	if game and game ~= "" then
		local path = root .. "/games/" .. game .. ".lua"
		if exists(path) then
			prices = M.merge(prices, load_file(path, "game '" .. game .. "'") or {})
		end
	end

	for _, modname in ipairs(opts.mods or core.get_modnames()) do
		local path, deprecated = M.mod_file(root .. "/mods", modname, core.get_modpath(modname) or "")
		if path then
			if deprecated then
				log("warning", "price file " .. path .. " is named after the mod's folder; "
					.. "name it after the mod.conf name '" .. modname .. "' instead")
			end
			prices = M.merge(prices, load_file(path, "mod '" .. modname .. "'") or {})
		end
	end

	if exists(world_file) then
		prices = M.merge(prices, load_file(world_file, "world") or {})
	end

	local unknown = {}
	for name in pairs(prices) do
		if not core.registered_items[name] and not core.registered_aliases[name] then
			unknown[#unknown + 1] = name
		end
	end
	table.sort(unknown)
	for _, name in ipairs(unknown) do
		log("warning", "price file lists unknown item '" .. name .. "'")
	end
	return prices, unknown
end

return M
