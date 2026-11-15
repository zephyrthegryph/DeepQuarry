// Very rare alloy that is reflective, should be used sparingly.
/datum/material/durasteel
	name = MAT_DURASTEEL
	stack_type = /obj/item/stack/material/durasteel
	toughness = 300
	heat_resistance = 168.8
	icon_base = "metal"
	icon_reinf = "reinf_metal"
	icon_colour = "#6EA7BE"
	strength = 100
	weight = 28
	reflectivity = 0.7 // Not a perfect mirror, but close.
	supply_conversion_value = 9

/datum/material/titanium
	name = MAT_TITANIUM
	stack_type = /obj/item/stack/material/titanium
	conductivity = 8
	icon_base = "metal"
	door_icon_base = "metal"
	icon_colour = "#D1E6E3"
	icon_reinf = "reinf_metal"
	supply_conversion_value = 4

/transformation/stack/titanium__titanium_hull_sheet
CAPABILITIES(/transformation/stack/titanium__titanium_hull_sheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/material/titanium/hull, 1)),
		chosen = chosen(title = "titanium hull sheet",
			subject = /datum/material/titanium,
			max_made = 5,
			build_time = 20,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/datum/material/iron
	name = MAT_IRON
	stack_type = /obj/item/stack/material/iron
	icon_colour = "#5C5454"
	weight = 22
	conductivity = 10
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 0.25

/datum/material/lead
	name = MAT_LEAD
	stack_type = /obj/item/stack/material/lead
	icon_colour = "#273956"
	weight = 23 // Lead is a bit more dense than silver IRL, and silver has 22 ingame.
	conductivity = 10
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	radiation_resistance = 25 // Lead is Special and so gets to block more radiation than it normally would with just weight, totalling in 48 protection.
	supply_conversion_value = 0.5

/datum/material/gold
	name = MAT_GOLD
	stack_type = /obj/item/stack/material/gold
	icon_colour = "#EDD12F"
	weight = 24
	strength = 40
	conductivity = 41
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 2

/datum/material/silver
	name = MAT_SILVER
	stack_type = /obj/item/stack/material/silver
	icon_colour = "#D1E6E3"
	weight = 22
	strength = 50
	conductivity = 63
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 1

/datum/material/platinum
	name = MAT_PLATINUM
	stack_type = /obj/item/stack/material/platinum
	icon_colour = "#9999FF"
	weight = 27
	conductivity = 9.43
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 5

/datum/material/uranium
	name = MAT_URANIUM
	stack_type = /obj/item/stack/material/uranium
	icon_base = "stone"
	icon_reinf = "reinf_stone"
	icon_colour = "#007A00"
	weight = 22
	door_icon_base = "stone"
	supply_conversion_value = 2
	traits = list(MT_RADIOACTIVE = 12)

/datum/material/mhydrogen
	name = MAT_METALHYDROGEN
	display_name = "metallic hydrogen"
	stack_type = /obj/item/stack/material/mhydrogen
	icon_colour = "#E6C5DE"
	conductivity = 100
	is_fusion_fuel = 1
	supply_conversion_value = 6

/datum/material/deuterium
	name = MAT_DEUTERIUM
	stack_type = /obj/item/stack/material/deuterium
	icon_colour = "#999999"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	is_fusion_fuel = 1
	supply_conversion_value = 3
	conductivity = 2

/datum/material/tritium
	name = MAT_TRITIUM
	stack_type = /obj/item/stack/material/tritium
	icon_colour = "#777777"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	is_fusion_fuel = 1
	supply_conversion_value = 4
	conductivity = 2

/datum/material/osmium
	name = MAT_OSMIUM
	stack_type = /obj/item/stack/material/osmium
	icon_colour = "#9999FF"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	conductivity = 100
	supply_conversion_value = 6

/datum/material/graphite
	name = MAT_GRAPHITE
	stack_type = /obj/item/stack/material/graphite
	flags = MATERIAL_BRITTLE
	icon_base = "solid"
	table_icon_base = "stone"
	icon_reinf = "reinf_mesh"
	icon_colour = "#333333"
	strength = 75
	weight = 15
	toughness = 88
	conductivity = 18
	heat_resistance = 90.6
	radiation_resistance = 15
	supply_conversion_value = 0.5

/datum/material/bronze
	name = MAT_BRONZE
	stack_type = /obj/item/stack/material/bronze
	icon_colour = "#EDD12F"
	icon_base = "solid"
	icon_reinf = "reinf_over"
	toughness = 60
	conductivity = 12
	supply_conversion_value = 1

/datum/material/tin
	name = MAT_TIN
	display_name = MAT_TIN
	use_name = MAT_TIN
	stack_type = /obj/item/stack/material/tin
	supply_conversion_value = 1

/datum/material/nickel
	name = MAT_NICKEL
	stack_type = /obj/item/stack/material/nickel
	icon_colour = "#aeb8aa"
	weight = 19
	strength = 58
	toughness = 60
	conductivity = 24
	heat_resistance = 72
	corrosion_resistance = 62
	supply_conversion_value = 1.5

/datum/material/chromium
	name = MAT_CHROMIUM
	stack_type = /obj/item/stack/material/chromium
	icon_colour = "#cad4da"
	weight = 16
	strength = 78
	toughness = 52
	conductivity = 18
	heat_resistance = 76
	corrosion_resistance = 92
	supply_conversion_value = 2

/datum/material/tungsten
	name = MAT_TUNGSTEN
	stack_type = /obj/item/stack/material/tungsten
	icon_colour = "#676b72"
	weight = 35
	strength = 92
	toughness = 88
	conductivity = 31
	heat_resistance = 100
	supply_conversion_value = 3

/datum/material/technical_ceramic
	name = MAT_TECH_CERAMIC
	stack_type = /obj/item/stack/material/technical_ceramic
	icon_colour = "#e1ddd0"
	icon_base = "stone"
	weight = 11
	strength = 82
	toughness = 45
	conductivity = 2
	heat_resistance = 96
	corrosion_resistance = 95
	supply_conversion_value = 2
	icon_colour = "#b2afaf"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 0.5
	strength = 50
	weight = 13

/datum/material/copper
	name = MAT_COPPER
	display_name = MAT_COPPER
	use_name = MAT_COPPER
	stack_type = /obj/item/stack/material/copper
	conductivity = 52
	icon_colour = "#af633e"
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 0.5
	weight = 13
	strength = 50

/datum/material/aluminium
	name = MAT_ALUMINIUM
	display_name = MAT_ALUMINIUM
	use_name = MAT_ALUMINIUM
	icon_colour = "#e5e2d0"
	stack_type = /obj/item/stack/material/aluminium
	sheet_singular_name = "ingot"
	sheet_plural_name = "ingots"
	supply_conversion_value = 1
	weight = 10


/transformation/stack/durasteel__durasteel_hull_sheet
CAPABILITIES(/transformation/stack/durasteel__durasteel_hull_sheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/material/durasteel/hull, 1)),
		chosen = chosen(title = "durasteel hull sheet",
			subject = /datum/material/durasteel,
			max_made = 5,
			build_time = 20,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/durasteel__durasteel_fishing_rod
CAPABILITIES(/transformation/stack/durasteel__durasteel_fishing_rod)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/material/fishing_rod/modern/strong, 1)),
		chosen = chosen(title = "durasteel fishing rod",
			subject = /datum/material/durasteel)))

/transformation/stack/durasteel__whetstone
CAPABILITIES(/transformation/stack/durasteel__whetstone)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/whetstone, 1)),
		chosen = chosen(title = "whetstone",
			subject = /datum/material/durasteel,
			build_time = 30)))

/datum/material/durasteel //Slightly nerfed protectivness

/datum/material/durasteel/hull //Severly reduces protectivness

/datum/material/titanium //Adjusted hardness, reflective, and protection
	strength = 60
	reflectivity = 0.3


/datum/material/iron //Adjusted hardness, reflective, and protection
	strength = 70
	reflectivity = 0.1


/datum/material/lead //Adjusted hardness, reflective, and protection
	strength = 60
	reflectivity = 0.1


/datum/material/gold //Adjusted reflective, and protection
	strength = 50
	reflectivity = 0.05


/datum/material/silver //Adjusted reflective, and protection
	strength = 60
	reflectivity = 0.2


/datum/material/platinum //Adjusted hardness, reflective, and protection
	strength = 60
	reflectivity = 0.0

/datum/material/uranium //Adjusted hardness, reflective, and protection
	strength = 70
	reflectivity = 0.5

/datum/material/mhydrogen //Adjusted hardness, reflective, and protection. And weight.
	strength = 75
	reflectivity = 0.4
	weight = 5

/datum/material/osmium //Adjusted hardness, reflective, and protection
	strength = 65
	reflectivity = 0.1
