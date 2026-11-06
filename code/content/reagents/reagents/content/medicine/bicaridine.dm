/datum/reagent/bicaridine
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.0, TREAT_BONE_REPAIR = 0.3, TREAT_HEMOSTATIC = 0.2)
	name = REAGENT_BICARIDINE
	id = REAGENT_ID_BICARIDINE
	description = REAGENT_BICARIDINE + " is an analgesic medication and can be used to treat blunt trauma."
	taste_description = "bitterness"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 0.25
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	medallergen_type = MEDALLERGEN_BICARD

// Bicaridine's trauma repair is its treatment_tags profile (body/treatment.dm).

/datum/reagent/bicaridine/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 2.5 * removed
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + wound_heal, 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.organs)
			dq_reagent_close_wounds(O, wound_heal)

/datum/reagent/bicaridine/topical
	treatment_tags = list(TREAT_HEMOSTATIC = 1.0, TREAT_BONE_REPAIR = 1.0, TREAT_TISSUE_REPAIR = 0.6, TREAT_NEURAL_REPAIR = 0.3)
	name = REAGENT_BICARIDAZE
	id = REAGENT_ID_BICARIDAZE
	description = REAGENT_BICARIDAZE + " is a topical variant of the chemical Bicaridine."
	taste_description = "bitterness"
	taste_mult = 3
	reagent_state = LIQUID
	color = "#BF0000"
	overdose = REAGENTS_OVERDOSE * 0.75
	scannable = SCANNABLE_BENEFICIAL
	touch_met = REM * 0.75
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_BICARD

/datum/reagent/bicaridine/topical
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/bicaridine/topical/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 2 * removed, source = src)
