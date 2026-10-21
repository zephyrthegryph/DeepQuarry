/datum/material/plastic
	name = MAT_PLASTIC
	stack_type = /obj/item/stack/material/plastic
	flags = MATERIAL_BRITTLE
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#CCCCCC"
	hardness = 10
	density = 12
	protectiveness = 5 // 20%
	conductive = 0
	conductivity = 2 // For the sake of material armor diversity, we're gonna pretend this plastic is a good insulator.
	melting_point = T0C+371 //assuming heat resistant plastic
	supply_conversion_value = 0.5

/datum/material/cardboard
	name = MAT_CARDBOARD
	stack_type = /obj/item/stack/material/cardboard
	flags = MATERIAL_BRITTLE
	integrity = 10
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#AAAAAA"
	hardness = 1
	density = 1
	protectiveness = 0 // 0%
	conductive = 0
	ignition_point = T0C+232 //"the temperature at which book-paper catches fire, and burns." close enough
	melting_point = T0C+232 //temperature at which cardboard walls would be destroyed
	door_icon_base = "wood"
	destruction_desc = "crumples"
	radiation_resistance = 1
	pass_stack_colors = TRUE
	supply_conversion_value = 0.05

/transformation/stack/cardboard__box
CAPABILITIES(/transformation/stack/cardboard__box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/storage/box, 1)),
		chosen = chosen(title = "box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__donut_box
CAPABILITIES(/transformation/stack/cardboard__donut_box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/storage/box/donut/empty, 1)),
		chosen = chosen(title = "donut box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__egg_box
CAPABILITIES(/transformation/stack/cardboard__egg_box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/storage/fancy/egg_box, 1)),
		chosen = chosen(title = "egg box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__light_tubes_box
CAPABILITIES(/transformation/stack/cardboard__light_tubes_box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/storage/box/lights/tubes, 1)),
		chosen = chosen(title = "light tubes box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__light_bulbs_box
CAPABILITIES(/transformation/stack/cardboard__light_bulbs_box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/storage/box/lights/bulbs, 1)),
		chosen = chosen(title = "light bulbs box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__mouse_traps_box
CAPABILITIES(/transformation/stack/cardboard__mouse_traps_box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/storage/box/mousetraps, 1)),
		chosen = chosen(title = "mouse traps box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__cardborg_suit
CAPABILITIES(/transformation/stack/cardboard__cardborg_suit)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/suit/cardborg, 1)),
		chosen = chosen(title = "cardborg suit",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__cardborg_helmet
CAPABILITIES(/transformation/stack/cardboard__cardborg_helmet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/head/cardborg, 1)),
		chosen = chosen(title = "cardborg helmet",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__pizza_box
CAPABILITIES(/transformation/stack/cardboard__pizza_box)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/pizzabox, 1)),
		chosen = chosen(title = "pizza box",
			subject = /datum/material/cardboard,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/cardboard__blue_folder
CAPABILITIES(/transformation/stack/cardboard__blue_folder)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/folder/blue, 1)),
		chosen = chosen(title = "blue folder",
			subject = /datum/material/cardboard,
			recycle = STACK_MATERIAL_SELF,
			group = "folders")))

/transformation/stack/cardboard__grey_folder
CAPABILITIES(/transformation/stack/cardboard__grey_folder)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/folder, 1)),
		chosen = chosen(title = "grey folder",
			subject = /datum/material/cardboard,
			recycle = STACK_MATERIAL_SELF,
			group = "folders")))

/transformation/stack/cardboard__red_folder
CAPABILITIES(/transformation/stack/cardboard__red_folder)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/folder/red, 1)),
		chosen = chosen(title = "red folder",
			subject = /datum/material/cardboard,
			recycle = STACK_MATERIAL_SELF,
			group = "folders")))

/transformation/stack/cardboard__white_folder
CAPABILITIES(/transformation/stack/cardboard__white_folder)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/folder/white, 1)),
		chosen = chosen(title = "white folder",
			subject = /datum/material/cardboard,
			recycle = STACK_MATERIAL_SELF,
			group = "folders")))

/transformation/stack/cardboard__yellow_folder
CAPABILITIES(/transformation/stack/cardboard__yellow_folder)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/folder/yellow, 1)),
		chosen = chosen(title = "yellow folder",
			subject = /datum/material/cardboard,
			recycle = STACK_MATERIAL_SELF,
			group = "folders")))

/datum/material/toy_foam
	name = MAT_FOAM
	display_name = MAT_FOAM
	use_name = MAT_FOAM
	flags = MATERIAL_PADDING
	ignition_point = T0C+232
	melting_point = T0C+300
	icon_colour = "#ff9900"
	hardness = 1
	density = 1
	protectiveness = 0 // 0%
	conductive = 0
	can_sharpen = FALSE
	supply_conversion_value = 0


/transformation/stack/plastic__plastic_crate
CAPABILITIES(/transformation/stack/plastic__plastic_crate)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/structure/closet/crate/plastic, 1)),
		chosen = chosen(title = "plastic crate",
			subject = /datum/material/plastic,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__plastic_bag
CAPABILITIES(/transformation/stack/plastic__plastic_bag)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/storage/bag/plasticbag, 1)),
		chosen = chosen(title = "plastic bag",
			subject = /datum/material/plastic,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__blood_pack
CAPABILITIES(/transformation/stack/plastic__blood_pack)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/reagent_containers/blood/empty, 1)),
		chosen = chosen(title = "blood pack",
			subject = /datum/material/plastic,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__reagent_dispenser_cartridge_large
CAPABILITIES(/transformation/stack/plastic__reagent_dispenser_cartridge_large)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/reagent_containers/chem_disp_cartridge, 1)),
		chosen = chosen(title = "reagent dispenser cartridge (large)",
			subject = /datum/material/plastic,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__reagent_dispenser_cartridge_med
CAPABILITIES(/transformation/stack/plastic__reagent_dispenser_cartridge_med)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/reagent_containers/chem_disp_cartridge/medium, 1)),
		chosen = chosen(title = "reagent dispenser cartridge (med)",
			subject = /datum/material/plastic,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__reagent_dispenser_cartridge_small
CAPABILITIES(/transformation/stack/plastic__reagent_dispenser_cartridge_small)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/reagent_containers/chem_disp_cartridge/small, 1)),
		chosen = chosen(title = "reagent dispenser cartridge (small)",
			subject = /datum/material/plastic,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__white_floor_tile
CAPABILITIES(/transformation/stack/plastic__white_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/white, 4)),
		chosen = chosen(title = "white floor tile",
			subject = /datum/material/plastic,
			max_made = 20,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__freezer_floor_tile
CAPABILITIES(/transformation/stack/plastic__freezer_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/freezer, 4)),
		chosen = chosen(title = "freezer floor tile",
			subject = /datum/material/plastic,
			max_made = 20,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__white_floor_tile_2
CAPABILITIES(/transformation/stack/plastic__white_floor_tile_2)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white, 4)),
		chosen = chosen(title = "white floor tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_panel_tile
CAPABILITIES(/transformation/stack/plastic__white_panel_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/panels, 4)),
		chosen = chosen(title = "white panel tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_techfloor_tile
CAPABILITIES(/transformation/stack/plastic__white_techfloor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/techfloor, 4)),
		chosen = chosen(title = "white techfloor tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_techfloor_tile_with_vents
CAPABILITIES(/transformation/stack/plastic__white_techfloor_tile_with_vents)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/techfloor_grid, 4)),
		chosen = chosen(title = "white techfloor tile with vents",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_brown_perforated_tile
CAPABILITIES(/transformation/stack/plastic__white_brown_perforated_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/brown_perforated, 4)),
		chosen = chosen(title = "white brown perforated tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_gray_perforated_tile
CAPABILITIES(/transformation/stack/plastic__white_gray_perforated_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/gray_perforated, 4)),
		chosen = chosen(title = "white gray perforated tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_cargo_tile
CAPABILITIES(/transformation/stack/plastic__white_cargo_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/cargo, 4)),
		chosen = chosen(title = "white cargo tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_brown_platform_tile
CAPABILITIES(/transformation/stack/plastic__white_brown_platform_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/brown_platform, 4)),
		chosen = chosen(title = "white brown platform tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_gray_platform_tile
CAPABILITIES(/transformation/stack/plastic__white_gray_platform_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/gray_platform, 4)),
		chosen = chosen(title = "white gray platform tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_danger_tile
CAPABILITIES(/transformation/stack/plastic__white_danger_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/danger, 4)),
		chosen = chosen(title = "white danger tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_golden_tile
CAPABILITIES(/transformation/stack/plastic__white_golden_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/golden, 4)),
		chosen = chosen(title = "white golden tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_monofloor_tile
CAPABILITIES(/transformation/stack/plastic__white_monofloor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/monofloor, 4)),
		chosen = chosen(title = "white monofloor tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white")))

/transformation/stack/plastic__white_blue_corner_tile
CAPABILITIES(/transformation/stack/plastic__white_blue_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/bluecorner, 4)),
		chosen = chosen(title = "white blue corner tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white::white corner tiles")))

/transformation/stack/plastic__white_orange_corner_tile
CAPABILITIES(/transformation/stack/plastic__white_orange_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/orangecorner, 4)),
		chosen = chosen(title = "white orange corner tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white::white corner tiles")))

/transformation/stack/plastic__white_cyan_corner_tile
CAPABILITIES(/transformation/stack/plastic__white_cyan_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/cyancorner, 4)),
		chosen = chosen(title = "white cyan corner tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white::white corner tiles")))

/transformation/stack/plastic__white_violet_corner_tile
CAPABILITIES(/transformation/stack/plastic__white_violet_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/white/violetcorener, 4)),
		chosen = chosen(title = "white violet corner tile",
			subject = /datum/material/plastic,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-white::white corner tiles")))

/transformation/stack/plastic__shower_curtain
CAPABILITIES(/transformation/stack/plastic__shower_curtain)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/curtain, 1)),
		chosen = chosen(title = "shower curtain",
			subject = /datum/material/plastic,
			build_time = 15,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__plastic_flaps
CAPABILITIES(/transformation/stack/plastic__plastic_flaps)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/plasticflaps, 1)),
		chosen = chosen(title = "plastic flaps",
			subject = /datum/material/plastic,
			build_time = 25,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__water_cooler
CAPABILITIES(/transformation/stack/plastic__water_cooler)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/reagent_dispensers/water_cooler, 1)),
		chosen = chosen(title = "water-cooler",
			subject = /datum/material/plastic,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__lampshade
CAPABILITIES(/transformation/stack/plastic__lampshade)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/lampshade, 1)),
		chosen = chosen(title = "lampshade",
			subject = /datum/material/plastic,
			build_time = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__plastic_net
CAPABILITIES(/transformation/stack/plastic__plastic_net)
	configure(transformation(takes = list(stack_term(STACK_SELF, 25)), makes = list(item_term(/obj/item/material/fishing_net, 1)),
		chosen = chosen(title = "plastic net",
			subject = /datum/material/plastic,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__plastic_fishtank
CAPABILITIES(/transformation/stack/plastic__plastic_fishtank)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/glass_jar/fish/plastic, 1)),
		chosen = chosen(title = "plastic fishtank",
			subject = /datum/material/plastic,
			build_time = 30 SECONDS,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__reagent_tubing
CAPABILITIES(/transformation/stack/plastic__reagent_tubing)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/hose, 4)),
		chosen = chosen(title = "reagent tubing",
			subject = /datum/material/plastic,
			max_made = 20,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__feeder
CAPABILITIES(/transformation/stack/plastic__feeder)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/machinery/feeder, 1)),
		chosen = chosen(title = "Feeder",
			subject = /datum/material/plastic,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plastic__sofa_middle
CAPABILITIES(/transformation/stack/plastic__sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa, 1)),
		chosen = chosen(title = "sofa middle",
			subject = /datum/material/plastic,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/transformation/stack/plastic__sofa_left
CAPABILITIES(/transformation/stack/plastic__sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left, 1)),
		chosen = chosen(title = "sofa left",
			subject = /datum/material/plastic,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/transformation/stack/plastic__sofa_right
CAPABILITIES(/transformation/stack/plastic__sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right, 1)),
		chosen = chosen(title = "sofa right",
			subject = /datum/material/plastic,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/transformation/stack/plastic__sofa_corner
CAPABILITIES(/transformation/stack/plastic__sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner, 1)),
		chosen = chosen(title = "sofa corner",
			subject = /datum/material/plastic,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

