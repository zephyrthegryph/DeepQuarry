/datum/reagent/toxin/carpotoxin
	name = REAGENT_CARPOTOXIN
	id = REAGENT_ID_CARPOTOXIN
	description = "A deadly neurotoxin produced by the dreaded space carp."
	taste_description = "fish"
	reagent_state = LIQUID
	dermal_absorption = 0.4
	color = "#003333"
	strength = 10
	poison_affliction = /datum/affliction/poisoning/neurotoxin
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/carpotoxin/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	M.injure(INJURY_NEURAL, strength / 4 * removed, source = src)
