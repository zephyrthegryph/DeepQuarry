/datum/reagent/ethanol/beepsky_smash
	name = REAGENT_BEEPSKYSMASH
	id = REAGENT_ID_BEEPSKYSMASH
	description = "Deny drinking this and prepare for THE LAW."
	taste_description = "whiskey and citrus"
	taste_mult = 2
	reagent_state = LIQUID
	color = "#404040"
	strength = 12

	glass_name = REAGENT_BEEPSKYSMASH
	glass_desc = "Heavy, hot and strong. Just like the Iron fist of the LAW."

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from whiskey(grains), and limejuice(fruit)

/datum/reagent/ethanol/beepsky_smash/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		M.status_at_least(STAT_STUNNED, 2)
