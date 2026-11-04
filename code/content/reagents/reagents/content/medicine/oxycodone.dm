/datum/reagent/oxycodone
	factors = alist(STAT_ANALGESIA = 200, STAT_SLOWDOWN = 1, STAT_PENALTY_SCALE = 1.25)
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 150, STAT_SLOWDOWN = 1, STAT_PENALTY_SCALE = 1.25))
	name = REAGENT_OXYCODONE
	id = REAGENT_ID_OXYCODONE
	description = "An effective and very addictive painkiller."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#800080"
	overdose = 20
	overdose_mod = 0.75
	scannable = SCANNABLE_BENEFICIAL
	metabolism = 0.02
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	species_strength = alist(IS_SLIME = 0.75)

/datum/reagent/oxycodone/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_pain * species_mult(M)
	// Kept: a species-only status side effect.
	if(alien == IS_SLIME)
		M.status_set(STAT_STUTTERING, min(50, max(0, M.status_units(STAT_STUTTERING) + 5))) //If you can't feel yourself, and your main mode of speech is resonation, there's a problem.
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + 10, 250 * chem_effective))

/datum/reagent/oxycodone/overdose(mob/living/carbon/M, alien)
	..()
	M.status_at_least(STAT_DRUGGED, 10)
	M.status_at_least(STAT_HALLUCINATING, 3)
