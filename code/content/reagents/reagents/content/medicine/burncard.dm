// Purifying agent's antitoxin and anti-radiation action are its treatment_tags profile.

//liquid fire
/datum/reagent/burncard
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.5)
	name = REAGENT_BURNCARD
	id = REAGENT_ID_BURNCARD
	description = "A more powerful variation of bicard that also burns the subject."
	taste_description = "bitterness"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE * 0.2
	dermal_absorption = 0.2
	overdose_mod = 1.25
	scannable = 1
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/burncard
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/burncard/affect_blood(mob/living/carbon/M, alien, removed)
	// Trauma repair is the treatment_tags profile; liquid fire still burns.
	M.injure(INJURY_BURN, 1 * removed, source = src)

/datum/reagent/burncard/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 3 * removed
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + wound_heal, 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal)
