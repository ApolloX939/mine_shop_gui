-- Base prices for Techage, in price units. 1 unit = the value of one cobblestone.
-- Items not listed are priced from their recipes, or have no price.
--
-- Techage's electronic fabricators and doser are read from Techage itself, so the
-- chips, LEDs, vacuum tubes and SSDs are priced from their parts and are not listed
-- here. Its furnace, melting pot, grinder and mill are only readable through
-- unified_inventory, so the items they make keep a price here (the values match
-- what those recipes give) and still work on servers without that mod. The rest
-- are made by machines without any readable recipe: judgment calls, climbing
-- with the tech tier.
--
-- Deliberately unpriced (not meant to be traded): admin and test blocks (item
-- source, sink, test block, power sources, water stop), oil sources, ore nodes,
-- the three gravel sieve machines, and filled barrels, canisters and cylinders
-- other than the four listed below.

return {
	-- Anchors: only made inside a Techage machine, or by uncrafting blocks, slabs and stairs
	["techage:iron_ingot"] = 16,
	["techage:basalt_cobble"] = 1,
	["techage:red_stone"] = 2,
	["techage:bauxite_cobble"] = 1,
	["techage:basalt_glass"] = 4,
	["techage:basalt_glass2"] = 4,
	["techage:sieved_basalt_gravel"] = 1,

	-- Natural resources
	["techage:baborium_lump"] = 40,
	["techage:usmium_nuggets"] = 60,
	["techage:usmium_powder"] = 60,
	["techage:bauxite_gravel"] = 3,
	["techage:bauxite_powder"] = 3,
	["techage:gibbsite_powder"] = 4,
	["techage:basalt_gravel"] = 1,
	["techage:sieved_gravel"] = 2,
	["techage:redmud"] = 2,

	-- TA1: powders and basics
	["techage:charcoal"] = 2,
	["techage:iron_powder"] = 16,
	["techage:clay_powder"] = 1,
	["techage:cement_powder"] = 1,
	["techage:graphite_powder"] = 8,
	["techage:leave_powder"] = 1,
	["techage:needle_powder"] = 1,
	["techage:silver_sandstone_powder"] = 1,

	-- TA2/TA3: metals, glass and chemistry
	["techage:aluminum"] = 24,
	["techage:aluminum_powder"] = 24,
	["techage:basalt_glass_thin"] = 6,
	["techage:basalt_glass_thin2"] = 6,
	["techage:basalt_glass_thin_xl"] = 10,
	["techage:basalt_glass_thin_xl2"] = 10,
	["techage:lye"] = 4,
	["techage:epoxy"] = 10,
	["techage:plastic_granules"] = 6,
	["techage:bitumen"] = 6,
	["techage:fueloil"] = 6,
	["techage:naphtha"] = 6,
	["techage:gasoline"] = 8,
	["techage:gas"] = 8,
	["techage:bucket_oil"] = 12,
	["techage:ammonia"] = 6,
	["techage:hydrogen"] = 6,
	["techage:nitrogen"] = 4,
	["techage:isobutane"] = 10,

	-- Filled containers that recipes need (all others stay unpriced)
	["techage:canister_epoxy"] = 12,
	["techage:canister_lye"] = 10,
	["techage:cylinder_large_hydrogen"] = 40,
	["techage:ta3_barrel_bitumen"] = 20,

	-- TA3: electronics (the vacuum tube is priced from its recipe)
	["techage:wlanchip"] = 30,
	["techage:ta3_logic"] = 20,

	-- TA4: silicon, carbon and ceramics (the chips and LEDs are priced from their recipes)
	["techage:ta4_silicon_wafer"] = 3,
	["techage:ta4_carbon_fiber"] = 5,
	["techage:ta4_furnace_ceramic"] = 10,
	["techage:ta4_round_ceramic"] = 10,

	-- TA5: fusion age (the AI chips and SSD are priced from their recipes)
	["techage:ta5_controlunit"] = 150,
	["techage:ta5_ceramic_turbine"] = 120,
	["techage:ta5_fr_shell"] = 200,
	["techage:ta5_magnet_shield"] = 38,
}
