/datum/material/wood
	name = MAT_WOOD
	stack_type = /obj/item/stack/material/wood
	icon_colour = "#9c5930"
	integrity = 50
	icon_base = "wood"
	explosion_resistance = 2
	shard_type = SHARD_SPLINTER
	shard_can_repair = 0 // you can't weld splinters back into planks
	hardness = 15
	density = 18
	protectiveness = 8 // 28%
	conductive = 0
	conductivity = 1
	melting_point = T0C+300 //okay, not melting in this case, but hot enough to destroy wood
	ignition_point = T0C+288
	dooropen_noise = SFX_EFFECTS_DOORCREAKY
	door_icon_base = "wood"
	destruction_desc = "splinters"
	sheet_singular_name = "plank"
	sheet_plural_name = "planks"
	supply_conversion_value = 0.25

/transformation/stack/wood__oar
CAPABILITIES(/transformation/stack/wood__oar)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/oar, 1)),
		chosen = chosen(title = "oar",
			subject = /datum/material/wood,
			build_time = 30,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/wood__boat
CAPABILITIES(/transformation/stack/wood__boat)
	configure(transformation(takes = list(stack_term(STACK_SELF, 20)), makes = list(item_term(/obj/vehicle/boat, 1)),
		chosen = chosen(title = "boat",
			subject = /datum/material/wood,
			build_time = 10 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/wood__dragon_boat
CAPABILITIES(/transformation/stack/wood__dragon_boat)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/vehicle/boat/dragon, 1)),
		chosen = chosen(title = "dragon boat",
			subject = /datum/material/wood,
			build_time = 30 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/wood__wooden_sandals
CAPABILITIES(/transformation/stack/wood__wooden_sandals)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/shoes/sandal, 1)),
		chosen = chosen(title = "wooden sandals",
			subject = /datum/material/wood,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__wood_circlet
CAPABILITIES(/transformation/stack/wood__wood_circlet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/head/woodcirclet, 1)),
		chosen = chosen(title = "wood circlet",
			subject = /datum/material/wood,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__clipboard
CAPABILITIES(/transformation/stack/wood__clipboard)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clipboard, 1)),
		chosen = chosen(title = "clipboard",
			subject = /datum/material/wood,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__wood_floor_tile
CAPABILITIES(/transformation/stack/wood__wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood, 4)),
		chosen = chosen(title = "wood floor tile",
			subject = /datum/material/wood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__large_wood_floor_tile
CAPABILITIES(/transformation/stack/wood__large_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/panel, 4)),
		chosen = chosen(title = "large wood floor tile",
			subject = /datum/material/wood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__parquet_wood_floor_tile
CAPABILITIES(/transformation/stack/wood__parquet_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/parquet, 4)),
		chosen = chosen(title = "parquet wood floor tile",
			subject = /datum/material/wood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__tiled_wood_floor_tile
CAPABILITIES(/transformation/stack/wood__tiled_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/tile, 4)),
		chosen = chosen(title = "tiled wood floor tile",
			subject = /datum/material/wood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__vertical_wood_floor_tile
CAPABILITIES(/transformation/stack/wood__vertical_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/vert, 4)),
		chosen = chosen(title = "vertical wood floor tile",
			subject = /datum/material/wood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__vertical_large_wood_floor_tile
CAPABILITIES(/transformation/stack/wood__vertical_large_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/vert_panel, 4)),
		chosen = chosen(title = "vertical large wood floor tile",
			subject = /datum/material/wood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__wooden_chair
CAPABILITIES(/transformation/stack/wood__wooden_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/wood, 1)),
		chosen = chosen(title = "wooden chair",
			subject = /datum/material/wood,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__crossbow_frame
CAPABILITIES(/transformation/stack/wood__crossbow_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/crossbowframe, 1)),
		chosen = chosen(title = "crossbow frame",
			subject = /datum/material/wood,
			build_time = 25,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__coffin
CAPABILITIES(/transformation/stack/wood__coffin)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/closet/coffin, 1)),
		chosen = chosen(title = "coffin",
			subject = /datum/material/wood,
			build_time = 15,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__beehive_assembly
CAPABILITIES(/transformation/stack/wood__beehive_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/beehive_assembly, 1)),
		chosen = chosen(title = "beehive assembly",
			subject = /datum/material/wood,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__beehive_frame
CAPABILITIES(/transformation/stack/wood__beehive_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/honey_frame, 1)),
		chosen = chosen(title = "beehive frame",
			subject = /datum/material/wood,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__book_shelf
CAPABILITIES(/transformation/stack/wood__book_shelf)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/bookcase, 1)),
		chosen = chosen(title = "book shelf",
			subject = /datum/material/wood,
			build_time = 15,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__wooden_shelves
CAPABILITIES(/transformation/stack/wood__wooden_shelves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/table/rack/shelf/wood, 1)),
		chosen = chosen(title = "wooden shelves",
			subject = /datum/material/wood,
			build_time = 5,
			one_per_turf = TRUE,
			on_floor = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__noticeboard_frame
CAPABILITIES(/transformation/stack/wood__noticeboard_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/frame/noticeboard, 1)),
		chosen = chosen(title = "noticeboard frame",
			subject = /datum/material/wood,
			build_time = 5,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__coilgun_stock
CAPABILITIES(/transformation/stack/wood__coilgun_stock)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/coilgun_assembly, 1)),
		chosen = chosen(title = "coilgun stock",
			subject = /datum/material/wood,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__crude_fishing_rod
CAPABILITIES(/transformation/stack/wood__crude_fishing_rod)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/material/fishing_rod/built, 1)),
		chosen = chosen(title = "crude fishing rod",
			subject = /datum/material/wood,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__wooden_standup_figure
CAPABILITIES(/transformation/stack/wood__wooden_standup_figure)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/barricade/cutout, 1)),
		chosen = chosen(title = "wooden standup figure",
			subject = /datum/material/wood,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__noticeboard
CAPABILITIES(/transformation/stack/wood__noticeboard)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/noticeboard, 1)),
		chosen = chosen(title = "noticeboard",
			subject = /datum/material/wood,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__tanning_rack
CAPABILITIES(/transformation/stack/wood__tanning_rack)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/tanning_rack, 1)),
		chosen = chosen(title = "tanning rack",
			subject = /datum/material/wood,
			build_time = 20,
			one_per_turf = TRUE,
			on_floor = TRUE,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/wood__painting_easel
CAPABILITIES(/transformation/stack/wood__painting_easel)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/easel, 1)),
		chosen = chosen(title = "painting easel",
			subject = /datum/material/wood,
			build_time = 20,
			one_per_turf = TRUE,
			on_floor = TRUE,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/wood__painting_frame
CAPABILITIES(/transformation/stack/wood__painting_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/frame/painting, 1)),
		chosen = chosen(title = "painting frame",
			subject = /datum/material/wood,
			build_time = 20,
			one_per_turf = TRUE,
			on_floor = TRUE,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/wood__roofing_tile
CAPABILITIES(/transformation/stack/wood__roofing_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/stack/tile/roofing, 4)),
		chosen = chosen(title = "roofing tile",
			subject = /datum/material/wood,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood__shovel
CAPABILITIES(/transformation/stack/wood__shovel)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/shovel/wood, 1)),
		chosen = chosen(title = "shovel",
			subject = /datum/material/wood,
			build_time = 10,
			on_floor = TRUE,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/wood__sofa_middle
CAPABILITIES(/transformation/stack/wood__sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa, 1)),
		chosen = chosen(title = "sofa middle",
			subject = /datum/material/wood,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/transformation/stack/wood__sofa_left
CAPABILITIES(/transformation/stack/wood__sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left, 1)),
		chosen = chosen(title = "sofa left",
			subject = /datum/material/wood,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/transformation/stack/wood__sofa_right
CAPABILITIES(/transformation/stack/wood__sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right, 1)),
		chosen = chosen(title = "sofa right",
			subject = /datum/material/wood,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/transformation/stack/wood__sofa_corner
CAPABILITIES(/transformation/stack/wood__sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner, 1)),
		chosen = chosen(title = "sofa corner",
			subject = /datum/material/wood,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			group = "sofas")))

/datum/material/wood/sif
	name = MAT_SIFWOOD
	stack_type = /obj/item/stack/material/wood/sif
	icon_colour = "#0099cc" // Cyan-ish

/transformation/stack/wood_sif__alien_wood_floor_tile
CAPABILITIES(/transformation/stack/wood_sif__alien_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/sif, 4)),
		chosen = chosen(title = "alien wood floor tile",
			subject = /datum/material/wood/sif,
			max_made = 20,
			pass_color = FALSE,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair"))))

/transformation/stack/wood_sif__large_alien_wood_floor_tile
CAPABILITIES(/transformation/stack/wood_sif__large_alien_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/sif/panel, 4)),
		chosen = chosen(title = "large alien wood floor tile",
			subject = /datum/material/wood/sif,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_sif__alien_wood_parquet_tile
CAPABILITIES(/transformation/stack/wood_sif__alien_wood_parquet_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/sif/parquet, 4)),
		chosen = chosen(title = "alien wood parquet tile",
			subject = /datum/material/wood/sif,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_sif__tiled_alien_wood_floor_tile
CAPABILITIES(/transformation/stack/wood_sif__tiled_alien_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/sif/tile, 4)),
		chosen = chosen(title = "tiled alien wood floor tile",
			subject = /datum/material/wood/sif,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_sif__vertical_alien_wood_floor_tile
CAPABILITIES(/transformation/stack/wood_sif__vertical_alien_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/sif/vert, 4)),
		chosen = chosen(title = "vertical alien wood floor tile",
			subject = /datum/material/wood/sif,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_sif__vertical_large_alien_wood_floor_tile
CAPABILITIES(/transformation/stack/wood_sif__vertical_large_alien_wood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/sif/vert_panel, 4)),
		chosen = chosen(title = "vertical large alien wood floor tile",
			subject = /datum/material/wood/sif,
			max_made = 20,
			pass_color = FALSE)))

/datum/material/wood/hardwood
	name = MAT_HARDWOOD
	stack_type = /obj/item/stack/material/wood/hard
	icon_colour = "#42291a"
	icon_base = "stone"
	table_icon_base = "stone"
	icon_reinf = "reinf_stone"
	integrity = 65	//a bit stronger than regular wood
	hardness = 20
	density = 20	//likewise, heavier

/transformation/stack/wood_hardwood__hardwood_floor_tile
CAPABILITIES(/transformation/stack/wood_hardwood__hardwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/hardwood, 4)),
		chosen = chosen(title = "hardwood floor tile",
			subject = /datum/material/wood/hardwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair", "wooden standup figure"))))

/transformation/stack/wood_hardwood__large_hardwood_floor_tile
CAPABILITIES(/transformation/stack/wood_hardwood__large_hardwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/hardwood/panel, 4)),
		chosen = chosen(title = "large hardwood floor tile",
			subject = /datum/material/wood/hardwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_hardwood__parquet_hardwood_floor_tile
CAPABILITIES(/transformation/stack/wood_hardwood__parquet_hardwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/hardwood/parquet, 4)),
		chosen = chosen(title = "parquet hardwood floor tile",
			subject = /datum/material/wood/hardwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_hardwood__tiled_hardwood_floor_tile
CAPABILITIES(/transformation/stack/wood_hardwood__tiled_hardwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/hardwood/tile, 4)),
		chosen = chosen(title = "tiled hardwood floor tile",
			subject = /datum/material/wood/hardwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_hardwood__vertical_hardwood_floor_tile
CAPABILITIES(/transformation/stack/wood_hardwood__vertical_hardwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/hardwood/vert, 4)),
		chosen = chosen(title = "vertical hardwood floor tile",
			subject = /datum/material/wood/hardwood,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_hardwood__vertical_large_hardwood_floor_tile
CAPABILITIES(/transformation/stack/wood_hardwood__vertical_large_hardwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/hardwood/vert_panel, 4)),
		chosen = chosen(title = "vertical large hardwood floor tile",
			subject = /datum/material/wood/hardwood,
			max_made = 20,
			pass_color = FALSE)))

/datum/material/wood/log
	name = MAT_LOG
	display_name = MAT_WOOD // will lead to "wood log"
	icon_base = "log"
	stack_type = /obj/item/stack/material/log
	sheet_singular_name = MAT_LOG
	sheet_plural_name = "logs"
	sheet_collective_name = "pile"
	pass_stack_colors = TRUE
	supply_conversion_value = 0.5

/transformation/stack/wood_log__bonfire
CAPABILITIES(/transformation/stack/wood_log__bonfire)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/bonfire, 1)),
		chosen = chosen(title = "bonfire",
			subject = /datum/material/wood/log,
			build_time = 50,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF,
			replaces = TRUE)))

/datum/material/wood/log/sif
	name = MAT_SIFLOG
	display_name = MAT_SIFWOOD
	icon_colour = "#0099cc" // Cyan-ish
	stack_type = /obj/item/stack/material/log/sif

/datum/material/wood/log/hard
	name = MAT_HARDLOG
	display_name = MAT_HARDWOOD
	icon_colour = "#6f432a"
	stack_type = /obj/item/stack/material/log/hard

/datum/material/wood/stick
	name = MAT_WOODEN_STICK
	icon_colour = "#824B28"
	display_name = MAT_WOOD
	icon_base = "stick"
	stack_type = /obj/item/stack/material/stick
	sheet_collective_name = "pile"
	pass_stack_colors = TRUE
	supply_conversion_value = 0.05
	sheet_singular_name = "stick"
	sheet_plural_name = "sticks"

/transformation/stack/wood_stick__clears
CAPABILITIES(/transformation/stack/wood_stick__clears)
	configure(transformation(chosen = chosen(subject = /datum/material/wood/stick, replaces = TRUE)))

/datum/material/wood/birch
	name = MAT_BIRCHWOOD
	stack_type = /obj/item/stack/material/wood/birch
	icon_colour = "#f6dec0"
	icon_base = "wood"
	icon_reinf = "reinf_stone"
	integrity = 65
	hardness = 20
	density = 20

/transformation/stack/wood_birch__birch_floor_tile
CAPABILITIES(/transformation/stack/wood_birch__birch_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/birch, 4)),
		chosen = chosen(title = "birch floor tile",
			subject = /datum/material/wood/birch,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair", "wooden standup figure"))))

/transformation/stack/wood_birch__large_birch_floor_tile
CAPABILITIES(/transformation/stack/wood_birch__large_birch_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/birch/panel, 4)),
		chosen = chosen(title = "large birch floor tile",
			subject = /datum/material/wood/birch,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_birch__parquet_birch_floor_tile
CAPABILITIES(/transformation/stack/wood_birch__parquet_birch_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/birch/parquet, 4)),
		chosen = chosen(title = "parquet birch floor tile",
			subject = /datum/material/wood/birch,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_birch__tiled_birch_floor_tile
CAPABILITIES(/transformation/stack/wood_birch__tiled_birch_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/birch/tile, 4)),
		chosen = chosen(title = "tiled birch floor tile",
			subject = /datum/material/wood/birch,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_birch__vertical_birch_floor_tile
CAPABILITIES(/transformation/stack/wood_birch__vertical_birch_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/birch/vert, 4)),
		chosen = chosen(title = "vertical birch floor tile",
			subject = /datum/material/wood/birch,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_birch__vertical_large_birch_floor_tile
CAPABILITIES(/transformation/stack/wood_birch__vertical_large_birch_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/birch/vert_panel, 4)),
		chosen = chosen(title = "vertical large birch floor tile",
			subject = /datum/material/wood/birch,
			max_made = 20,
			pass_color = FALSE)))

/datum/material/wood/pine
	name = MAT_PINEWOOD
	stack_type = /obj/item/stack/material/wood/pine
	icon_colour = "#cd9d6f"
	icon_base = "wood"
	icon_reinf = "reinf_stone"
	integrity = 65
	hardness = 20
	density = 20

/transformation/stack/wood_pine__pine_floor_tile
CAPABILITIES(/transformation/stack/wood_pine__pine_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/pine, 4)),
		chosen = chosen(title = "pine floor tile",
			subject = /datum/material/wood/pine,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair", "wooden standup figure"))))

/transformation/stack/wood_pine__large_pine_floor_tile
CAPABILITIES(/transformation/stack/wood_pine__large_pine_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/pine/panel, 4)),
		chosen = chosen(title = "large pine floor tile",
			subject = /datum/material/wood/pine,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_pine__parquet_pine_floor_tile
CAPABILITIES(/transformation/stack/wood_pine__parquet_pine_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/pine/parquet, 4)),
		chosen = chosen(title = "parquet pine floor tile",
			subject = /datum/material/wood/pine,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_pine__tiled_pine_floor_tile
CAPABILITIES(/transformation/stack/wood_pine__tiled_pine_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/pine/tile, 4)),
		chosen = chosen(title = "tiled pine floor tile",
			subject = /datum/material/wood/pine,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_pine__vertical_pine_floor_tile
CAPABILITIES(/transformation/stack/wood_pine__vertical_pine_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/pine/vert, 4)),
		chosen = chosen(title = "vertical pine floor tile",
			subject = /datum/material/wood/pine,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_pine__vertical_large_pine_floor_tile
CAPABILITIES(/transformation/stack/wood_pine__vertical_large_pine_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/pine/vert_panel, 4)),
		chosen = chosen(title = "vertical large pine floor tile",
			subject = /datum/material/wood/pine,
			max_made = 20,
			pass_color = FALSE)))

/datum/material/wood/oak
	name = MAT_OAKWOOD
	stack_type = /obj/item/stack/material/wood/oak
	icon_colour = "#674928"
	icon_base = "wood"
	icon_reinf = "reinf_stone"
	integrity = 65
	hardness = 20
	density = 20

/transformation/stack/wood_oak__oak_floor_tile
CAPABILITIES(/transformation/stack/wood_oak__oak_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/oak, 4)),
		chosen = chosen(title = "oak floor tile",
			subject = /datum/material/wood/oak,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair", "wooden standup figure"))))

/transformation/stack/wood_oak__large_oak_floor_tile
CAPABILITIES(/transformation/stack/wood_oak__large_oak_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/oak/panel, 4)),
		chosen = chosen(title = "large oak floor tile",
			subject = /datum/material/wood/oak,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_oak__parquet_oak_floor_tile
CAPABILITIES(/transformation/stack/wood_oak__parquet_oak_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/oak/parquet, 4)),
		chosen = chosen(title = "parquet oak floor tile",
			subject = /datum/material/wood/oak,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_oak__tiled_oak_floor_tile
CAPABILITIES(/transformation/stack/wood_oak__tiled_oak_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/oak/tile, 4)),
		chosen = chosen(title = "tiled oak floor tile",
			subject = /datum/material/wood/oak,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_oak__vertical_oak_floor_tile
CAPABILITIES(/transformation/stack/wood_oak__vertical_oak_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/oak/vert, 4)),
		chosen = chosen(title = "vertical oak floor tile",
			subject = /datum/material/wood/oak,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_oak__vertical_large_oak_floor_tile
CAPABILITIES(/transformation/stack/wood_oak__vertical_large_oak_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/oak/vert_panel, 4)),
		chosen = chosen(title = "vertical large oak floor tile",
			subject = /datum/material/wood/oak,
			max_made = 20,
			pass_color = FALSE)))

/datum/material/wood/acacia
	name = MAT_ACACIAWOOD
	stack_type = /obj/item/stack/material/wood/acacia
	icon_colour = "#b75e12"
	icon_base = "wood"
	icon_reinf = "reinf_stone"
	integrity = 65
	hardness = 20
	density = 20

/transformation/stack/wood_acacia__acacia_floor_tile
CAPABILITIES(/transformation/stack/wood_acacia__acacia_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/acacia, 4)),
		chosen = chosen(title = "acacia floor tile",
			subject = /datum/material/wood/acacia,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair", "wooden standup figure"))))

/transformation/stack/wood_acacia__large_acacia_floor_tile
CAPABILITIES(/transformation/stack/wood_acacia__large_acacia_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/acacia/panel, 4)),
		chosen = chosen(title = "large acacia floor tile",
			subject = /datum/material/wood/acacia,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_acacia__parquet_acacia_floor_tile
CAPABILITIES(/transformation/stack/wood_acacia__parquet_acacia_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/acacia/parquet, 4)),
		chosen = chosen(title = "parquet acacia floor tile",
			subject = /datum/material/wood/acacia,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_acacia__tiled_acacia_floor_tile
CAPABILITIES(/transformation/stack/wood_acacia__tiled_acacia_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/acacia/tile, 4)),
		chosen = chosen(title = "tiled acacia floor tile",
			subject = /datum/material/wood/acacia,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_acacia__vertical_acacia_floor_tile
CAPABILITIES(/transformation/stack/wood_acacia__vertical_acacia_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/acacia/vert, 4)),
		chosen = chosen(title = "vertical acacia floor tile",
			subject = /datum/material/wood/acacia,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_acacia__vertical_large_acacia_floor_tile
CAPABILITIES(/transformation/stack/wood_acacia__vertical_large_acacia_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/acacia/vert_panel, 4)),
		chosen = chosen(title = "vertical large acacia floor tile",
			subject = /datum/material/wood/acacia,
			max_made = 20,
			pass_color = FALSE)))

/datum/material/wood/redwood
	name = MAT_REDWOOD
	stack_type = /obj/item/stack/material/wood/redwood
	icon_colour = "#a45a52"
	icon_base = "wood"
	table_icon_base = "stone"
	icon_reinf = "reinf_stone"
	integrity = 65
	hardness = 20
	density = 20

/transformation/stack/wood_redwood__redwood_floor_tile
CAPABILITIES(/transformation/stack/wood_redwood__redwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/redwood, 4)),
		chosen = chosen(title = "redwood floor tile",
			subject = /datum/material/wood/redwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF,
			drops = list("wood floor tile", "large wood floor tile", "parquet wood floor tile", "tiled wood floor tile", "vertical wood floor tile", "vertical large wood floor tile", "wooden chair", "wooden standup figure"))))

/transformation/stack/wood_redwood__large_redwood_floor_tile
CAPABILITIES(/transformation/stack/wood_redwood__large_redwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/redwood/panel, 4)),
		chosen = chosen(title = "large redwood floor tile",
			subject = /datum/material/wood/redwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_redwood__parquet_redwood_floor_tile
CAPABILITIES(/transformation/stack/wood_redwood__parquet_redwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/redwood/parquet, 4)),
		chosen = chosen(title = "parquet redwood floor tile",
			subject = /datum/material/wood/redwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_redwood__tiled_redwood_floor_tile
CAPABILITIES(/transformation/stack/wood_redwood__tiled_redwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/redwood/tile, 4)),
		chosen = chosen(title = "tiled redwood floor tile",
			subject = /datum/material/wood/redwood,
			max_made = 20,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/wood_redwood__vertical_redwood_floor_tile
CAPABILITIES(/transformation/stack/wood_redwood__vertical_redwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/redwood/vert, 4)),
		chosen = chosen(title = "vertical redwood floor tile",
			subject = /datum/material/wood/redwood,
			max_made = 20,
			pass_color = FALSE)))

/transformation/stack/wood_redwood__vertical_large_redwood_floor_tile
CAPABILITIES(/transformation/stack/wood_redwood__vertical_large_redwood_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/wood/redwood/vert_panel, 4)),
		chosen = chosen(title = "vertical large redwood floor tile",
			subject = /datum/material/wood/redwood,
			max_made = 20,
			pass_color = FALSE)))

