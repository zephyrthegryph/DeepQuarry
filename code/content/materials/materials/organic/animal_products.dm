/datum/material/diona
	name = MAT_BIOMASS
	icon_colour = null
	stack_type = null
	toughness = 300
	icon_base = "diona"
	icon_reinf = "noreinf"
	supply_conversion_value = 1

/datum/material/diona/place_dismantled_product()
	return

/datum/material/diona/place_dismantled_girder(turf/target)
	spawn_diona_nymph(target)

/datum/material/chitin
	name = MAT_CHITIN
	icon_colour = "#8d6653"
	stack_type = /obj/item/stack/material/chitin
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	toughness = 30
	weight = 10
	ignition_point = T0C+400
	heat_resistance = 13.1
	supply_conversion_value = 4
	conductivity = 2


/datum/material/chitin
	reflectivity = 0.05


/datum/material/deathclawscale
	name = "deathclaw scale"
	icon_colour = "#8d6653"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	strength = 50
	reflectivity = 0.4
	conductivity = 8
	supply_conversion_value = 0

/datum/material/dragonscale
	name = "dragon scale"
	icon_colour = "#ffffff"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	strength = 50
	reflectivity = 0.6
	conductivity = 8
	supply_conversion_value = 0

/datum/material/phorondragonscale
	name = "phoron dragon scale"
	icon_colour = "#8d6653"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	strength = 10
	reflectivity = 0.8
	conductivity = 8
	supply_conversion_value = 0

/datum/material/xenochitin
	name = "xenochitin"
	icon_colour = "#8d6653"
	icon_base = "solid"
	icon_reinf = "reinf_mesh"
	strength = 40
	reflectivity = 0.6
	conductivity = 8
	supply_conversion_value = 0
