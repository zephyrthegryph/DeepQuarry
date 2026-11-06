/datum/reagent/lube // TODO: spraying on borgs speeds them up
	name = REAGENT_LUBE
	id = REAGENT_ID_LUBE
	description = "Lubricant is a substance introduced between two moving surfaces to reduce the friction and wear between them. giggity."
	taste_description = "slime"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#009CA8"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_LUBE

/datum/reagent/lube/touch_turf(turf/simulated/T)
	..()
	if(!istype(T))
		return
	if(volume >= 1)
		T.wet_floor(2)
