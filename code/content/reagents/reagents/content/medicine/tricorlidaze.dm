// Tricordrazine's healing (blood or touch) is its treatment_tags profile.

/datum/reagent/tricorlidaze
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.3,
		TREAT_BURN_CARE = 0.3,
		TREAT_OXYGENATION = 0.3,
		TREAT_ANTITOXIN = 0.4,
		TREAT_ANTIMICROBIAL = 0.3,
	)
	name = REAGENT_TRICORLIDAZE
	id = REAGENT_ID_TRICORLIDAZE
	description = REAGENT_TRICORLIDAZE + " is a topical gel produced with tricordrazine and sterilizine."
	taste_description = "bitterness"
	reagent_state = SOLID
	color = "#B060FF"
	scannable = SCANNABLE_BENEFICIAL
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG
	medallergen_type = MEDALLERGEN_TRICORD

// Tricorlidaze's topical healing is its treatment_tags profile.
/datum/reagent/tricorlidaze
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/tricorlidaze/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 3 * removed, source = src)

/datum/reagent/tricorlidaze/touch_obj(obj/O)
	..()
	if(istype(O, /obj/item/stack/medical/bruise_pack) && round(volume) >= 5)
		var/obj/item/stack/medical/bruise_pack/C = O
		var/packname = C.name
		var/to_produce = min(C.get_amount(), round(volume / 5))

		var/obj/item/stack/medical/M = C.upgrade_stack(to_produce)

		if(M && M.get_amount())
			holder.my_atom.visible_message(span_infoplain(span_bold("\The [packname]") + " bubbles."))
			remove_self(to_produce * 5)
