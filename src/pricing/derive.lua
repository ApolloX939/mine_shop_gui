-- Derives item prices from base prices and recipes.
--
-- derive{
--   base    = { ["mod:item"] = units },       fixed prices; never overridden
--   recipes = { { type = "alloy",
--                 inputs = { {name = "mod:a", count = 2}, {group = "wood", count = 1} },
--                 output = { name = "mod:b", count = 3 } }, ... },   single-output only
--   groups  = { wood = { "mod:a", "mod:b" } },   members of each group used by recipes
--   markup  = function(recipe_type) return 0.1 end,   optional, fraction added on top
-- }
-- returns prices, source, dropped
--   prices   item -> price units
--   source   item -> "base" or the recipe type that gave the price
--   dropped  list of items whose price could not settle (see below)
--
-- Each item gets the cheapest cost over all its recipes, found by relaxing
-- prices repeatedly until nothing gets cheaper. That makes cycles harmless
-- (block <-> ingots just stops improving). A recipe that can duplicate value
-- (for example 1 a -> 2 a) never settles; items in such a loop lose their
-- derived price and are reported in `dropped`.
-- A group ingredient costs as much as its cheapest priced member.

local MAX_PASSES = 200
local MAX_ATTEMPTS = 5
local TOLERANCE = 1e-9

local function relax(opts, excluded)
	local prices, source = {}, {}
	for name, price in pairs(opts.base) do
		prices[name] = price
		source[name] = "base"
	end
	local groups = opts.groups or {}

	local function input_price(input)
		if input.group then
			local best
			for _, member in ipairs(groups[input.group] or {}) do
				local price = prices[member]
				if price and (not best or price < best) then best = price end
			end
			return best
		end
		return prices[input.name]
	end

	local unstable
	for _ = 1, MAX_PASSES do
		unstable = {}
		local any = false
		for _, recipe in ipairs(opts.recipes) do
			local out = recipe.output.name
			if source[out] ~= "base" and not excluded[out] then
				local cost, complete = 0, true
				for _, input in ipairs(recipe.inputs) do
					local price = input_price(input)
					if not price then complete = false break end
					cost = cost + price * (input.count or 1)
				end
				if complete then
					local markup = opts.markup and opts.markup(recipe.type) or 0
					local candidate = cost * (1 + markup) / (recipe.output.count or 1)
					local current = prices[out]
					if current == nil or candidate < current * (1 - TOLERANCE) then
						prices[out] = candidate
						source[out] = recipe.type
						unstable[out] = true
						any = true
					end
				end
			end
		end
		if not any then return prices, source, nil end
	end
	return prices, source, unstable
end

return function(opts)
	local excluded, dropped = {}, {}
	local prices, source, unstable
	for _ = 1, MAX_ATTEMPTS do
		prices, source, unstable = relax(opts, excluded)
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
		prices, source = relax(opts, setmetatable({}, { __index = function() return true end }))
	end
	table.sort(dropped)
	return prices, source, dropped
end
