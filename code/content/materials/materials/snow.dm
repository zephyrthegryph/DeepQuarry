/datum/material/snow
	name = MAT_SNOW
	stack_type = /obj/item/stack/material/snow
	flags = MATERIAL_BRITTLE
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#FFFFFF"
	integrity = 1
	hardness = 1
	density = 1
	protectiveness = 0 // 0%
	melting_point = T0C+1
	destruction_desc = "crumples"
	sheet_singular_name = "pile"
	sheet_plural_name = "pile" //Just a bigger pile
	radiation_resistance = 1
	supply_conversion_value = 0

/transformation/stack/snow__snowball
CAPABILITIES(/transformation/stack/snow__snowball)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/snow/snowball, 1)),
		chosen = chosen(title = "snowball",
			subject = /datum/material/snow,
			build_time = 10,
			recycle = STACK_MATERIAL_SELF,
			replaces = TRUE)))

/transformation/stack/snow__snow_brick
CAPABILITIES(/transformation/stack/snow__snow_brick)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/material/snowbrick, 1)),
		chosen = chosen(title = "snow brick",
			subject = /datum/material/snow,
			build_time = 10,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/snow__snowman
CAPABILITIES(/transformation/stack/snow__snowman)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/snowman, 1)),
		chosen = chosen(title = "snowman",
			subject = /datum/material/snow,
			build_time = 15,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/snow__snow_robot
CAPABILITIES(/transformation/stack/snow__snow_robot)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/snowman/borg, 1)),
		chosen = chosen(title = "snow robot",
			subject = /datum/material/snow,
			build_time = 10,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/snow__snow_spider
CAPABILITIES(/transformation/stack/snow__snow_spider)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/snowman/spider, 1)),
		chosen = chosen(title = "snow spider",
			subject = /datum/material/snow,
			build_time = 20,
			recycle = STACK_MATERIAL_SELF)))

/datum/material/snowbrick //only slightly stronger than snow, used to make igloos mostly
	name = MAT_SNOWBRICK
	flags = MATERIAL_BRITTLE
	stack_type = /obj/item/stack/material/snowbrick
	icon_base = "stone"
	table_icon_base = "stone"
	icon_reinf = "reinf_stone"
	icon_colour = "#D8FDFF"
	integrity = 50
	density = 2
	hardness = 2
	protectiveness = 0 // 0%
	melting_point = T0C+1
	destruction_desc = "crumbles"
	sheet_singular_name = "brick"
	sheet_plural_name = "bricks"
	radiation_resistance = 1
	supply_conversion_value = 0

/transformation/stack/snowbrick__door
CAPABILITIES(/transformation/stack/snowbrick__door)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/structure/simple_door, 1)),
		chosen = chosen(title = "{display_name} door",
			subject = /datum/material/snowbrick,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			replaces = TRUE)))

/transformation/stack/snowbrick__barricade
CAPABILITIES(/transformation/stack/snowbrick__barricade)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/barricade, 1)),
		chosen = chosen(title = "{display_name} barricade",
			subject = /datum/material/snowbrick,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/snowbrick__stool
CAPABILITIES(/transformation/stack/snowbrick__stool)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stool, 1)),
		chosen = chosen(title = "{display_name} stool",
			subject = /datum/material/snowbrick,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/snowbrick__chair
CAPABILITIES(/transformation/stack/snowbrick__chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair, 1)),
		chosen = chosen(title = "{display_name} chair",
			subject = /datum/material/snowbrick,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/snowbrick__bed
CAPABILITIES(/transformation/stack/snowbrick__bed)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed, 1)),
		chosen = chosen(title = "{display_name} bed",
			subject = /datum/material/snowbrick,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/snowbrick__double_bed
CAPABILITIES(/transformation/stack/snowbrick__double_bed)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/bed/double, 1)),
		chosen = chosen(title = "{display_name} double bed",
			subject = /datum/material/snowbrick,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/snowbrick__wall_girders
CAPABILITIES(/transformation/stack/snowbrick__wall_girders)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/girder, 1)),
		chosen = chosen(title = "{display_name} wall girders",
			subject = /datum/material/snowbrick,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/snowbrick__ashtray
CAPABILITIES(/transformation/stack/snowbrick__ashtray)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/material/ashtray, 1)),
		chosen = chosen(title = "{display_name} ashtray",
			subject = /datum/material/snowbrick,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

