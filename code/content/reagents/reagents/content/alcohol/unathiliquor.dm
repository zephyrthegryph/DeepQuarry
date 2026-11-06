/datum/reagent/ethanol/unathiliquor
	name = REAGENT_UNATHILIQUOR
	id = REAGENT_ID_UNATHILIQUOR
	description = "This barely qualifies as a drink, and could give jet fuel a run for its money. Also known to cause feelings of euphoria and numbness."
	taste_description = "spiced numbness"
	color = "#242424"
	strength = 5

	glass_name = "unathi liquor"
	glass_desc = "This barely qualifies as a drink, and may cause euphoria and numbness. Imbiber beware!"

/datum/reagent/ethanol/unathiliquor
	species_strength = alist(IS_SLIME = 0.15) // ~1/6

/datum/reagent/ethanol/unathiliquor/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		if(inert_for(M))
			return

		var/drug_strength = 10
		if(M.species.chem_strength_tox > 0)
			drug_strength *= M.species.chem_strength_tox
		drug_strength *= species_mult(M)

		M.status_at_least(STAT_DRUGGED, drug_strength)
		if(prob(10) && isturf(M.loc) && !istype(M.loc, /turf/space) && M.canmove && !M.restrained())
			step(M, pick(GLOB.cardinal))
