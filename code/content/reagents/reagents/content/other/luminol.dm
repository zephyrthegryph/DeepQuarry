/datum/reagent/luminol
	name = REAGENT_LUMINOL
	id = REAGENT_ID_LUMINOL
	scannable = SCANNABLE_ADVANCED
	description = "A compound that interacts with blood on the molecular level."
	taste_description = "metal"
	reagent_state = LIQUID
	color = "#F2F3F4"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/luminol/touch_obj(obj/O)
	..()
	O.reveal_blood()

/datum/reagent/luminol/touch_mob(mob/living/L)
	..()
	L.reveal_blood()
