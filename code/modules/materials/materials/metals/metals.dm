// DQEdit Start — material_class added per subtype so the dynamic-material
// system (SSquarry rolls) and downstream synergy checks have a coarse
// classification. The legacy hardness/conductivity/integrity/weight vars
// are unchanged; classes are purely additive metadata.
// DQEdit End


// Very rare alloy that is reflective, should be used sparingly.
/datum/material/durasteel
	name = MAT_DURASTEEL
	stack_type = /obj/item/stack/material/durasteel
	material_class = MATCLASS_METAL
	integrity = 600
	melting_point = 7000
	icon_base = "metal"
	icon_reinf = "reinf_metal"
	icon_colour = "#6EA7BE"
	explosion_resistance = 75
	hardness = 100
	density = 28
	protectiveness = 60 // 75%
	reflectivity = 0.7 // Not a perfect mirror, but close.
	supply_conversion_value = 9

/datum/material/durasteel/generate_recipes()
	..()
	recipes += list(
		new /datum/stack_recipe("durasteel hull sheet", /obj/item/stack/material/durasteel/hull, 2, 1, 5, time = 20, one_per_turf = 0, on_floor = 1, recycle_material = "[name]")
	)

/datum/material/titanium
	name = MAT_TITANIUM
	stack_type = /obj/item/stack/material/titanium
	material_class = MATCLASS_METAL
	conductivity = 2.38
	icon_base = "metal"
	door_icon_base = "metal"
	icon_colour = "#D1E6E3"
	icon_reinf = "reinf_metal"
	supply_conversion_value = 4

/datum/material/titanium/generate_recipes()
	..()
	recipes += list(
		new /datum/stack_recipe("titanium hull sheet", /obj/item/stack/material/titanium/hull, 2, 1, 5, time = 20, one_per_turf = 0, on_floor = 1, recycle_material = "[name]")
	)

/datum/material/iron
	name = MAT_IRON
	stack_type = /obj/item/stack/material/iron
	material_class = MATCLASS_METAL
	icon_colour = "#5C5454"
	density = 22
	conductivity = 10
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 0.25

/datum/material/lead
	name = MAT_LEAD
	stack_type = /obj/item/stack/material/lead
	material_class = MATCLASS_METAL
	icon_colour = "#273956"
	density = 23 // Lead is a bit more dense than silver IRL, and silver has 22 ingame.
	conductivity = 10
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	radiation_resistance = 25 // Lead is Special and so gets to block more radiation than it normally would with just weight, totalling in 48 protection.
	supply_conversion_value = 0.5

/datum/material/gold
	name = MAT_GOLD
	stack_type = /obj/item/stack/material/gold
	material_class = MATCLASS_METAL
	icon_colour = "#EDD12F"
	density = 24
	hardness = 40
	conductivity = 41
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 2

/datum/material/silver
	name = MAT_SILVER
	stack_type = /obj/item/stack/material/silver
	material_class = MATCLASS_METAL
	icon_colour = "#D1E6E3"
	density = 22
	hardness = 50
	conductivity = 63
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 1

/datum/material/platinum
	name = MAT_PLATINUM
	stack_type = /obj/item/stack/material/platinum
	material_class = MATCLASS_METAL
	icon_colour = "#9999FF"
	density = 27
	conductivity = 9.43
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 5

/datum/material/uranium
	name = MAT_URANIUM
	stack_type = /obj/item/stack/material/uranium
	material_class = MATCLASS_METAL
	icon_base = "stone"
	icon_reinf = "reinf_stone"
	icon_colour = "#007A00"
	density = 22
	door_icon_base = "stone"
	supply_conversion_value = 2

/datum/material/uranium/New()
	. = ..()
	// DQEdit — was `radioactivity = 12` direct var. Now lives on a
	// /datum/component/material_radioactive carrying the magnitude.
	AddComponent(/datum/component/material_radioactive, 12)

/datum/material/mhydrogen
	name = MAT_METALHYDROGEN
	display_name = "metallic hydrogen"
	stack_type = /obj/item/stack/material/mhydrogen
	material_class = MATCLASS_METAL
	icon_colour = "#E6C5DE"
	conductivity = 100
	is_fusion_fuel = 1
	supply_conversion_value = 6

/datum/material/deuterium
	name = MAT_DEUTERIUM
	stack_type = /obj/item/stack/material/deuterium
	material_class = MATCLASS_METAL
	icon_colour = "#999999"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	is_fusion_fuel = 1
	conductive = 0
	supply_conversion_value = 3

/datum/material/tritium
	name = MAT_TRITIUM
	stack_type = /obj/item/stack/material/tritium
	material_class = MATCLASS_METAL
	icon_colour = "#777777"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	is_fusion_fuel = 1
	conductive = 0
	supply_conversion_value = 4

/datum/material/osmium
	name = MAT_OSMIUM
	stack_type = /obj/item/stack/material/osmium
	material_class = MATCLASS_METAL
	icon_colour = "#9999FF"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	conductivity = 100
	supply_conversion_value = 6

/datum/material/graphite
	name = MAT_GRAPHITE
	stack_type = /obj/item/stack/material/graphite
	material_class = MATCLASS_METAL
	flags = MATERIAL_BRITTLE
	icon_base = "solid"
	table_icon_base = "stone"
	icon_reinf = "reinf_mesh"
	icon_colour = "#333333"
	hardness = 75
	density = 15
	integrity = 175
	protectiveness = 15
	conductivity = 18
	melting_point = T0C+3600
	radiation_resistance = 15
	supply_conversion_value = 0.5

/datum/material/bronze
	name = MAT_BRONZE
	stack_type = /obj/item/stack/material/bronze
	material_class = MATCLASS_METAL
	icon_colour = "#EDD12F"
	icon_base = "solid"
	icon_reinf = "reinf_over"
	integrity = 120
	conductivity = 12
	protectiveness = 9 // 33%
	supply_conversion_value = 1

/datum/material/tin
	name = MAT_TIN
	display_name = MAT_TIN
	use_name = MAT_TIN
	stack_type = /obj/item/stack/material/tin
	material_class = MATCLASS_METAL
	icon_colour = "#b2afaf"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 0.5
	hardness = 50
	density = 13

/datum/material/copper
	name = MAT_COPPER
	display_name = MAT_COPPER
	use_name = MAT_COPPER
	stack_type = /obj/item/stack/material/copper
	material_class = MATCLASS_METAL
	conductivity = 52
	icon_colour = "#af633e"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 0.5
	density = 13
	hardness = 50

/datum/material/aluminium
	name = MAT_ALUMINIUM
	display_name = MAT_ALUMINIUM
	use_name = MAT_ALUMINIUM
	icon_colour = "#e5e2d0"
	stack_type = /obj/item/stack/material/aluminium
	material_class = MATCLASS_METAL
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 1
	density = 10


// === merged from metals_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/material/durasteel/generate_recipes()
	. = ..()
	recipes += list(
		new /datum/stack_recipe("durasteel fishing rod", /obj/item/material/fishing_rod/modern/strong, 2),
		new /datum/stack_recipe("whetstone", /obj/item/whetstone, 2, time = 30),
	)


// === merged from metals_chomp.dm during hard-fork de-suffix (chain-verified additive) ===
/datum/material/durasteel //Slightly nerfed protectivness
	protectiveness = 55

/datum/material/durasteel/hull //Severly reduces protectivness
	protectiveness = 45

/datum/material/titanium //Adjusted hardness, reflective, and protection
	hardness = 60
	protectiveness = 30
	reflectivity = 0.3


/datum/material/iron //Adjusted hardness, reflective, and protection
	hardness = 70
	protectiveness = 20
	reflectivity = 0.1


/datum/material/lead //Adjusted hardness, reflective, and protection
	hardness = 60
	protectiveness = 15
	reflectivity = 0.1


/datum/material/gold //Adjusted reflective, and protection
	hardness = 50
	protectiveness = 30
	reflectivity = 0.05


/datum/material/silver //Adjusted reflective, and protection
	hardness = 60
	protectiveness = 30
	reflectivity = 0.2


/datum/material/platinum //Adjusted hardness, reflective, and protection
	hardness = 60
	protectiveness = 30
	reflectivity = 0.0

/datum/material/uranium //Adjusted hardness, reflective, and protection
	hardness = 70
	protectiveness = 30
	reflectivity = 0.5

/datum/material/mhydrogen //Adjusted hardness, reflective, and protection. And weight.
	hardness = 75
	protectiveness = 40
	reflectivity = 0.4
	density = 5

/datum/material/osmium //Adjusted hardness, reflective, and protection
	hardness = 65
	protectiveness = 30
	reflectivity = 0.1
