/datum/reagent/osteodaxon
	treatment_tags = list(TREAT_BONE_REPAIR = 1.0, TREAT_TISSUE_REPAIR = 0.3)
	name = REAGENT_OSTEODAXON
	id = REAGENT_ID_OSTEODAXON
	description = "An experimental drug used to heal bone fractures."
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C9BCE3"
	metabolism = REM * 0.5
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/osteodaxon
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/osteodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	// Light tissue repair ("gives the bones a chance to set") is in the treatment_tags profile.
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/totalvol = 0
		if(H.ingested)
			for(var/datum/reagent/R in H.ingested.reagent_list)
				if(istype(R,/datum/reagent/osteodaxon))
					totalvol += R.volume
		totalvol += volume
		if(totalvol >= 1)
			for(var/obj/item/organ/external/O in H.damaged_limbs())
				if(dq_reagent_knit_fracture(O))
					H.custom_pain(span_danger(span_normal(span_bold("You feel a terrible agony tear through your [O.name]!"))),60,TRUE)
					H.status_adjust(STAT_WEAKENED, 10)		//Bones being regrown will knock you over
					H.injure(INJURY_PAIN, 60, O.organ_tag, source = src)
					H.status_adjust(STAT_STUNNED, 1)		//Bones being regrown will knock you over
