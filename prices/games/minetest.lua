-- Base prices for Minetest Game (game id "minetest"), in price units.
-- 1 unit = the value of one cobblestone. Items not listed here are priced
-- from their recipes, or have no price.

return {
	-- Anchors: these only make each other (cobble <-> stone, block <-> lump,
	-- block <-> slabs), so a recipe cannot price them.
	["default:cobble"] = { price = 1, fixed = true }, -- the price unit itself
	["default:coal_lump"] = 8,
	["default:mese_crystal"] = 100,
	["default:diamond"] = 150,
	["default:mossycobble"] = 1,
	["default:desert_cobble"] = 1,
	["default:desert_sandstone"] = 4, -- 4 desert sand

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

	-- Leaves, saplings, flowers (dyes and many Ethereal recipes need these)
	["default:leaves"] = 1,
	["default:jungleleaves"] = 1,
	["default:pine_needles"] = 1,
	["default:aspen_leaves"] = 1,
	["default:acacia_leaves"] = 1,
	["default:bush_leaves"] = 1,
	["default:sapling"] = 3,
	["default:junglesapling"] = 3,
	["default:pine_sapling"] = 3,
	["default:aspen_sapling"] = 3,
	["default:acacia_sapling"] = 3,
	["flowers:rose"] = 1,
	["flowers:tulip"] = 1,
	["flowers:tulip_black"] = 1,
	["flowers:dandelion_yellow"] = 1,
	["flowers:dandelion_white"] = 1,
	["flowers:geranium"] = 1,
	["flowers:viola"] = 1,
	["flowers:chrysanthemum_green"] = 1,
	["flowers:mushroom_brown"] = 2,
	["flowers:mushroom_red"] = 2,
	["flowers:waterlily"] = 2,

	-- Bushes, grasses and soils
	["default:acacia_bush_leaves"] = 1,
	["default:blueberry_bush_leaves"] = 1,
	["default:blueberry_bush_leaves_with_berries"] = 2,
	["default:pine_bush_needles"] = 1,
	["default:acacia_bush_stem"] = 2,
	["default:bush_stem"] = 2,
	["default:pine_bush_stem"] = 2,
	["default:acacia_bush_sapling"] = 3,
	["default:blueberry_bush_sapling"] = 3,
	["default:bush_sapling"] = 3,
	["default:pine_bush_sapling"] = 3,
	["default:dry_grass_1"] = 1,
	["default:dry_shrub"] = 1,
	["default:fern_1"] = 1,
	["default:grass_1"] = 1,
	["default:junglegrass"] = 1,
	["default:marram_grass_1"] = 1,
	["default:sand_with_kelp"] = 1,
	["default:dirt_with_grass"] = 1,
	["default:dirt_with_dry_grass"] = 1,
	["default:dirt_with_coniferous_litter"] = 1,
	["default:dirt_with_rainforest_litter"] = 1,
	["default:dry_dirt"] = 1,
	["default:dry_dirt_with_dry_grass"] = 1,
	["default:permafrost"] = 1,
	["default:permafrost_with_moss"] = 1,
	["default:permafrost_with_stones"] = 1,

	-- Food and sea life
	["default:apple"] = 2,
	["default:blueberries"] = 2,
	["default:coral_brown"] = 2,
	["default:coral_cyan"] = 2,
	["default:coral_green"] = 2,
	["default:coral_orange"] = 2,
	["default:coral_pink"] = 2,
	["default:coral_skeleton"] = 2,

	-- Seeds and wild crops
	["farming:seed_wheat"] = 1,
	["farming:seed_cotton"] = 1,
	["farming:cotton_wild"] = 3,

	-- Caught with a net
	["butterflies:butterfly_red"] = 3,
	["butterflies:butterfly_violet"] = 3,
	["butterflies:butterfly_white"] = 3,
	["fireflies:firefly"] = 3,

	-- Filled buckets: an empty bucket (24) plus the contents
	["bucket:bucket_river_water"] = 27,
	["bucket:bucket_lava"] = 30,

	-- Ore lumps (ingots are priced from these by smelting)
	["default:copper_lump"] = 12,
	["default:tin_lump"] = 12,
	["default:iron_lump"] = 16,
	["default:gold_lump"] = 40,
}
