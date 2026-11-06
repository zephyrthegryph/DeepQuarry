/datum/material/grass
	name = MAT_GRASS
	display_name = "grass"
	stack_type = /obj/item/stack/tile/grass
	ignition_point = T0C+300
	melting_point = T0C+300
	protectiveness = 0
	conductive = 0
	integrity = 10
	supply_conversion_value = 0.1

/transformation/stack/grass__bush
CAPABILITIES(/transformation/stack/grass__bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes, 1)),
		chosen = chosen(title = "bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers",
			replaces = TRUE)))

/transformation/stack/grass__reed_bush
CAPABILITIES(/transformation/stack/grass__reed_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/reedbush, 1)),
		chosen = chosen(title = "reed bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__leafy_bush
CAPABILITIES(/transformation/stack/grass__leafy_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/leafybush, 1)),
		chosen = chosen(title = "leafy bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__pale_bush
CAPABILITIES(/transformation/stack/grass__pale_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/palebush, 1)),
		chosen = chosen(title = "pale bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__stalky_bush
CAPABILITIES(/transformation/stack/grass__stalky_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/stalkybush, 1)),
		chosen = chosen(title = "stalky bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__grassy_bush
CAPABILITIES(/transformation/stack/grass__grassy_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/grassybush, 1)),
		chosen = chosen(title = "grassy bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__ferny_bush
CAPABILITIES(/transformation/stack/grass__ferny_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/fernybush, 1)),
		chosen = chosen(title = "ferny bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__sunny_bush
CAPABILITIES(/transformation/stack/grass__sunny_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/sunnybush, 1)),
		chosen = chosen(title = "sunny bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__pointy_bush
CAPABILITIES(/transformation/stack/grass__pointy_bush)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/pointybush, 1)),
		chosen = chosen(title = "pointy bush",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__lavender_grass
CAPABILITIES(/transformation/stack/grass__lavender_grass)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/lavendergrass, 1)),
		chosen = chosen(title = "lavender grass",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__yellow_and_white_flowers
CAPABILITIES(/transformation/stack/grass__yellow_and_white_flowers)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/ywflowers, 1)),
		chosen = chosen(title = "yellow-and-white flowers",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__blue_and_red_flowers
CAPABILITIES(/transformation/stack/grass__blue_and_red_flowers)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/brflowers, 1)),
		chosen = chosen(title = "blue-and-red flowers",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__pink_and_purple_flowers
CAPABILITIES(/transformation/stack/grass__pink_and_purple_flowers)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/ppflowers, 1)),
		chosen = chosen(title = "pink-and-purple flowers",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__sparse_grass
CAPABILITIES(/transformation/stack/grass__sparse_grass)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/sparsegrass, 1)),
		chosen = chosen(title = "sparse grass",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

/transformation/stack/grass__full_grass
CAPABILITIES(/transformation/stack/grass__full_grass)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/flora/ausbushes/fullgrass, 1)),
		chosen = chosen(title = "full grass",
			subject = /datum/material/grass,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "bushes and flowers")))

