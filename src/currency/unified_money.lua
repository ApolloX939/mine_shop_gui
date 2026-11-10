-- Adapter for Unified Money (um_core + one backend).
-- Only the public `unified_money.*` API is used.

local adapter = { name = "unified_money" }

local function um()
	return rawget(_G, "unified_money")
end

function adapter.available()
	local u = um()
	return type(u) == "table"
		and type(u.get_balance_safe) == "function"
		and type(u.del_balance) == "function"
		and type(u.add_balance_safe) == "function"
end

function adapter.round(amount)
	return amount
end

function adapter.balance(player)
	return um().get_balance_safe(player)
end

function adapter.withdraw(player, amount)
	local api = mine_shop_gui.currency
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount == 0 then return true end
	if um().get_balance_safe(player) < amount then
		return false, "insufficient_funds"
	end
	if not um().del_balance(player, amount) then
		return false, "unavailable"
	end
	return true
end

function adapter.deposit(player, amount)
	local api = mine_shop_gui.currency
	if not api.valid_amount(amount) then return false, "invalid_amount" end
	if amount == 0 then return true end
	if not um().add_balance_safe(player, amount) then
		return false, "unavailable"
	end
	return true
end

function adapter.format(amount)
	return tostring(amount)
end

mine_shop_gui.currency.register(adapter)
