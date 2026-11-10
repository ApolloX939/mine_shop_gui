-- Loads the base price list: a Lua file that returns a table of
-- ["mod:item"] = price units.
--
-- Two files are read and merged:
--   <mod>/base_prices.lua                       ships with the mod
--   <world>/mine_shop_gui_prices.lua            optional, edited by the server owner
-- Entries in the world file replace those in the mod file. Setting an item to
-- `false` in the world file removes its price.
--
-- Files run in an empty environment, so they can only hold data.

local M = {}

local function describe(value)
	return type(value) == "string" and ("'" .. value .. "'") or tostring(value)
end

-- Read one file. Returns prices (table), problems (list of strings).
-- A missing file returns nil, "not found". An unreadable one returns nil, message.
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

local function log(level, msg)
	core.log(level, "[mine_shop_gui] " .. msg)
end

local function load_file(path, label, required)
	local prices, problems = M.parse(path)
	if not prices then
		if problems == "not found" and not required then return nil end
		log("warning", label .. " price file could not be used: " .. tostring(problems))
		return nil
	end
	for _, problem in ipairs(problems) do
		log("warning", label .. " price file: " .. problem)
	end
	return prices
end

-- Load the mod's file and the world's file, merged.
function M.load()
	local mod_file = mine_shop_gui.modpath .. "/base_prices.lua"
	local world_file = core.get_worldpath() .. "/mine_shop_gui_prices.lua"
	local shipped = load_file(mod_file, "mod", true) or {}
	local override = load_file(world_file, "world", false)
	return M.merge(shipped, override)
end

return M
