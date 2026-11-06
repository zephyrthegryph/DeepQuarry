/datum/reagent/coolant
	// Only synthetic parts respond (TREAT_COOLANT is a synthetic mechanism).
	treatment_tags = list(TREAT_COOLANT = 1.0)
	name = REAGENT_COOLANT
	id = REAGENT_ID_COOLANT
	description = "Industrial cooling substance."
	taste_description = "sourness"
	taste_mult = 1.1
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#C8A5DC"

	affects_robots = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY
	coolant_modifier = 2 // In the name

/datum/reagent/coolant/affect_blood(mob/living/carbon/M, alien, removed)
	if(HAS_SYNTHETIC_BIOLOGY(M) && ishuman(M))
		var/mob/living/carbon/human/H = M

		var/datum/reagent/blood/coolant = H.get_blood(H.vessel)

		if(coolant)
			H.vessel.add_reagent(REAGENT_ID_BLOOD, removed, coolant.data)

		else
			H.vessel.add_reagent(REAGENT_ID_BLOOD, removed)
			H.fixblood()

	else
		..()
