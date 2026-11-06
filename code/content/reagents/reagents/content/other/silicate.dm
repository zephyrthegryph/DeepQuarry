/datum/reagent/silicate
	name = REAGENT_SILICATE
	id = REAGENT_ID_SILICATE
	description = "A compound that can be used to reinforce glass."
	taste_description = "plastic"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#C7FFFF"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/silicate/touch_obj(obj/O)
	..()
	if(istype(O, /obj/structure/window))
		var/obj/structure/window/W = O
		W.apply_silicate(volume)
		remove_self(volume)
	return
