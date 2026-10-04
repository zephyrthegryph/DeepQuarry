/obj/item/forensics/swab
	name = "swab kit"
	desc = "A sterilized cotton swab and vial used to take forensic samples."
	icon_state = "swab"
	var/gsr = 0
	var/list/dna
	var/used
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

/obj/item/forensics/swab/proc/is_used()
	return used

/obj/item/forensics/swab/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	if(!ishuman(M))
		return ..()

	if(is_used())
		return ITEM_INTERACT_FAILURE

	var/mob/living/carbon/human/H = M
	var/sample_type

	if(H.get_equipped_item(SLOT_ID_MASK))
		to_chat(user, span_warning("\The [H] is wearing a mask."))
		return ITEM_INTERACT_FAILURE

	if(!H.dna || !H.dna.unique_enzymes)
		to_chat(user, span_warning("They don't seem to have DNA!"))
		return ITEM_INTERACT_FAILURE

	if(user != H && H.combat_mode && !H.lying)
		act_message(user, H, others = span_danger("%U% tries to take a swab sample from %T%, but they move away."))
		return ITEM_INTERACT_FAILURE

	if(user.zone_sel.selecting == O_MOUTH)
		if(!H.organs_by_name[BP_HEAD])
			to_chat(user, span_warning("They don't have a head."))
			return ITEM_INTERACT_FAILURE
		if(!H.check_has_mouth())
			to_chat(user, span_warning("They don't have a mouth."))
			return ITEM_INTERACT_FAILURE
		act_message(user, H, others = "%U% swabs %T%'s mouth for a saliva sample.")
		dna = list(H.dna.unique_enzymes)
		sample_type = "DNA"

	else if(user.zone_sel.selecting == BP_R_HAND || user.zone_sel.selecting == BP_L_HAND)
		var/has_hand
		var/obj/item/organ/external/O = H.organs_by_name[BP_R_HAND]
		if(istype(O) && !O.is_stump())
			has_hand = 1
		else
			O = H.organs_by_name[BP_L_HAND]
			if(istype(O) && !O.is_stump())
				has_hand = 1
		if(!has_hand)
			to_chat(user, span_warning("They don't have any hands."))
			return
		act_message(user, H, others = "%U% swabs %T%'s palm for a sample.")
		sample_type = "GSR"
		gsr = H.forensic_data?.get_gunshotresidue()
	else
		return ITEM_INTERACT_FAILURE

	if(sample_type)
		set_used(sample_type, H)
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

/obj/item/forensics/swab/afterattack(atom/A, mob/user, proximity)
	return collect_swab_evidence(A, user, proximity)

/obj/item/forensics/swab/proc/collect_swab_evidence(atom/A, mob/user, proximity, selected_evidence)
	if(!proximity || istype(A, /obj/machinery/dnaforensics))
		return

	if(is_used())
		to_chat(user, span_warning("This swab has already been used."))
		return

	add_fingerprint(user)

	var/list/choices = list()
	if(A.forensic_data?.has_blooddna())
		choices |= "Blood"
	if(istype(A, /obj/item/clothing))
		choices |= "Gunshot Residue"

	var/choice
	if(!choices.len)
		to_chat(user, span_warning("There is no evidence on \the [A]."))
		return
	else if(choices.len == 1)
		choice = choices[1]
	else
		if(isnull(selected_evidence))
			open_request(src, /datum/prompt/choice/forensic_swab_evidence, PROC_REF(forensic_swab_evidence_answered), answerer = user, choices = choices, target = A, captured_proximity = proximity)
			return TRUE
		choice = selected_evidence

	if(!choice)
		return

	var/sample_type
	if(choice == "Blood")
		if(!A.forensic_data?.has_blooddna()) return
		dna = A.forensic_data?.get_blooddna().Copy()
		sample_type = "blood"

	else if(choice == "Gunshot Residue")
		var/obj/item/clothing/B = A
		if(!istype(B) || !B.forensic_data?.get_gunshotresidue())
			to_chat(user, span_warning("There is no residue on \the [A]."))
			return
		gsr = B.forensic_data?.get_gunshotresidue()
		sample_type = "residue"

	if(sample_type)
		act_message(user, A, MSG_SELF("You swab %T% for a sample."), MSG_OTHERS("%U% swabs %T% for a sample."))
		set_used(sample_type, A)


/obj/item/forensics/swab/proc/forensic_swab_evidence_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/forensic_swab_evidence/request = context.request
	collect_swab_evidence(request.target, request.answerer, request.captured_proximity, request.answer_value)
	SStgui.update_uis(src)

/datum/prompt/choice/forensic_swab_evidence
	title = "Evidence Collection"
	question = "What kind of evidence are you looking for?"
	timeout = 0
	var/atom/target
	var/captured_proximity
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/forensic_swab_evidence)
	ref_one(nameof(target), /atom)

/datum/prompt/choice/forensic_swab_evidence/prepare(datum/act/A)
	..()
	var/atom/captured_target = target
	rel_clear(src, nameof(target))
	rel_set(src, nameof(target), captured_target)

/datum/prompt/choice/forensic_swab_evidence/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(target))
		return "The original sample source is no longer available."

/obj/item/forensics/swab/proc/set_used(sample_str, atom/source)
	name = "[initial(name)] ([sample_str] - [source])"
	desc = "[initial(desc)] The label on the vial reads 'Sample of [sample_str] from [source].'."
	icon_state = "swab_used"
	used = 1
