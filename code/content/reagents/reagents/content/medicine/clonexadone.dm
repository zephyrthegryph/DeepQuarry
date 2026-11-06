/datum/reagent/clonexadone
	name = REAGENT_CLONEXADONE
	id = REAGENT_ID_CLONEXADONE
	description = "A liquid compound similar to that used in the cloning process. Can be used to 'finish' the cloning process when used in conjunction with a cryo tube."
	taste_description = "rotten bananas"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#80BFFF"
	metabolism = REM * 0.5
	mrate_static = TRUE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/clonexadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.body_temperature() < 170)
		var/chem_effective = M.species.chem_strength_heal * species_mult(M)
		// Kept: temperature-gated status side effects.
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to harden sporadically, resulting in seizure-like twitching."))
			M.status_at_least(STAT_WEAKENED, 20)
			M.status_at_least(STAT_MUTED, 20)
			M.status_adjust(STAT_JITTERY, 4)
		// Temperature-gated (see cryoxadone): mends directly.
		dq_cryo_mend(M, 30 * removed * chem_effective)
