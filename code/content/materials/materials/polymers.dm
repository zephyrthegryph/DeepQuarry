// The polymers (doc/rewrite/proposals/chemistry_recipes.md section 9): rubber, nylon, hard plastic (bakelite), guncotton, aramid and carbon fibre. Chemistry makes the units
// (phenol and wood aldehyde, a fatty acid and sulfur, a fatty acid and diethylamine, myelamine, nitric acid on cloth); the alloy furnace polymerises them
// (code/content/materials/engineering/material_polymers.dm). Each breaks back down into those units in a grinder (code/content/refinery/grinding.dm).

/datum/material/rubber
	name = MAT_RUBBER
	stack_type = /obj/item/stack/material/rubber
	flags = MATERIAL_PADDING
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#2d2d30"
	strength = 6
	toughness = 55
	weight = 6
	conductivity = 1
	heat_resistance = 8
	corrosion_resistance = 70
	ignition_point = T0C+260
	supply_conversion_value = 2

/datum/material/nylon
	name = MAT_NYLON
	stack_type = /obj/item/stack/material/nylon
	flags = MATERIAL_PADDING
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#d8d2c2"
	strength = 30
	toughness = 45
	weight = 4
	conductivity = 1
	heat_resistance = 12
	corrosion_resistance = 65
	ignition_point = T0C+330
	supply_conversion_value = 2

/datum/material/hard_plastic
	name = MAT_HARD_PLASTIC
	stack_type = /obj/item/stack/material/hard_plastic
	flags = MATERIAL_BRITTLE
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#5b3a24"
	strength = 35
	toughness = 20
	weight = 10
	conductivity = 1
	heat_resistance = 40
	corrosion_resistance = 85
	supply_conversion_value = 2

/datum/material/guncotton
	name = MAT_GUNCOTTON
	stack_type = /obj/item/stack/material/guncotton
	flags = MATERIAL_PADDING
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#f1efe6"
	strength = 3
	toughness = 4
	weight = 1
	conductivity = 1
	heat_resistance = 4
	ignition_point = T0C+180 // a nitrated cellulose: flash paper, propellant
	supply_conversion_value = 4

/datum/material/aramid
	name = MAT_ARAMID
	stack_type = /obj/item/stack/material/aramid
	flags = MATERIAL_PADDING
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#d6b83c"
	strength = 70
	toughness = 80
	weight = 3
	conductivity = 1
	heat_resistance = 55
	corrosion_resistance = 60
	supply_conversion_value = 6

/datum/material/carbon_fibre
	name = MAT_CARBON_FIBRE
	stack_type = /obj/item/stack/material/carbon_fibre
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#26272b"
	strength = 85
	toughness = 40
	weight = 3
	conductivity = 12
	heat_resistance = 75
	corrosion_resistance = 90
	supply_conversion_value = 8

// The sheets. They are made in the furnace, not printed (no autolathe design: exotic_no_autolathe_reprint).

/obj/item/stack/material/rubber
	name = MAT_RUBBER
	icon_state = "sheet-plastic"
	default_type = MAT_RUBBER
	no_variants = FALSE
	apply_colour = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/nylon
	name = MAT_NYLON
	icon_state = "sheet-cloth"
	default_type = MAT_NYLON
	no_variants = FALSE
	apply_colour = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/hard_plastic
	name = MAT_HARD_PLASTIC
	icon_state = "sheet-plastic"
	default_type = MAT_HARD_PLASTIC
	no_variants = FALSE
	apply_colour = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/guncotton
	name = MAT_GUNCOTTON
	icon_state = "sheet-cloth"
	default_type = MAT_GUNCOTTON
	no_variants = FALSE
	apply_colour = TRUE
	resistance_flags = FLAMMABLE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/aramid
	name = MAT_ARAMID
	icon_state = "sheet-cloth"
	default_type = MAT_ARAMID
	no_variants = FALSE
	apply_colour = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/carbon_fibre
	name = MAT_CARBON_FIBRE
	icon_state = "sheet-plastic"
	default_type = MAT_CARBON_FIBRE
	no_variants = FALSE
	apply_colour = TRUE
	exotic_no_autolathe_reprint = TRUE
