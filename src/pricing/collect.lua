-- Collects what the pricing needs from the running game: recipes, group
-- members and the flags items set on themselves. Call after all mods loaded.
--
-- Recipes come from the built-in crafting (normal, cooking), from Technic's
-- machines, from Techage's electronic fabricators and doser, and (when
-- unified_inventory is installed) from Techage's furnace, melting pot, grinder
-- and mill, and from Skyblock Zero's machines. Recipes with more than one output
-- are skipped.

local M = {}

local IGNORED = { [""] = true, air = true, unknown = true, ignore = true }
local STACK_FLAG_KEYS = { "no_buy", "no_sell" }

-- Follow aliases to the real item name.
function M.resolve(name)
	for _ = 1, 10 do
		local target = core.registered_aliases[name]
		if not target then break end
		name = target
	end
	return name
end

-- "mod:item 3" -> "mod:item", 3, or nil if it is not a usable item.
local function parse_stack(text)
	if type(text) ~= "string" or text == "" then return nil end
	local stack = ItemStack(text)
	local name, count = M.resolve(stack:get_name()), stack:get_count()
	if IGNORED[name] or count < 1 or not core.registered_items[name] then return nil end
	return name, count
end

-- Add an ingredient to a list, merging repeats (nine stone in a grid is one
-- ingredient of count nine).
local function add_input(inputs, index, key, entry)
	local existing = index[key]
	if existing then
		existing.count = existing.count + 1
	else
		entry.count = 1
		index[key] = entry
		inputs[#inputs + 1] = entry
	end
end

local function craft_recipes()
	local recipes = {}
	for name in pairs(core.registered_items) do
		if not IGNORED[name] then
			for _, craft in ipairs(core.get_all_craft_recipes(name) or {}) do
				if craft.type ~= "fuel" then
					local out_name, out_count = parse_stack(craft.output)
					local inputs, index, usable = {}, {}, out_name ~= nil
					for _, item in pairs(craft.items or {}) do
						if item ~= "" then
							if item:sub(1, 6) == "group:" then
								add_input(inputs, index, item, { group = item:sub(7) })
							else
								local in_name = parse_stack(item)
								if in_name then
									add_input(inputs, index, in_name, { name = in_name })
								else
									usable = false
								end
							end
						end
					end
					if usable and #inputs > 0 then
						recipes[#recipes + 1] = {
							type = craft.type,
							inputs = inputs,
							output = { name = out_name, count = out_count },
						}
					end
				end
			end
		end
	end
	return recipes
end

local function technic_recipes()
	local recipes = {}
	local technic = rawget(_G, "technic")
	if not technic or type(technic.recipes) ~= "table" then return recipes end
	for typename, def in pairs(technic.recipes) do
		for _, recipe in pairs(def.recipes or {}) do
			local outputs = recipe.output
			if type(outputs) ~= "table" then outputs = { outputs } end
			if #outputs == 1 then
				local out_name, out_count = parse_stack(outputs[1])
				local inputs, usable = {}, out_name ~= nil
				for item, count in pairs(recipe.input or {}) do
					local in_name = parse_stack(item)
					if in_name then
						inputs[#inputs + 1] = { name = in_name, count = count }
					else
						usable = false
					end
				end
				if usable and #inputs > 0 then
					recipes[#recipes + 1] = {
						type = typename,
						inputs = inputs,
						output = { name = out_name, count = out_count },
					}
				end
			end
		end
	end
	return recipes
end

-- "name 3" or "group:wood 2" -> an ingredient, or nil if it cannot be identified.
local function parse_input(text)
	if type(text) ~= "string" or text == "" then return nil end
	local first, count = text:match("^(%S+)%s*(%d*)$")
	if not first then return nil end
	if first:sub(1, 6) == "group:" then
		return { group = first:sub(7), count = tonumber(count) or 1 }
	end
	local name, n = parse_stack(text)
	if not name then return nil end
	return { name = name, count = n }
end

-- Build a recipe from ingredient texts and one output text, or nil if any part
-- is unusable (an ingredient that is not a registered item makes the whole
-- recipe unusable, because its cost would be unknown).
local function make_recipe(rtype, input_texts, output_text)
	local out_name, out_count = parse_stack(output_text)
	if not out_name then return nil end
	local inputs, index = {}, {}
	for _, text in ipairs(input_texts) do
		if text ~= "" then
			local input = parse_input(text)
			if not input then return nil end
			local key = input.name or ("group:" .. input.group)
			if index[key] then
				index[key].count = index[key].count + input.count
			else
				index[key] = input
				inputs[#inputs + 1] = input
			end
		end
	end
	if #inputs == 0 then return nil end
	return { type = rtype, inputs = inputs, output = { name = out_name, count = out_count } }
end

-- Techage's electronic fabricators and chemical doser keep their recipes in a
-- table that only techage.recipes.get can reach, one recipe per index. The
-- type names are the ones Techage registers them under. Waste products (empty
-- spools, red mud) are treated as free by-products, and catalysts are not
-- consumed, so neither is part of the cost.
local TECHAGE_TYPES = { "ta2_electronic_fab", "ta3_electronic_fab", "ta4_electronic_fab", "ta4_doser" }

local function techage_recipes()
	local recipes = {}
	local techage = rawget(_G, "techage")
	if not (techage and type(techage.recipes) == "table" and type(techage.recipes.get) == "function") then
		return recipes
	end
	for _, rtype in ipairs(TECHAGE_TYPES) do
		local ok, first = pcall(techage.recipes.get, { recipe_idx = 1 }, rtype)
		if ok and type(first) == "table" then
			-- get() returns the first recipe again when the index runs past the end
			local list = { first }
			for i = 2, 1000 do
				local ok_i, recipe = pcall(techage.recipes.get, { recipe_idx = i }, rtype)
				if not ok_i or recipe == nil or recipe == first then break end
				list[#list + 1] = recipe
			end
			for _, r in ipairs(list) do
				local texts = {}
				for _, input in ipairs(r.input or {}) do
					if input.name and input.name ~= "" and (input.num or 0) > 0 then
						texts[#texts + 1] = input.name .. " " .. input.num
					end
				end
				local out = r.output
				if type(out) == "table" and out.name and out.name ~= "" then
					local recipe = make_recipe(rtype, texts, out.name .. " " .. (out.num or 1))
					if recipe then recipes[#recipes + 1] = recipe end
				end
			end
		end
	end
	return recipes
end

-- Recipes of Techage's furnace, melting pot, grinder and mill are private to
-- those machines, but Techage also hands them to unified_inventory's craft
-- guide. Read them from there when that mod is installed. Sieves and the
-- rinser are left out on purpose: their output is random.
local GUIDE_TYPES = { melting = true, ta3_melting = true, grinding = true, milling = true }

local function guide_recipes()
	local recipes = {}
	local ui = rawget(_G, "unified_inventory")
	if not (ui and type(ui.crafts_for) == "table" and type(ui.crafts_for.recipe) == "table") then
		return recipes
	end
	for _, list in pairs(ui.crafts_for.recipe) do
		for _, craft in ipairs(list) do
			if GUIDE_TYPES[craft.type] then
				-- the output is a string, or a list holding one ItemStack
				local out = craft.output
				if type(out) == "table" then
					out = (#out == 1) and out[1] or nil
				end
				local out_text
				if type(out) == "string" then
					out_text = out
				elseif out ~= nil then
					local ok, text = pcall(function() return out:to_string() end)
					if ok then out_text = text end
				end
				local texts = {}
				for _, item in pairs(craft.items or {}) do
					if type(item) ~= "string" then texts = nil break end
					texts[#texts + 1] = item
				end
				if out_text and texts then
					local recipe = make_recipe(craft.type, texts, out_text)
					if recipe then recipes[#recipes + 1] = recipe end
				end
			end
		end
	end
	return recipes
end

-- Skyblock Zero's machines (crushers, compressors, the electronics fabricator, ...)
-- keep their recipes in sbz_api.recipe.registered_crafts, filled one tick after
-- loading (the shop builds prices after that). The electronics fabricator's
-- recipes go to unified_inventory directly, under the type "ele_fab".
-- Entries without ingredients only tell the craft guide where an item comes from.
local function sbz_recipes()
	local recipes = {}
	local api = rawget(_G, "sbz_api")
	if not (api and type(api.recipe) == "table" and type(api.recipe.registered_crafts) == "table") then
		return recipes
	end
	local crafts = {}
	for _, craft in ipairs(api.recipe.registered_crafts) do crafts[#crafts + 1] = craft end
	local ui = rawget(_G, "unified_inventory")
	if ui and type(ui.crafts_for) == "table" and type(ui.crafts_for.recipe) == "table" then
		for _, list in pairs(ui.crafts_for.recipe) do
			for _, craft in ipairs(list) do
				if craft.type == "ele_fab" then crafts[#crafts + 1] = craft end
			end
		end
	end
	for _, craft in ipairs(crafts) do
		local out = craft.output
		if type(out) == "table" then out = (#out == 1) and out[1] or nil end
		if type(out) ~= "string" and out ~= nil then
			local ok, text = pcall(function() return out:to_string() end)
			out = ok and text or nil
		end
		local texts = {}
		for _, item in pairs(craft.items or {}) do
			if type(item) ~= "string" then texts = nil break end
			texts[#texts + 1] = item
		end
		if out and texts then
			local recipe = make_recipe(craft.type or "sbz", texts, out)
			if recipe then recipes[#recipes + 1] = recipe end
		end
	end
	return recipes
end

local function signature(recipe)
	local parts = {}
	for _, input in ipairs(recipe.inputs) do
		parts[#parts + 1] = (input.name or ("group:" .. input.group)) .. "*" .. input.count
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- All usable recipes, in a stable order so that ties always resolve the same way.
-- The same recipe can arrive from two sources (Technic's grinder is also in the
-- craft guide, Techage's fabricators appear under several tiers); only the first
-- in sorted order is kept.
function M.recipes()
	local recipes = craft_recipes()
	for _, source in ipairs({ technic_recipes, techage_recipes, guide_recipes, sbz_recipes }) do
		for _, recipe in ipairs(source()) do recipes[#recipes + 1] = recipe end
	end
	for _, recipe in ipairs(recipes) do
		table.sort(recipe.inputs, function(a, b)
			return (a.name or a.group) < (b.name or b.group)
		end)
	end
	table.sort(recipes, function(a, b)
		if a.output.name ~= b.output.name then return a.output.name < b.output.name end
		if a.type ~= b.type then return a.type < b.type end
		return signature(a) < signature(b)
	end)
	local unique, seen = {}, {}
	for _, recipe in ipairs(recipes) do
		local key = recipe.output.name .. "*" .. recipe.output.count .. "|" .. signature(recipe)
		if not seen[key] then
			seen[key] = true
			unique[#unique + 1] = recipe
		end
	end
	return unique
end

-- Members of every group the recipes ask for. A group written "a,b" needs both.
function M.groups(recipes)
	local wanted = {}
	for _, recipe in ipairs(recipes) do
		for _, input in ipairs(recipe.inputs) do
			if input.group then wanted[input.group] = true end
		end
	end
	local members = {}
	for spec in pairs(wanted) do members[spec] = {} end
	for name, def in pairs(core.registered_items) do
		if not IGNORED[name] then
			local item_groups = def.groups or {}
			for spec, list in pairs(members) do
				local all = true
				for group in spec:gmatch("[^,]+") do
					if (item_groups[group] or 0) <= 0 then all = false break end
				end
				if all then list[#list + 1] = name end
			end
		end
	end
	for _, list in pairs(members) do table.sort(list) end
	return members
end

-- Flags an item definition sets on itself:
--   _mine_shop_gui = { no_buy = true, no_sell = true }
function M.flags_from_def(def)
	local field = def and def._mine_shop_gui
	if type(field) ~= "table" then return nil end
	local flags = { no_buy = field.no_buy and true or nil, no_sell = field.no_sell and true or nil }
	if flags.no_buy or flags.no_sell then return flags end
	return nil
end

-- Own flags of every registered item that sets any.
function M.item_flags()
	local result = {}
	for name, def in pairs(core.registered_items) do
		local flags = M.flags_from_def(def)
		if flags then result[name] = flags end
	end
	return result
end

-- Flags set on one stack through its metadata:
--   stack:get_meta():set_string("no_sell", "true")
-- A flag is set when the key is present and its value is exactly the string
-- "true". Any other value ("false", "1", "yes", ...) leaves it unset.
-- Metadata has no boolean setter, so the string is what gets stored.
function M.stack_flags(stack)
	local meta = stack:get_meta()
	local flags = {}
	for _, key in ipairs(STACK_FLAG_KEYS) do
		flags[key] = meta:contains(key) and meta:get_string(key) == "true"
	end
	return flags
end

return M
