/mob/living/carbon/human/proc/update_eyes()
	var/obj/item/organ/internal/eyes/eyes = organ_in(O_EYES)
	if(eyes)
		eyes.update_colour()
		update_icons_body() //Body handles eyes
		update_eyes() //For floating eyes only

/mob/living/carbon/human/proc/handle_grasp()
	if(!get_equipped_item(SLOT_ID_HAND_L) && !get_equipped_item(SLOT_ID_HAND_R))
		return

	// You should not be able to pick anything up, but stranger things have happened.
	if(get_equipped_item(SLOT_ID_HAND_L))
		for(var/limb_tag in list(BP_L_HAND, BP_L_ARM))
			var/obj/item/organ/external/E = get_organ(limb_tag)
			if(!E)
				act_message(src, null, others = span_danger("Lacking a functioning left hand, %U% drops \the [get_equipped_item(SLOT_ID_HAND_L)]."))
				drop_from_inventory(get_equipped_item(SLOT_ID_HAND_L))
				break

	if(get_equipped_item(SLOT_ID_HAND_R))
		for(var/limb_tag in list(BP_R_HAND, BP_R_ARM))
			var/obj/item/organ/external/E = get_organ(limb_tag)
			if(!E)
				act_message(src, null, others = span_danger("Lacking a functioning right hand, %U% drops \the [get_equipped_item(SLOT_ID_HAND_R)]."))
				drop_from_inventory(get_equipped_item(SLOT_ID_HAND_R))
				break

	// Check again...
	if(!get_equipped_item(SLOT_ID_HAND_L) && !get_equipped_item(SLOT_ID_HAND_R))
		return
	var/adrenaline = has_body_effect(/datum/body_effect/adrenaline)
	for (var/obj/item/organ/external/E in organs)
		if(!E || !E.can_grasp)
			continue

		if((E.is_broken() || E.is_dislocated()) && !E.splinted && !adrenaline)
			switch(E.body_part)
				if(HAND_LEFT, ARM_LEFT)
					if(!get_equipped_item(SLOT_ID_HAND_L))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_HAND_L))
				if(HAND_RIGHT, ARM_RIGHT)
					if(!get_equipped_item(SLOT_ID_HAND_R))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_HAND_R))

			if(!isbelly(loc))
				var/emote_scream = pick("screams in pain and ", "lets out a sharp cry and ", "cries out and ")
				automatic_custom_emote(VISIBLE_MESSAGE, "[(can_feel_pain()) ? "" : emote_scream ]drops what they were holding in their [E.name]!", check_stat = TRUE)
				if(can_feel_pain())
					emote("pain")

		else if(E.is_malfunctioning())
			switch(E.body_part)
				if(HAND_LEFT, ARM_LEFT)
					if(!get_equipped_item(SLOT_ID_HAND_L))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_HAND_L))
				if(HAND_RIGHT, ARM_RIGHT)
					if(!get_equipped_item(SLOT_ID_HAND_R))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_HAND_R))

			if(!isbelly(loc))
				automatic_custom_emote(VISIBLE_MESSAGE, "drops what they were holding, their [E.name] malfunctioning!", check_stat = TRUE)

				fx_sparks(src, 5, FALSE)

//Handles chem traces
/mob/living/carbon/human/proc/handle_trace_chems()
	//New are added for reagents to random organs.
	for(var/datum/reagent/A in reagents.reagent_list)
		var/obj/item/organ/O = pick(organs)
		LAZYSET(O.trace_chemicals, A.name, 100)

// Traitgenes Init genes based on the traits currently active
/mob/living/carbon/human/proc/sync_dna_traits(refresh_traits, hide_message = TRUE)
	SHOULD_NOT_OVERRIDE(TRUE) //Don't. Even. /Think/. About. It.
	if(!dna || !species)
		return
	// Traitgenes NO_DNA and Synthetics cannot be mutated
	if(HAS_SYNTHETIC_BIOLOGY(src))
		return
	if(species.flags & NO_DNA)
		return
	if(refresh_traits && species.traits)
		for(var/TR in species.traits)
			var/datum/trait/T = GLOB.all_traits[TR]
			if(!T)
				continue
			if(!T.linked_gene)
				continue
			var/datum/gene/trait/gene = T.linked_gene
			dna.SetSEState(gene.block, TRUE, TRUE)
		dna.UpdateSE()
	var/flgs = MUTCHK_FORCED
	if(hide_message)
		flgs |= MUTCHK_HIDEMSG
	domutcheck( src, null, flgs)

/mob/living/carbon/human/proc/sync_organ_dna()
	var/list/all_bits = internal_organ_list()|organs
	for(var/obj/item/organ/O in all_bits)
		O.set_dna(dna)

/mob/living/carbon/human/proc/set_gender(g)
	if(g != gender)
		gender = g

	if(dna.GetUIState(DNA_UI_GENDER) ^ gender == FEMALE) // XOR will catch both cases where they do not match
		dna.SetUIState(DNA_UI_GENDER, gender == FEMALE)
		sync_organ_dna(dna)

/// The limbs that are hurt or need care: damage, wounds, a fracture, germs, or a cut-away, bleeding, destroyed, dead or
/// mutated part. A query over the limbs.
/mob/living/carbon/human/proc/damaged_limbs()
	RETURN_TYPE(/list)
	. = list()
	for(var/obj/item/organ/external/E as anything in organs)
		if((E.status & (ORGAN_CUT_AWAY|ORGAN_BLEEDING|ORGAN_DESTROYED|ORGAN_DEAD|ORGAN_MUTATED)) || E.is_fractured() || E.germ_level || length(E.get_wounds()))
			. += E
