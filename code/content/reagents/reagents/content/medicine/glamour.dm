/datum/reagent/glamour
	name = REAGENT_GLAMOUR
	id = REAGENT_ID_GLAMOUR
	description = "This material is from somewhere else, just being near produces changes."
	taste_description = "change"
	dermal_absorption = 1 //Magic liquid stuff. It immediately clears itself in your system the moment it touches you, so whatever.
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_SECRETIVE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/glamour/affect_blood(mob/living/carbon/target, removed)
	grant(target, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), target)
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()
