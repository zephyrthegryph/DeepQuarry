/datum/reagent/immunosuprizine
	name = REAGENT_IMMUNOSUPRIZINE
	id = REAGENT_ID_IMMUNOSUPRIZINE
	description = "An experimental powder believed to have the ability to prevent any organ rejection."
	taste_description = "flesh"
	reagent_state = SOLID
	dermal_absorption = 0
	color = "#7B4D4F"
	overdose = 20
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	metabolism = REM * 0.06
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	// Diona: it's a tree. Slime: difficulty bonding with internal cellular structure.
	// Unathi: natural regeneration, robust biology. Tajara: highest metabolism.
	species_strength = alist(IS_DIONA = 4, IS_SLIME = 1.3, IS_UNATHI = 0.6, IS_TAJARA = 0.5)

/datum/reagent/immunosuprizine/affect_blood(mob/living/carbon/M, alien, removed)
	var/strength_mod = species_mult(M) // * M.species.chem_strength_heal //Just removing the chem strength adjustment. It'd require division, which is best avoided.

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!inert_for(H)) // inert_species (diona): no rejection toxin
			H.injure(INJURY_TOXIN, (30 * strength_mod) * removed, source = src)

		var/list/organtotal = list()
		organtotal |= H.organs
		organtotal |= H.internal_organ_list()

		for(var/obj/item/organ/I in organtotal)	// Don't mess with robot bits, they don't reject.
			if(I.is_robotic())
				organtotal -= I

		if(dose >= 15)
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data && prob(round(15 * strength_mod)))	// Reset the rejection process, toggle it to not reject.
					I.rejecting = 0
					I.can_reject = FALSE

		if(H.body?.treatment_levels()?[TREAT_ANTIMICROBIAL]) // P2-K6: the mechanism, not the reagent IDs	// Chemicals that increase your immune system's aggressiveness make this chemical's job harder.
			for(var/obj/item/organ/I in organtotal)
				if(I.transplant_data)
					var/rejectmem = I.can_reject
					I.can_reject = initial(I.can_reject)
					if(rejectmem != I.can_reject)
						H.injure(INJURY_TOXIN, (15 / strength_mod) * removed, source = src) //Someone forgot a * removed here in the past. It made it so 1u of this chem would do (baseline) 1245 toxins per unit, or 15 toxins per tick.
						H.injure(INJURY_TOXIN, 1, I, src, flags = INJURE_IGNORE_RESISTANCE)
