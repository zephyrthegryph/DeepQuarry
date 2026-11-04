/datum/reagent/peridaxon
	// Generic organ support: weak on every organ-repair mechanism.
	treatment_tags = list(
		TREAT_OCULAR = 0.3,
		TREAT_RESPIRATORY = 0.3,
		TREAT_HEPATORENAL = 0.3,
		TREAT_CARDIAC = 0.3,
		TREAT_DIGESTIVE = 0.3,
	)
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 20))
	name = REAGENT_PERIDAXON
	id = REAGENT_ID_PERIDAXON
	description = "Used to encourage recovery of internal organs and nervous systems. Medicate cautiously."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#561EC3"
	overdose = 10
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_PERIDAX

/datum/reagent/peridaxon/affect_blood(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/internal/I in H.internal_organ_list())
			if(I.is_robotic())
				continue
			if(I.damage > 0) // Repair is peridaxon's organ tags; the confusion is its side effect.
				H.status_at_least(STAT_CONFUSED, 5)
			if(I.damage <= 5 && I.organ_tag == O_EYES)
				H.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + 10, 250)) //Eyes need to reset, or something
				H.set_sdisabilities(H.sdisabilities & (~BLIND))
		if(alien == IS_SLIME)
			if(prob(33))
				H.status_at_least(STAT_CONFUSED, 10)

/datum/reagent/peridaxon/overdose(mob/living/carbon/M, alien, removed)
	..()
	M.injure(INJURY_PAIN, 5, source = src)
	M.status_at_least(STAT_HALLUCINATING, 10)
