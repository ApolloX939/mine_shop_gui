-- Collects what the pricing needs from the running game: recipes, group
-- members and the flags items set on themselves. Call after all mods loaded.
--
-- Recipes come from the built-in crafting (normal, cooking) and from Technic's
-- machines when it is installed. Recipes with more than one output are skipped.

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

local function signature(recipe)
	local parts = {}
	for _, input in ipairs(recipe.inputs) do
		parts[#parts + 1] = (input.name or ("group:" .. input.group)) .. "*" .. input.count
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- All usable recipes, in a stable order so that ties always resolve the same way.
function M.recipes()
	local recipes = craft_recipes()
	for _, recipe in ipairs(technic_recipes()) do recipes[#recipes + 1] = recipe end
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
	return recipes
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
