/datum/reagent/flamecure
	name = REAGENT_FLAMECURE
	id = REAGENT_ID_FLAMECURE
	description = "Used to rapidly clot internal hemorrhages by burning the wounded areas"
	reagent_state = LIQUID
	color = "#4246C7"
	overdose = REAGENTS_OVERDOSE * 0.5
	dermal_absorption = 0.2
	scannable = 1
	var/repair_strength = 9
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/flamecure
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/flamecure/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_set(STAT_BLURRY, min(M.status_units(STAT_BLURRY) + (repair_strength * removed), 250))
	// The legacy negative burn-heal here was a burn (twice for humans).
	M.injure(INJURY_BURN, (ishuman(M) ? 2 : 1) * removed, source = src)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = removed * repair_strength
		for(var/obj/item/organ/external/O in H.damaged_limbs())
			dq_reagent_close_wounds(O, wound_heal)
