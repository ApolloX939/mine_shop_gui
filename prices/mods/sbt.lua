-- Base prices for Skyblock: Two (sbt), in price units (1 = one cobblestone).
-- The values follow the hand-set values of the emc mod. Everything made by a
-- recipe or a machine is priced from its ingredients; only raw materials are
-- listed here.

return {
	-- Minerals and raw materials
	["sbt:calcite"] = 13,
	["sbt:grimstone"] = 12,
	["sbt:extrosim_crystal"] = 32,
	["sbt:resium_crystal"] = 64,
	["sbt:atlantideum_shard"] = 128,
	["sbt:vexinite"] = 34,
	["sbt:enhanced_stone"] = 252,
	["sbt:emmitrex_plate"] = 860,
	["sbt:colorium_circuit"] = 28,
	["sbt:creox_fab_cube"] = 13000,
	["sbt:diamond"] = 150,
	["sbt:oil"] = 30,

	-- Plants of the sbt worlds
	["sbt:core_wart"] = 28,
	["sbt:electrograss"] = 32,
	["sbt:weed"] = 1,
	["sbt:kiwi_vine"] = 2,
	["sbt:kiwi_leaves"] = 15,
	["sbt:kiwi_sapling"] = 16,
	["sbt:kiwi"] = 4,
	["ethereal:bananaleaves"] = 15,

	-- Animals and their products
	["sbt:egg"] = 15,
	["sbt:floxite_feather"] = 9,
	["sbt:floxite_raw"] = 15,
	["sbt:jogbin_raw"] = 21,
	["sbt:unopian_raw"] = 12,
	["sbt:hexenith_raw"] = 28,
	["sbt:meat_raw"] = 14,
	["sbt:hexenith_hide"] = 3,
	["sbt:bucket_milk"] = 16,
	["sbt:fish"] = 18,
	["sbt:hairball"] = 12,
	["sbt:saddle"] = 316,
	["sbt:plesoic"] = 17,
	["sbt:trexare"] = 5,
	["sbt:athrosoto"] = 12,
	["sbt:nutra_paste"] = 1,

	-- Crops and kitchen ingredients: priced one by one, since a recipe can name
	-- any member of a food group
	["sbt:sugar_cube"] = 9,
	["sbt:artichoke"] = 32,
	["sbt:asparagus"] = 5,
	["sbt:barley"] = 14,
	["sbt:oat"] = 15,
	["sbt:rye"] = 11,
	["sbt:beans"] = 7,
	["sbt:beetroot"] = 5,
	["sbt:blackberry"] = 4,
	["sbt:blueberries"] = 5,
	["sbt:raspberries"] = 4,
	["sbt:strawberry"] = 4,
	["sbt:cabbage"] = 8,
	["sbt:carrot"] = 10,
	["sbt:chili_pepper"] = 4,
	["sbt:cocoa_beans_raw"] = 10,
	["sbt:coffee_beans"] = 2,
	["sbt:corn"] = 26,
	["sbt:cucumber"] = 15,
	["sbt:eggplant"] = 24,
	["sbt:ginger"] = 3,
	["sbt:grapes"] = 8,
	["sbt:lettuce"] = 4,
	["sbt:mint_leaf"] = 4,
	["sbt:onion"] = 6,
	["sbt:parsley"] = 1,
	["sbt:pea_pod"] = 7,
	["sbt:pepper"] = 14,
	["sbt:pepper_red"] = 14,
	["sbt:pepper_yellow"] = 14,
	["sbt:pineapple"] = 20,
	["sbt:potato"] = 1,
	["sbt:rhubarb"] = 4,
	["sbt:soy_pod"] = 15,
	["sbt:spinach"] = 5,
	["sbt:tomato"] = 13,
	["sbt:vanilla"] = 10,
	["sbt:hemp_leaf"] = 4,
	["sbt:sunflower"] = 6,
	["sbt:salt_crystal"] = 12,

	-- Seeds
	["sbt:seed_barley"] = 1,
	["sbt:seed_cotton"] = 1,
	["sbt:seed_hemp"] = 1,
	["sbt:seed_mint"] = 1,
	["sbt:seed_oat"] = 1,
	["sbt:seed_rice"] = 6,
	["sbt:seed_rye"] = 1,
	["sbt:seed_wheat"] = 1,

	-- Kitchen tools. A recipe hands them back, so they are priced cheaply
	-- instead of adding their whole cost to every dish.
	["sbt:mortar_pestle"] = { price = 6, fixed = true },
	["sbt:cutting_board"] = { price = 4, fixed = true },
	["sbt:baking_tray"] = { price = 4, fixed = true },
	["sbt:mutator"] = { price = 30, fixed = true },

	-- Machine parts that no recipe the shop can read makes (priced by hand)
	["sbt:cable"] = 5,
	["sbt:upgrade_base"] = 40,
	["sbt:case"] = 20,
	["sbt:motherboard"] = 60,
	["sbt:psu"] = 40,
	["sbt:extrex_drill"] = 300,
	["sbt:emmitrex_drill"] = 400,
	["sbt:diamond_drill"] = 600,
	["sbt:alloy537_rebreather"] = 300,

	-- Loop anchors: these items are made from each other, so a recipe cannot
	-- price them. Each is set to the cost of its ingredients.
	["sbt:wheat"] = 14,
	["sbt:straw"] = { price = 42, fixed = true }, -- 9 wheat make 3 straw
	["sbt:honey"] = 12,
	["sbt:honey_block"] = { price = 108, fixed = true }, -- 9 honey
	["sbt:garlic_clove"] = 2,
	["sbt:garlic"] = { price = 16, fixed = true }, -- 8 cloves
	["sbt:melon_slice"] = 3,
	["sbt:melon_8"] = { price = 12, fixed = true }, -- 4 slices
	["sbt:pumpkin_slice"] = 3,
	["sbt:pumpkin_8"] = { price = 12, fixed = true }, -- 4 slices
}
