/datum/reagent/toxin/amatoxin
	name = REAGENT_AMATOXIN
	id = REAGENT_ID_AMATOXIN
	description = "A powerful poison derived from certain species of mushroom."
	taste_description = "mushroom"
	reagent_state = LIQUID
	color = "#792300"
	strength = 10
	poison_affliction = /datum/affliction/poisoning/amatoxin
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/amatoxin/affect_blood(mob/living/carbon/M, alien, removed)
	// Trojan horse. Waits until most of the toxin has gone through the body before dealing the bulk of it in one big strike.
	if(volume < max_dose * 0.1)
		M.injure(INJURY_TOXIN, max_dose * strength, source = src, affliction = poison_affliction) //Get hit all at once.
		M.reagents.del_reagent(REAGENT_ID_AMATOXIN) //Remove the rest of ourselves.
