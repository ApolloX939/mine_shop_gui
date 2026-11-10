-- Builds the final price table and answers "can this be bought / sold?".
--
-- mine_shop_gui.pricing.items[name] = {
--   price   = units,                       price units (see api.price for currency amounts)
--   source  = "base" | recipe type | "hook",
--   no_buy  = boolean,                     the shop will not sell this item
--   no_sell = boolean,                     the shop will not buy this item
-- }
--
-- Steps: base price files -> collector (recipes, groups, flags) -> derivation
-- -> hooks registered with mine_shop_gui.register_on_prices_generated.

local P = mine_shop_gui.pricing
local collect = dofile(mine_shop_gui.modpath .. "/src/pricing/collect.lua")
P.collect = collect
P.items = {}
P.generated = false
P.hooks = {}

local function log(level, msg)
	core.log(level, "[mine_shop_gui] " .. msg)
end

-- Fraction added to the cost of items made with this recipe type, from the
-- setting mine_shop_gui_markup_<type> (a percentage, default 0).
function P.markup(recipe_type)
	local percent = tonumber(core.settings:get("mine_shop_gui_markup_" .. recipe_type)) or 0
	return math.max(0, percent) / 100
end

-- Check and clean the table after the hooks have had their way with it.
local function validate(items)
	local names = {}
	for name in pairs(items) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local entry = items[name]
		local reason
		if type(name) ~= "string" or not core.registered_items[collect.resolve(name)] then
			reason = "is not a registered item"
		elseif type(entry) ~= "table" then
			reason = "is not a table"
		elseif type(entry.price) ~= "number" or entry.price ~= entry.price
				or entry.price < 0 or entry.price == math.huge then
			reason = "has an invalid price"
		end
		if reason then
			log("warning", "dropping price entry '" .. tostring(name) .. "': it " .. reason)
			items[name] = nil
		else
			entry.no_buy = entry.no_buy and true or false
			entry.no_sell = entry.no_sell and true or false
			entry.source = entry.source or "hook"
		end
	end
end

local function run_hooks(items, hooks)
	for _, hook in ipairs(hooks) do
		local ok, err = pcall(hook, items)
		if not ok then
			log("error", "a prices-generated callback failed and was skipped: " .. tostring(err))
		end
	end
	validate(items)
end

-- Build the price table. Called once after all mods have loaded.
-- `opts` is for tests: base, recipes, groups, flags, hooks replace the real data.
function P.generate(opts)
	opts = opts or {}
	local base = opts.base or P.base_prices.load()
	local recipes = opts.recipes or collect.recipes()
	local groups = opts.groups or collect.groups(recipes)
	local own_flags = opts.flags or collect.item_flags()

	local prices, source, dropped, flags = P.derive({
		base = base,
		recipes = recipes,
		groups = groups,
		flags = own_flags,
		markup = P.markup,
	})

	local items = {}
	for name, price in pairs(prices) do
		local f = flags[name] or {}
		items[name] = {
			price = price,
			source = source[name],
			no_buy = f.no_buy or false,
			no_sell = f.no_sell or false,
		}
	end
	for _, name in ipairs(dropped) do
		log("warning", "no stable price for '" .. name .. "': its recipes create value in a loop")
	end

	run_hooks(items, opts.hooks or P.hooks)

	P.items = items
	P.generated = true
	local count = 0
	for _ in pairs(items) do count = count + 1 end
	log("action", "generated prices for " .. count .. " items")
	return items, { dropped = dropped }
end

-- Other mods call this while loading. The callback gets the whole table and
-- edits it in place: change prices, remove entries, add entries, set flags.
-- It runs after the collector, in registration order.
function mine_shop_gui.register_on_prices_generated(fn)
	assert(type(fn) == "function", "register_on_prices_generated needs a function")
	P.hooks[#P.hooks + 1] = fn
	if P.generated then
		log("warning", "a prices-generated callback was registered after the prices were built; running it now")
		run_hooks(P.items, { fn })
	end
end

function P.get(name)
	return P.items[collect.resolve(name)]
end

function P.can_buy(name)
	local entry = P.get(name)
	return entry ~= nil and not entry.no_buy
end

-- `stack` is an ItemStack. Its own metadata can also forbid the sale.
function P.can_sell(stack)
	local entry = P.get(stack:get_name())
	if entry == nil or entry.no_sell then return false end
	return not collect.stack_flags(stack).no_sell
end
