/datum/reagent/imidazoline
	treatment_tags = list(TREAT_OCULAR = 1.0)
	// Repairs the eyes but leaves them sensitive: a flash that lands blinds for twice as long while it is in the blood.
	factors = alist(STAT_FLASH_VULNERABILITY = 2)
	name = REAGENT_IMIDAZOLINE
	id = REAGENT_ID_IMIDAZOLINE
	description = "Heals eye damage and clears blurred vision. The healing eyes are light-sensitive: while the drug is in the blood, a bright flash blinds the patient for longer."
	taste_description = "dull toxin"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8A5DC"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/imidazoline/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_BLURRY, -5)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if(istype(E))
			if(E.is_robotic())
				return
			// Eye repair is imidazoline's TREAT_OCULAR tag (body/treatment.dm).
			if(E.damage <= 5 && E.organ_tag == O_EYES)
				H.set_sdisabilities(H.sdisabilities & (~BLIND))
