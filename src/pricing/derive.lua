-- Derives item prices from base prices and recipes.
--
-- derive{
--   base    = { ["mod:item"] = 4, ["mod:other"] = { price = 1, fixed = true } },
--             a plain number is a ceiling: a recipe may make the item cheaper and
--             then lowers it. `fixed = true` keeps the price whatever recipes say.
--   recipes = { { type = "alloy",
--                 inputs = { {name = "mod:a", count = 2}, {group = "wood", count = 1} },
--                 output = { name = "mod:b", count = 3 } }, ... },   single-output only
--   groups  = { wood = { "mod:a", "mod:b" } },   members of each group used by recipes
--   markup  = function(recipe_type) return 0.1 end,   optional, fraction added on top
--   flags   = { ["mod:item"] = { no_buy = true, no_sell = true } },   the items' own flags
--   trace   = function(message) end,   optional, told what each loop cut did
-- }
-- returns prices, source, dropped, flags, below_base, lowered, held_below
--   prices   item -> price units
--   source   item -> "base" or the recipe type that gave the price
--   dropped  list of items left without a price because their recipes loop
--   flags    item -> { no_buy = true, no_sell = true } (only items that have any)
--   below_base  item -> cheapest recipe cost, for FIXED base prices that a recipe
--            could undercut. The fixed price still applies; this only reports.
--   lowered  item -> the base price it started from, for base prices that a
--            recipe lowered
--   held_below  item -> cheapest recipe cost, for items held at a price inside a
--            gaining loop although a recipe could make them for less
--
-- Each item gets the cheapest cost over all its recipes, found by relaxing
-- prices repeatedly until nothing gets cheaper. That makes harmless cycles
-- (block <-> ingots) settle by themselves.
--
-- A loop that gains value (for example 2 sand -> 1 sandstone, but 1 sandstone ->
-- 4 sand) never settles, so it is cut:
--   * a member with a base price is held at that price;
--   * otherwise every member is held at the price its routes from OUTSIDE the
--     loop give it, ignoring the recipes that run round the loop;
--   * a member with no outside route stays unpriced (reported in `dropped`).
-- Items merely downstream of a loop are not affected.
-- A group ingredient costs as much as its cheapest priced member.
--
-- Flags are inherited: a derived item gets its own flags plus the flags of every
-- ingredient of the recipe that set its price (for a group ingredient, the
-- member that was used). The item is still priced.

local MAX_PASSES = 200
local MAX_ATTEMPTS = 25
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

-- One relaxation. `held` holds items at a given price, `excluded` removes the
-- recipes that make an item, `skip` removes individual recipes.
local function relax(opts, held, excluded, skip)
	local prices, source, flags, below, lowered, held_below = {}, {}, {}, {}, {}, {}
	local original, fixed = {}, {}
	local own = opts.flags or {}
	for name, entry in pairs(opts.base) do
		local price, is_fixed = entry, false
		if type(entry) == "table" then
			price, is_fixed = entry.price, entry.fixed and true or false
		end
		prices[name] = price
		source[name] = "base"
		original[name] = price
		fixed[name] = is_fixed
		flags[name] = union(own[name])
	end
	for name, h in pairs(held) do
		prices[name], source[name], flags[name] = h.price, h.source, h.flags
		original[name], fixed[name] = nil, true
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
			if not excluded[out] and not (skip and skip[recipe]) then
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
					if fixed[out] then
						-- a fixed price: only note that a recipe could make it for less
						local report = held[out] and held_below or below
						if candidate < current * (1 - TOLERANCE) and (report[out] == nil or candidate < report[out]) then
							report[out] = candidate
						end
					elseif current == nil or candidate < current * (1 - TOLERANCE) then
						if original[out] ~= nil then lowered[out] = original[out] end
						prices[out] = candidate
						source[out] = recipe.type
						flags[out] = union(own[out], inherited)
						unstable[out] = true
						any = true
					end
				end
			end
		end
		if not any then return prices, source, flags, nil, below, lowered, held_below end
	end
	return prices, source, flags, unstable, below, lowered, held_below
end

-- The strongly connected groups of `set` (items that depend on each other
-- through recipes, so a price change can travel round and round). Each group
-- is a list of item names; a lone item only counts if it feeds itself.
-- Loops that something else in `set` feeds into are only moving because that
-- other loop has not settled, so they are returned separately as `downstream`.
local function cycles_in(opts, set)
	local groups = opts.groups or {}
	local edges = {}
	for _, recipe in ipairs(opts.recipes) do
		local out = recipe.output.name
		if set[out] then
			for _, input in ipairs(recipe.inputs) do
				local sources = input.name and { input.name } or groups[input.group] or {}
				for _, source in ipairs(sources) do
					if set[source] then
						edges[source] = edges[source] or {}
						edges[source][out] = true
					end
				end
			end
		end
	end

	local counter, stack, on_stack, index, low, found = 0, {}, {}, {}, {}, {}
	local function visit(v)
		counter = counter + 1
		index[v], low[v] = counter, counter
		stack[#stack + 1] = v
		on_stack[v] = true
		for w in pairs(edges[v] or {}) do
			if not index[w] then
				visit(w)
				low[v] = math.min(low[v], low[w])
			elseif on_stack[w] then
				low[v] = math.min(low[v], index[w])
			end
		end
		if low[v] == index[v] then
			local group = {}
			repeat
				local w = table.remove(stack)
				on_stack[w] = nil
				group[#group + 1] = w
			until w == v
			if #group > 1 or (edges[v] and edges[v][v]) then
				table.sort(group)
				found[#found + 1] = group
			end
		end
	end

	local names = {}
	for name in pairs(set) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		if not index[name] then visit(name) end
	end

	local group_of = {}
	for g, group in ipairs(found) do
		for _, name in ipairs(group) do group_of[name] = g end
	end
	local upstream, downstream = {}, {}
	for g, group in ipairs(found) do
		local fed = false
		for from, targets in pairs(edges) do
			if group_of[from] ~= g then
				for _, name in ipairs(group) do
					if targets[name] then fed = true end
				end
			end
		end
		if fed then downstream[#downstream + 1] = group else upstream[#upstream + 1] = group end
	end
	return upstream, downstream
end

-- Recipes that make a member of `group` out of another member of it.
local function round_the_loop(opts, group)
	local members, result = {}, {}
	for _, name in ipairs(group) do members[name] = true end
	local groups = opts.groups or {}
	for _, recipe in ipairs(opts.recipes) do
		if members[recipe.output.name] then
			for _, input in ipairs(recipe.inputs) do
				local sources = input.name and { input.name } or groups[input.group] or {}
				for _, source in ipairs(sources) do
					if members[source] then result[recipe] = true end
				end
			end
		end
	end
	return result
end

local function base_price(opts, name)
	local entry = opts.base[name]
	return type(entry) == "table" and entry.price or entry
end

return function(opts)
	local held, excluded, dropped = {}, {}, {}
	local prices, source, flags, unstable, below, lowered, held_below
	for _ = 1, MAX_ATTEMPTS do
		prices, source, flags, unstable, below, lowered, held_below = relax(opts, held, excluded)
		if not unstable then break end

		local cut = false
		local count = 0
		for _ in pairs(unstable) do count = count + 1 end
		if opts.trace then opts.trace(count .. " prices still moving after " .. MAX_PASSES .. " passes") end
		local upstream, downstream = cycles_in(opts, unstable)
		-- Only cut loops that nothing unstable feeds into; the ones below them
		-- settle once these are cut. (If none qualify, cut them all.)
		if #upstream == 0 then upstream = downstream end
		for _, group in ipairs(upstream) do
			if opts.trace then
				opts.trace("loop of " .. #group .. " items: " .. table.concat(group, ", "):sub(1, 300))
			end
			local with_base = {}
			for _, name in ipairs(group) do
				if opts.base[name] ~= nil then with_base[#with_base + 1] = name end
			end
			if #with_base > 0 then
				-- cut at the base-priced members
				for _, name in ipairs(with_base) do
					if not held[name] then
						held[name] = { price = base_price(opts, name), source = "base",
							flags = union((opts.flags or {})[name]) }
						cut = true
					end
				end
			else
				-- price the members from the routes that do not run round the loop
				local entry_prices, entry_source, entry_flags =
					relax(opts, held, excluded, round_the_loop(opts, group))
				local any = false
				for _, name in ipairs(group) do
					if entry_prices[name] and not held[name] then
						held[name] = { price = entry_prices[name], source = entry_source[name],
							flags = entry_flags[name] }
						any, cut = true, true
					end
				end
				if not any then
					-- no outside route at all: leave the whole loop unpriced
					for _, name in ipairs(group) do
						if not excluded[name] then
							excluded[name] = true
							dropped[#dropped + 1] = name
							cut = true
						end
					end
				end
			end
		end
		if not cut then
			-- no loop found, so stop everything that is still moving
			for name in pairs(unstable) do
				if not excluded[name] then
					excluded[name] = true
					dropped[#dropped + 1] = name
				end
			end
		end
	end
	if unstable then
		-- Still not settled: keep only the base prices.
		prices, source, flags, _, below, lowered, held_below =
			relax(opts, {}, setmetatable({}, { __index = function() return true end }))
	end

	local really_dropped = {}
	for _, name in ipairs(dropped) do
		if prices[name] == nil then really_dropped[#really_dropped + 1] = name end
	end
	table.sort(really_dropped)
	return prices, source, really_dropped, flags, below, lowered, held_below
end
