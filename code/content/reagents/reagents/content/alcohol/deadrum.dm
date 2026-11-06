/datum/reagent/ethanol/deadrum
	name = REAGENT_DEADRUM
	id = REAGENT_ID_DEADRUM
	description = "Popular with the sailors. Not very popular with everyone else."
	taste_description = "butterscotch and salt"
	taste_mult = 1.1
	color = "#ECB633"
	strength = 50

	glass_name = "rum"
	glass_desc = "Now you want to Pray for a pirate suit, don't you?"

/datum/reagent/ethanol/deadrum/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		M.status_adjust(STAT_DIZZY, 5)
