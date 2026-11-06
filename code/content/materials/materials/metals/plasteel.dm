/datum/material/plasteel
	name = MAT_PLASTEEL
	stack_type = /obj/item/stack/material/plasteel
	integrity = 400
	melting_point = 6000
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#777777"
	explosion_resistance = 25
	hardness = 80
	density = 23
	protectiveness = 20 // 50%
	conductivity = 13 // For the purposes of balance.
	supply_conversion_value = 6

/datum/material/plasteel/rebar //to give a different reinforced overlay
	name = MAT_PLASTEELREBAR
	icon_reinf = "reinf_metal"
	icon_colour = "#6A6A6A"
	stack_type = /obj/item/stack/material/plasteel/rebar
	sheet_singular_name = "rod"
	sheet_plural_name = "rods"
	composite_material = list(MAT_PLASTEEL = SHEET_MATERIAL_AMOUNT)


/transformation/stack/plasteel__ai_core
CAPABILITIES(/transformation/stack/plasteel__ai_core)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/AIcore, 1)),
		chosen = chosen(title = "AI core",
			subject = /datum/material/plasteel,
			build_time = 50,
			one_per_turf = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__metal_crate
CAPABILITIES(/transformation/stack/plasteel__metal_crate)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/structure/closet/crate, 1)),
		chosen = chosen(title = "Metal crate",
			subject = /datum/material/plasteel,
			build_time = 50,
			one_per_turf = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__knife_grip
CAPABILITIES(/transformation/stack/plasteel__knife_grip)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/material/butterflyhandle, 1)),
		chosen = chosen(title = "knife grip",
			subject = /datum/material/plasteel,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__dark_floor_tile
CAPABILITIES(/transformation/stack/plasteel__dark_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/dark, 4)),
		chosen = chosen(title = "dark floor tile",
			subject = /datum/material/plasteel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__roller_bed
CAPABILITIES(/transformation/stack/plasteel__roller_bed)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/roller, 1)),
		chosen = chosen(title = "roller bed",
			subject = /datum/material/plasteel,
			build_time = 30,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__whetstone
CAPABILITIES(/transformation/stack/plasteel__whetstone)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/whetstone, 1)),
		chosen = chosen(title = "whetstone",
			subject = /datum/material/plasteel,
			build_time = 10,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__plasteel_rebar
CAPABILITIES(/transformation/stack/plasteel__plasteel_rebar)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/material/plasteel/rebar, 1)),
		chosen = chosen(title = "plasteel rebar",
			subject = /datum/material/plasteel,
			build_time = 5,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__plasteel_hull_sheet
CAPABILITIES(/transformation/stack/plasteel__plasteel_hull_sheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/material/plasteel/hull, 1)),
		chosen = chosen(title = "plasteel hull sheet",
			subject = /datum/material/plasteel,
			max_made = 5,
			build_time = 20,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/plasteel__reinforced_low_wall_bay_style
CAPABILITIES(/transformation/stack/plasteel__reinforced_low_wall_bay_style)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/low_wall/bay/reinforced, 1)),
		chosen = chosen(title = "reinforced low wall (bay style)",
			subject = /datum/material/plasteel,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			recycle = STACK_MATERIAL_SELF,
			group = "reinforced low walls")))

/transformation/stack/plasteel__reinforced_low_wall_eris_style
CAPABILITIES(/transformation/stack/plasteel__reinforced_low_wall_eris_style)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/low_wall/eris/reinforced, 1)),
		chosen = chosen(title = "reinforced low wall (eris style)",
			subject = /datum/material/plasteel,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			recycle = STACK_MATERIAL_SELF,
			group = "reinforced low walls")))

/transformation/stack/plasteel__sofa_middle
CAPABILITIES(/transformation/stack/plasteel__sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa, 1)),
		chosen = chosen(title = "sofa middle",
			subject = /datum/material/plasteel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/plasteel__sofa_left
CAPABILITIES(/transformation/stack/plasteel__sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left, 1)),
		chosen = chosen(title = "sofa left",
			subject = /datum/material/plasteel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/plasteel__sofa_right
CAPABILITIES(/transformation/stack/plasteel__sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right, 1)),
		chosen = chosen(title = "sofa right",
			subject = /datum/material/plasteel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/plasteel__sofa_corner
CAPABILITIES(/transformation/stack/plasteel__sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner, 1)),
		chosen = chosen(title = "sofa corner",
			subject = /datum/material/plasteel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/datum/material/plastitanium
	name = MAT_PLASTITANIUM
	stack_type = /obj/item/stack/material/plastitanium
	integrity = 600
	melting_point = 9000
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#585658"
	explosion_resistance = 35
	hardness = 90
	density = 40
	protectiveness = 30
	conductivity = 7
	supply_conversion_value = 8

/transformation/stack/plastitanium__whetstone
CAPABILITIES(/transformation/stack/plastitanium__whetstone)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/whetstone, 1)),
		chosen = chosen(title = "whetstone",
			subject = /datum/material/plastitanium,
			build_time = 20)))

