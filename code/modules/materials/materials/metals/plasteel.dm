/datum/material/plasteel
	name = MAT_PLASTEEL
	stack_type = /obj/item/stack/material/plasteel
	material_class = MATCLASS_METAL
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

/datum/material/plasteel/generate_recipes()
	..()
	recipes += list(
		new /datum/stack_recipe("AI core", /obj/structure/AIcore, 4, time = 50, one_per_turf = 1, recycle_material = "[name]"),
		new /datum/stack_recipe("Metal crate", /obj/structure/closet/crate, 10, time = 50, one_per_turf = 1, recycle_material = "[name]"),
		new /datum/stack_recipe("knife grip", /obj/item/material/butterflyhandle, 4, time = 20, one_per_turf = 0, on_floor = 1, supplied_material = "[name]"),
		new /datum/stack_recipe("dark floor tile", /obj/item/stack/tile/floor/dark, 1, 4, 20, recycle_material = "[name]"),
		new /datum/stack_recipe("roller bed", /obj/item/roller, 5, time = 30, on_floor = 1, recycle_material = "[name]"),
		new /datum/stack_recipe("whetstone", /obj/item/whetstone, 2, time = 10, recycle_material = "[name]"),
		new /datum/stack_recipe("plasteel rebar", /obj/item/stack/material/plasteel/rebar, 1, time = 5, recycle_material = "[name]"),
		new /datum/stack_recipe("plasteel hull sheet", /obj/item/stack/material/plasteel/hull, 2, 1, 5, time = 20, one_per_turf = 0, on_floor = 1, recycle_material = "[name]"),
		new /datum/stack_recipe_list("reinforced low walls",list(
			new /datum/stack_recipe("reinforced low wall (bay style)", /obj/structure/low_wall/bay/reinforced, 3, one_per_turf = 1, on_floor = 1, supplied_material = "[name]", recycle_material = "[name]"),
			new /datum/stack_recipe("reinforced low wall (eris style)", /obj/structure/low_wall/eris/reinforced, 3, one_per_turf = 1, on_floor = 1, supplied_material = "[name]", recycle_material = "[name]")
		)),
	)

/datum/material/plasteel/rebar //to give a different reinforced overlay
	name = MAT_PLASTEELREBAR
	icon_reinf = "reinf_metal"
	icon_colour = "#6A6A6A"
	stack_type = /obj/item/stack/material/plasteel/rebar
	sheet_singular_name = "rod"
	sheet_plural_name = "rods"
	composite_material = list(MAT_PLASTEEL = SHEET_MATERIAL_AMOUNT)


// === merged from plasteel_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/material/plasteel/generate_recipes()
	. = ..()
// recipes += new /datum/stack_recipe("Hammer Head", /obj/item/hammer_head, 2) // Disabled because I had to disable code/game/objects/items/weapons/material/sledgehammer_construction_ch.dm due to lots of errors
	recipes += new /datum/stack_recipe_list("sofas", list( \
		new /datum/stack_recipe("sofa middle", /obj/structure/bed/chair/sofa, 1, one_per_turf = 1, on_floor = 1), \
		new /datum/stack_recipe("sofa left", /obj/structure/bed/chair/sofa/left, 1, one_per_turf = 1, on_floor = 1), \
		new /datum/stack_recipe("sofa right", /obj/structure/bed/chair/sofa/right, 1, one_per_turf = 1, on_floor = 1), \
		new /datum/stack_recipe("sofa corner", /obj/structure/bed/chair/sofa/corner, 1, one_per_turf = 1, on_floor = 1), \
		))


// === merged from plasteel_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/material/plastitanium
	name = MAT_PLASTITANIUM
	stack_type = /obj/item/stack/material/plastitanium
	material_class = MATCLASS_METAL
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

/datum/material/plastitanium/generate_recipes()
	..()
	recipes += list(
		new /datum/stack_recipe("whetstone", /obj/item/whetstone, 2, time = 20),
	)
