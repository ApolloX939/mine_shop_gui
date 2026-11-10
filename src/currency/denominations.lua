-- Builds an adapter for currencies that are plain items in the player's
-- inventory, each with a fixed value (coins, notes, emeralds, ...).
--
-- def = {
--   name = "adapter name",
--   get_denominations = function() return { {name = "mod:item", value = 5}, ... } end,
--   format = function(amount) return "..." end,    -- optional
--   default_scale = 5,                             -- currency amount per price unit
--   icon = "mod:item",                             -- optional: picture for the currency
--                                                  (default: the smallest denomination)
--   symbol = "$", symbol_first = true,             -- optional: short mark for text
--   number = function(amount) return "..." end,   -- optional: amount without any currency name
--   warn_missing = true,                           -- optional: log denominations whose item is not registered
-- }
--
-- Paying works by removing all of the player's money, then handing back the
-- change. The inventory is restored if the change does not fit.
-- Change is made greedily, largest denomination first, which gives exact
-- change for the usual coin/note systems. If a denomination set cannot make an
-- exact amount, the operation fails instead of losing anything.

local api = mine_shop_gui.currency

local function gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

local M = {}

function M.new(def)
	local self = { name = def.name }
	local cache

	-- Resolved lazily: items only exist once every mod has loaded.
	local function resolved()
		if cache then return cache end
		local list, values, unit = {}, {}, 0
		for _, d in ipairs(def.get_denominations()) do
			if core.registered_items[d.name]
					and d.value > 0 and d.value == math.floor(d.value) then
				list[#list + 1] = d
				values[d.name] = d.value
				unit = gcd(unit, d.value)
			elseif def.warn_missing then
				core.log("warning", "[mine_shop_gui] currency '" .. def.name
					.. "': ignoring unknown item '" .. d.name .. "'")
			end
		end
		table.sort(list, function(a, b) return a.value > b.value end)
		cache = { list = list, values = values, unit = unit }
		return cache
	end

	local function get_inventory(player)
		local obj = core.get_player_by_name(player)
		return obj and obj:get_inventory()
	end

	local function total_in(inv)
		local values, total = resolved().values, 0
		for _, stack in ipairs(inv:get_list("main")) do
			local value = values[stack:get_name()]
			if value then
				total = total + value * stack:get_count()
			end
		end
		return total
	end

	-- Remove every money stack and return how much it was worth.
	local function take_all(inv)
		local values, total = resolved().values, 0
		local list = inv:get_list("main")
		for i, stack in ipairs(list) do
			local value = values[stack:get_name()]
			if value then
				total = total + value * stack:get_count()
				list[i] = ItemStack()
			end
		end
		inv:set_list("main", list)
		return total
	end

	-- Add `amount` worth of money as change. Returns true, or false + reason.
	local function give(inv, amount)
		for _, d in ipairs(resolved().list) do
			local count = math.floor(amount / d.value)
			amount = amount - count * d.value
			local max = core.registered_items[d.name].stack_max or 99
			while count > 0 do
				local n = math.min(count, max)
				local leftover = inv:add_item("main", ItemStack({ name = d.name, count = n }))
				if not leftover:is_empty() then
					return false, "no_room"
				end
				count = count - n
			end
		end
		if amount ~= 0 then
			return false, "invalid_amount"
		end
		return true
	end

	function self.available()
		return #resolved().list > 0
	end

	self.default_scale = def.default_scale

	function self.unit()
		return resolved().unit
	end

	function self.round(amount)
		local unit = resolved().unit
		if unit == 0 then return amount end
		return math.floor(amount / unit + 0.5) * unit
	end

	function self.snapshot(player)
		local inv = get_inventory(player)
		return inv and inv:get_list("main")
	end

	function self.restore(player, snapshot)
		local inv = get_inventory(player)
		if inv then inv:set_list("main", snapshot) end
	end

	function self.balance(player)
		local inv = get_inventory(player)
		if not inv then return nil end
		return total_in(inv)
	end

	function self.withdraw(player, amount)
		if not api.valid_amount(amount) or self.round(amount) ~= amount then
			return false, "invalid_amount"
		end
		if amount == 0 then return true end
		local inv = get_inventory(player)
		if not inv then return false, "unavailable" end
		if total_in(inv) < amount then return false, "insufficient_funds" end

		local snapshot = inv:get_list("main")
		local total = take_all(inv)
		local ok, reason = give(inv, total - amount)
		if not ok then
			inv:set_list("main", snapshot)
			return false, reason
		end
		return true
	end

	function self.deposit(player, amount)
		if not api.valid_amount(amount) or self.round(amount) ~= amount then
			return false, "invalid_amount"
		end
		if amount == 0 then return true end
		local inv = get_inventory(player)
		if not inv then return false, "unavailable" end

		local snapshot = inv:get_list("main")
		local ok, reason = give(inv, amount)
		if not ok then
			inv:set_list("main", snapshot)
			return false, reason
		end
		return true
	end

	self.format = def.format or function(amount) return tostring(amount) end
	self.number = def.number or self.format

	function self.icon()
		if def.icon then return def.icon end
		local list = resolved().list
		return list[#list] and list[#list].name -- sorted largest first, so this is the smallest
	end

	function self.format_symbol(amount)
		local number = self.number(amount)
		if not def.symbol or def.symbol == "" then return self.format(amount) end
		if def.symbol_first then return def.symbol .. number end
		return number .. " " .. def.symbol
	end

	return self
end

mine_shop_gui.currency_denominations = M
