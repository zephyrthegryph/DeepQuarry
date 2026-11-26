/datum/reagent/bicaridine
	treatment_tags = list(TREAT_TISSUE_REPAIR = 1.0, TREAT_BONE_REPAIR = 0.3, TREAT_HEMOSTATIC = 0.2)
	// Raises the metabolism: bicaridine and every other drug in the blood clear faster, and the patient grows hungry.
	factors = alist(STAT_METABOLISM_MULT = 1.5)
	name = REAGENT_BICARIDINE
	id = REAGENT_ID_BICARIDINE
	description = REAGENT_BICARIDINE + " is a trauma drug that repairs cuts, bruises and other blunt soft-tissue damage. It speeds up the metabolism, so every drug in the blood (itself included) clears faster and the patient grows hungry; an overdose thins the blood and makes the patient bleed."
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
	/// Nutrition burned per unit metabolised in the blood (the raised metabolism's hunger).
	var/hunger_per_unit = 10

/datum/reagent/bicaridine/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjust_nutrition(-hunger_per_unit * removed)

// Bicaridine's trauma repair is its treatment_tags profile (body/treatment.dm).

/datum/reagent/bicaridine/overdose(mob/living/carbon/M, alien, removed)
	..()
	var/wound_heal = 2.5 * removed
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + wound_heal, 250))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/obj/item/organ/external/O in H.organs)
			dq_reagent_close_wounds(O, wound_heal)
