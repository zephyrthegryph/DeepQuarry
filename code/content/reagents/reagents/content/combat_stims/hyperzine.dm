/datum/reagent/hyperzine
	treatment_tags = list(TREAT_STIMULANT = 1.0)
	factors = alist(STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_HYPERZINE
	id = REAGENT_ID_HYPERZINE
	description = REAGENT_HYPERZINE + " is a highly effective, long lasting, muscle stimulant."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FF3300"
	overdose = REAGENTS_OVERDOSE * 0.5
	scannable = SCANNABLE_ADVANCED
	overdose_mod = 0.25
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COMSTIM
	species_strength = alist(IS_TAJARA = 1.25)

/datum/reagent/hyperzine/affect_blood(mob/living/carbon/M, alien, removed)
	removed *= species_mult(M)
	// Kept: a species-only, dose-gated status/nutrition side effect.
	if(alien == IS_SLIME)
		M.status_adjust(STAT_JITTERY, 4) //Hyperactive fluid pumping results in unstable 'skeleton', resulting in vibration.
		if(dose >= 5)
			M.adjust_nutrition(-removed * 2) // Sadly this movement starts burning food in higher doses.
	..()
	if(prob(5))
		M.emote(pick("twitch", "blink_r", "shiver"))

/datum/reagent/hyperzine/overdose(mob/living/carbon/M, alien, removed)
	..()
	if(prob(5)) // 1 in 20
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/heart/ht = H.organ_in(O_HEART)
		if(ht)
			H.injure(INJURY_BLUNT, 1, ht, src, flags = INJURE_IGNORE_RESISTANCE)
		to_chat(M, span_warning("Huh... Is this what a heart attack feels like?"))
