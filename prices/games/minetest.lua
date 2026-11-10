-- Base prices for Minetest Game (game id "minetest"), in price units.
-- 1 unit = the value of one cobblestone. Items not listed here are priced
-- from their recipes, or have no price.

return {
	-- Anchors: these only make each other (cobble <-> stone, block <-> lump,
	-- block <-> slabs), so a recipe cannot price them.
	["default:cobble"] = 1,
	["default:coal_lump"] = 8,
	["default:mese_crystal"] = 100,
	["default:diamond"] = 150,
	["default:mossycobble"] = 1,
	["default:desert_cobble"] = 1,
	["default:desert_sandstone"] = 2,

	-- Earth
	["default:dirt"] = 1,
	["default:sand"] = 1,
	["default:desert_sand"] = 1,
	["default:silver_sand"] = 1,
	["default:gravel"] = 1,
	["default:clay_lump"] = 2,
	["default:snow"] = 1,
	["default:ice"] = 3,
	["default:flint"] = 2,
	["default:obsidian"] = 25,

	-- Wood (logs)
	["default:tree"] = 4,
	["default:jungletree"] = 4,
	["default:pine_tree"] = 4,
	["default:acacia_tree"] = 4,
	["default:aspen_tree"] = 4,

	-- Plants
	["default:cactus"] = 2,
	["default:papyrus"] = 2,
	["farming:wheat"] = 3,
	["farming:cotton"] = 3,

	-- Ore lumps (ingots are priced from these by smelting)
	["default:copper_lump"] = 12,
	["default:tin_lump"] = 12,
	["default:iron_lump"] = 16,
	["default:gold_lump"] = 40,
}
