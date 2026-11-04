/datum/reagent/cryoxadone
	name = REAGENT_CRYOXADONE
	id = REAGENT_ID_CRYOXADONE
	description = "A chemical mixture with almost magical healing powers. Its main limitation is that the targets body temperature must be under 170K for it to metabolise correctly."
	taste_description = "overripe bananas"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#8080FF"
	metabolism = REM * 0.5
	mrate_static = TRUE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.25)

/datum/reagent/cryoxadone/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.body_temperature() < 170)
		var/chem_effective = M.species.chem_strength_heal * species_mult(M)
		// Kept: temperature-gated status side effects.
		if(alien == IS_SLIME)
			to_chat(M, span_danger("It's cold. Something causes your cellular mass to harden occasionally, resulting in vibration."))
			M.status_at_least(STAT_WEAKENED, 10)
			M.status_at_least(STAT_MUTED, 10)
			M.status_adjust(STAT_JITTERY, 4)
		// Only works below 170K, a gate a continuous treatment tag can't
		// express, so the cryo-healing mends directly.
		dq_cryo_mend(M, 10 * removed * chem_effective)
