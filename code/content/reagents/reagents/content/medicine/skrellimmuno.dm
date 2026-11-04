/datum/reagent/skrellimmuno //skrell exist?
	name = REAGENT_MALISHQUALEM
	id = REAGENT_ID_MALISHQUALEM
	description = "A strange, oily powder used by Malish-Katish to prevent organ rejection."
	taste_description = "mordant"
	reagent_state = SOLID
	dermal_absorption = 0
	color = "#84B2B0"
	metabolism = REM * 0.06
	overdose = 20
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	/// Skrell take none of the rejection toxin (a multiplier on that toxin only).
	species_strength = alist(IS_SKRELL = 0)

/datum/reagent/skrellimmuno/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = 0.5 * M.species.chem_strength_heal
	// B16: a species with no healing strength must not divide the rejection toxin by zero.
	var/toxin_divisor = max(strength_mod, 0.1)

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/toxin_mult = species_mult(H)
		if(toxin_mult)
			H.injure(INJURY_TOXIN, 20 * removed * toxin_mult, source = src)

		var/list/organtotal = list()
		organtotal |= H.organs
		organtotal |= H.internal_organ_list()

		for(var/obj/item/organ/I in organtotal)	// Don't mess with robot bits, they don't reject.
			if(I.is_robotic())
				organtotal -= I

		if(dose >= 15)
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data && prob(round(15 * strength_mod)))
					I.rejecting = 0
					I.can_reject = FALSE

		if(H.body?.treatment_levels()?[TREAT_ANTIMICROBIAL]) // P2-K6: the mechanism, not the reagent IDs
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data)
					var/rejectmem = I.can_reject
					I.can_reject = initial(I.can_reject)
					if(rejectmem != I.can_reject)
						H.injure(INJURY_TOXIN, (10 / toxin_divisor) * removed, source = src) // B16: per unit metabolised
						H.injure(INJURY_TOXIN, 1, I, src, flags = INJURE_IGNORE_RESISTANCE)
