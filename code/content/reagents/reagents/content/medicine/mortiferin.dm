/datum/reagent/mortiferin
	name = REAGENT_MORTIFERIN
	id = REAGENT_ID_MORTIFERIN
	description = "A liquid compound based upon those used in cloning. Utilized in cases of toxic shock. May cause liver damage."
	taste_description = "meat"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#6b4de3"
	metabolism = REM * 0.5
	mrate_static = TRUE
	affects_dead = FALSE //Clarifying this here since the original intent was this ONLY works on people that have the bloodpump_corpse modifier.
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	species_strength = alist(IS_SLIME = 0.5)

/datum/reagent/mortiferin/on_mob_life(mob/living/carbon/M, alien, datum/reagents/metabolism/location)
	. = ..(M, alien, location)

/datum/reagent/mortiferin/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.body_temperature() < (T0C - 10) || (M.stat == DEAD))
		var/chem_effective = M.species.chem_strength_heal * species_mult(M)
		// Kept: cold-gated status side effects.
		if(alien == IS_SLIME)
			if(prob(10))
				to_chat(M, span_danger("It's so cold. Something causes your cellular mass to solidify sporadically, resulting in uncontrollable twitching."))
			M.status_at_least(STAT_WEAKENED, 10)
			M.status_at_least(STAT_MUTED, 10)
			M.status_adjust(STAT_JITTERY, 4)
		// Cold- or death-gated: mends directly (a tag can't express the gate).
		if(M.stat != DEAD)
			M.mend(TREAT_GENETIC_REPAIR, 5 * removed * chem_effective)
		M.mend(TREAT_OXYGENATION, 10 * removed * chem_effective)
		M.mend(TREAT_ANTITOXIN, 20 * removed * chem_effective)

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
			if(istype(L) && prob(5))
				if(L.is_robotic())
					return

				H.injure(INJURY_TOXIN, rand(1,3) * removed, L, src, flags = INJURE_IGNORE_RESISTANCE)
