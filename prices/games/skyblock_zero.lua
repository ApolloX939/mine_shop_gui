-- Base prices for Skyblock: Zero (game id "skyblock_zero"), in price units.
-- 1 unit = the value of one cobblestone, so the cheapest dust (matter dust)
-- is worth a few units. Items not listed here are priced from their recipes
-- (crafting and the machines: crushing, compressing, centrifuging, ...), or
-- have no price.
--
-- The raw values follow the hand-set values of the emc mod.

return {
	-- Dusts, the starting resources
	["sbz_resources:matter_dust"] = 5,
	["sbz_resources:charged_particle"] = 3,
	["sbz_resources:core_dust"] = 10,
	["sbz_resources:strange_dust"] = 98,
	["sbz_resources:raw_emittrium"] = 16,
	["sbz_resources:phlogiston"] = 1024,
	["sbz_resources:red_sand"] = 125,
	["sbz_resources:movable_emitter"] = 1000,

	-- Planets and meteorites
	["sbz_planets:snowball"] = 6,
	["sbz_planets:dead_core"] = 126,
	["sbz_meteorites:neutronium"] = 603,

	-- Plants
	["sbz_bio:fiberweed"] = 20,
	["sbz_bio:stemfruit"] = 20,
	["sbz_bio:pyrograss"] = 30,
	["sbz_bio:razorgrass"] = 50,
	["sbz_bio:algae"] = 12,
	["sbz_bio:cleargrass"] = 45,
	["sbz_bio:colorium_tree"] = 16,
	["sbz_bio:shockshroom"] = 32,
	["sbz_bio:warpshroom"] = 64,
	["sbz_bio:colorium_emitter"] = 1000,

	-- Fluid
	["sbz_chem:water_fluid_cell"] = 5,

	-- Loop anchors: made from each other, so a recipe cannot price them.
	["sbz_bio:moss"] = { price = 6, fixed = true }, -- 9 moss make 1 dirt, 1 dirt makes 3 moss
	["sbz_planets:dwarf_orb"] = 153,
}
