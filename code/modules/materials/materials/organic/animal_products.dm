/datum/material/diona
	name = MAT_BIOMASS
	material_class = MATCLASS_ORGANIC
	icon_colour = null
	stack_type = null
	integrity = 600
	icon_base = "diona"
	icon_reinf = "noreinf"
	supply_conversion_value = 1

/datum/material/diona/place_dismantled_product()
	return

/datum/material/diona/place_dismantled_girder(turf/target)
	spawn_diona_nymph(target)

/datum/material/chitin
	name = MAT_CHITIN
	material_class = MATCLASS_ORGANIC
	icon_colour = "#8d6653"
	stack_type = /obj/item/stack/material/chitin
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	integrity = 60
	density = 10
	ignition_point = T0C+400
	melting_point = T0C+500
	protectiveness = 20
	conductive = 0
	supply_conversion_value = 4


// === merged from animal_products_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/material/chitin
	protectiveness = 25
	reflectivity = 0.05


/datum/material/deathclawscale
	name = "deathclaw scale"
	material_class = MATCLASS_ORGANIC // DQEdit — class assignment
	icon_colour = "#8d6653"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	hardness = 50
	protectiveness = 40
	reflectivity = 0.4
	conductivity = 1
	supply_conversion_value = 0

/datum/material/dragonscale
	name = "dragon scale"
	material_class = MATCLASS_ORGANIC // DQEdit — class assignment
	icon_colour = "#ffffff"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	hardness = 50
	protectiveness = 75
	reflectivity = 0.6
	conductivity = 1
	supply_conversion_value = 0

/datum/material/phorondragonscale
	name = "phoron dragon scale"
	material_class = MATCLASS_ORGANIC // DQEdit — class assignment
	icon_colour = "#8d6653"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	hardness = 10
	protectiveness = 80
	reflectivity = 0.8
	conductivity = 1
	supply_conversion_value = 0

/datum/material/xenochitin
	name = "xenochitin"
	material_class = MATCLASS_ORGANIC // DQEdit — class assignment
	icon_colour = "#8d6653"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	hardness = 40
	protectiveness = 40
	reflectivity = 0.6
	conductivity = 0.5
	supply_conversion_value = 0
