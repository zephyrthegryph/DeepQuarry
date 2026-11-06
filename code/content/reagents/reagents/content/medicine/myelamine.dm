/datum/reagent/myelamine
	// The clotting agent: runs down bleeds; its wound closure is affect_blood.
	treatment_tags = list(TREAT_HEMOSTATIC = 1.0)
	name = REAGENT_MYELAMINE
	id = REAGENT_ID_MYELAMINE
	description = "Used to rapidly clot hemorrhages by increasing the effectiveness of platelets. An ideal dosage of 10 units will fully heal any internal hemorrhages."
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#4246C7"
	metabolism = REM * 0.75
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	var/repair_strength = 6
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/myelamine
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/myelamine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + (repair_strength * removed), 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength
		// B13: clotting through mend(): one wound per limb dressed (the clot), its
		// damage repaired, and internal bleeds closed by vessel repair.
		var/sweet_zone = (dose >= 9.5 && dose < 11) // a 10u pen or pill fixes internal bleeding outright
		for(var/obj/item/organ/external/O as anything in H.organs)
			if(!LAZYLEN(O.get_wounds()))
				continue
			H.mend(TREAT_WOUND_PACKING, 1, O)
			H.mend(TREAT_TISSUE_REPAIR, wound_heal * 3.5, O)
			H.mend(TREAT_VESSEL_REPAIR, sweet_zone ? DQ_REAGENT_KNIT_AMOUNT : wound_heal, O)

/datum/reagent/myelamine/overdose(mob/living/carbon/M, alien, removed)
	//Heals slightly faster at the cost of high toxins. Honestly you should never do this, but whatever.
	..()
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength / 2
		for(var/obj/item/organ/external/O as anything in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal, bleeding = FALSE)
