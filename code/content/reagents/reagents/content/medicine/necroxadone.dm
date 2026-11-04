/datum/reagent/necroxadone
	// Baseline (warm, living) action; the cryo/corpse boost mends directly.
	treatment_tags = list(TREAT_ANTITOXIN = 0.45, TREAT_GENETIC_REPAIR = 0.3, TREAT_OXYGENATION = 0.2)
	name = REAGENT_NECROXADONE
	id = REAGENT_ID_NECROXADONE
	description = "A liquid compound based upon that which is used in the cloning process. Utilized primarily in severe cases of toxic shock."
	taste_description = "meat"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#94B21C"
	metabolism = REM * 0.5
	mrate_static = TRUE
	scannable = SCANNABLE_BENEFICIAL
	affects_dead = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/necroxadone/affect_blood(mob/living/carbon/M, alien, removed)
	var/chem_effective = M.species.chem_strength_heal * species_mult(M)
	if(M.body_temperature() < 170 || (M.stat == DEAD && M.has_body_effect(/datum/body_effect/bloodpump_corpse)))
		// Kept: cold-gated status side effects.
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to harden sporadically, resulting in seizure-like twitching."))
			M.status_at_least(STAT_WEAKENED, 20)
			M.status_at_least(STAT_MUTED, 20)
			M.status_adjust(STAT_JITTERY, 4)
		// Cold/corpse-gated boost on top of the baseline treatment_tags
		// profile; the gate can't be a tag, so it mends directly.
		M.mend(TREAT_GENETIC_REPAIR, (M.stat != DEAD ? 20 : 15) * removed * chem_effective)
		M.mend(TREAT_OXYGENATION, 20 * removed * chem_effective)
		M.mend(TREAT_ANTITOXIN, 40 * removed * chem_effective)
