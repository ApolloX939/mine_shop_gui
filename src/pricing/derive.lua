-- Derives item prices from base prices and recipes.
--
-- derive{
--   base    = { ["mod:item"] = units },       fixed prices; never overridden
--   recipes = { { type = "alloy",
--                 inputs = { {name = "mod:a", count = 2}, {group = "wood", count = 1} },
--                 output = { name = "mod:b", count = 3 } }, ... },   single-output only
--   groups  = { wood = { "mod:a", "mod:b" } },   members of each group used by recipes
--   markup  = function(recipe_type) return 0.1 end,   optional, fraction added on top
--   flags   = { ["mod:item"] = { no_buy = true, no_sell = true } },   the items' own flags
-- }
-- returns prices, source, dropped, flags, below_base
--   prices   item -> price units
--   source   item -> "base" or the recipe type that gave the price
--   dropped  list of items whose price could not settle (see below)
--   flags    item -> { no_buy = true, no_sell = true } (only items that have any)
--   below_base  item -> cheapest recipe cost, for items with a base price that a
--            recipe can make for less. The base price still wins; this only reports.
--
-- Each item gets the cheapest cost over all its recipes, found by relaxing
-- prices repeatedly until nothing gets cheaper. That makes cycles harmless
-- (block <-> ingots just stops improving). A recipe that can duplicate value
-- (for example 1 a -> 2 a) never settles; items in such a loop lose their
-- derived price and are reported in `dropped`.
-- A group ingredient costs as much as its cheapest priced member.
--
-- Flags are inherited: a derived item gets its own flags plus the flags of every
-- ingredient of the recipe that set its price (for a group ingredient, the
-- member that was used). The item is still priced.

local MAX_PASSES = 200
local MAX_ATTEMPTS = 5
local TOLERANCE = 1e-9

-- Combine two flag tables into a new one, or nil if neither sets a flag.
local function union(a, b)
	local result = {}
	for _, flags in ipairs({ a or {}, b or {} }) do
		if flags.no_buy then result.no_buy = true end
		if flags.no_sell then result.no_sell = true end
	end
	if result.no_buy or result.no_sell then return result end
	return nil
end

local function relax(opts, excluded)
	local prices, source, flags, below = {}, {}, {}, {}
	local own = opts.flags or {}
	for name, price in pairs(opts.base) do
		prices[name] = price
		source[name] = "base"
		flags[name] = union(own[name])
	end
	local groups = opts.groups or {}

	-- Returns the price of an ingredient and the item that supplies it.
	local function input_price(input)
		if input.group then
			local best, best_name
			for _, member in ipairs(groups[input.group] or {}) do
				local price = prices[member]
				if price and (not best or price < best) then
					best, best_name = price, member
				end
			end
			return best, best_name
		end
		return prices[input.name], input.name
	end

	local unstable
	for _ = 1, MAX_PASSES do
		unstable = {}
		local any = false
		for _, recipe in ipairs(opts.recipes) do
			local out = recipe.output.name
			if not excluded[out] then
				local cost, complete, inherited = 0, true, nil
				for _, input in ipairs(recipe.inputs) do
					local price, supplier = input_price(input)
					if not price then complete = false break end
					cost = cost + price * (input.count or 1)
					inherited = union(inherited, flags[supplier])
				end
				if complete then
					local markup = opts.markup and opts.markup(recipe.type) or 0
					local candidate = cost * (1 + markup) / (recipe.output.count or 1)
					local current = prices[out]
					if source[out] == "base" then
						-- fixed price: only note that a recipe could make it for less
						if candidate < current * (1 - TOLERANCE) and (below[out] == nil or candidate < below[out]) then
							below[out] = candidate
						end
					elseif current == nil or candidate < current * (1 - TOLERANCE) then
						prices[out] = candidate
						source[out] = recipe.type
						flags[out] = union(own[out], inherited)
						unstable[out] = true
						any = true
					end
				end
			end
		end
		if not any then return prices, source, flags, nil, below end
	end
	return prices, source, flags, unstable, below
end

return function(opts)
	local excluded, dropped = {}, {}
	local prices, source, flags, unstable, below
	for _ = 1, MAX_ATTEMPTS do
		prices, source, flags, unstable, below = relax(opts, excluded)
		if not unstable then break end
		for name in pairs(unstable) do
			if not excluded[name] then
				excluded[name] = true
				dropped[#dropped + 1] = name
			end
		end
	end
	if unstable then
		-- Still not settled after dropping loops: price only what is certain.
		prices, source, flags, _, below = relax(opts, setmetatable({}, { __index = function() return true end }))
	end
	table.sort(dropped)
	return prices, source, dropped, flags, below
end
