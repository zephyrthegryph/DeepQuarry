/obj/item/sample
	name = "forensic sample"
	icon = 'icons/obj/forensics.dmi'
	w_class = ITEMSIZE_TINY
	var/list/evidence

/obj/item/sample/Initialize(mapload, atom/supplied)
	. = ..()
	if(supplied && supplied.forensic_data)
		copy_evidence(supplied)
		name = "[initial(name)] (\the [supplied])"

/obj/item/sample/print/Initialize(mapload, supplied)
	. = ..()
	if(evidence && length(evidence))
		icon_state = "fingerprint1"

/obj/item/sample/proc/copy_evidence(atom/supplied)
	var/list/fibre_data = supplied.forensic_data.get_fibres()
	if(fibre_data && fibre_data.len)
		evidence = fibre_data.Copy()
		supplied.forensic_data.clear_fibres()

/obj/item/sample/proc/merge_evidence(obj/item/sample/supplied, mob/user)
	if(!supplied.evidence || !length(supplied.evidence))
		return 0
	if(length(supplied.evidence)) LAZYOR(evidence, supplied.evidence)
	name = "[initial(name)] (combined)"
	to_chat(user, span_notice("You transfer the contents of \the [supplied] into \the [src]."))
	return 1

/obj/item/sample/print/merge_evidence(obj/item/sample/supplied, mob/user)
	if(!supplied.evidence || !length(supplied.evidence))
		return 0
	for(var/print in supplied.evidence)
		if(LAZYACCESS(evidence, print))
			LAZYSET(evidence, print, stringmerge(LAZYACCESS(evidence, print),LAZYACCESS(supplied.evidence, print)))
		else
			LAZYSET(evidence, print, LAZYACCESS(supplied.evidence, print))
	name = "[initial(name)] (combined)"
	to_chat(user, span_notice("You overlay \the [src] and \the [supplied], combining the print records."))
	return 1

/obj/item/sample/attackby(obj/O, mob/user)
	if(O.type == src.type)
		user.unEquip(O)
		if(merge_evidence(O, user))
			qdel(O)
		return 1
	return ..()

/obj/item/sample/fibers
	name = "fiber bag"
	desc = "Used to hold fiber evidence for the detective."
	icon_state = "fiberbag"

/obj/item/sample/print
	name = "fingerprint card"
	desc = "Records a set of fingerprints."
	icon = 'icons/obj/card.dmi'
	icon_state = "fingerprint0"
	item_state = "paper"

/obj/item/sample/print/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(evidence && length(evidence))
		return
	if(!ishuman(user))
		return
	var/mob/living/carbon/human/H = user
	if(H.get_equipped_item(SLOT_ID_GLOVES))
		to_chat(user, span_warning("Take \the [H.get_equipped_item(SLOT_ID_GLOVES)] off first."))
		return

	to_chat(user, span_notice("You firmly press your fingertips onto the card."))
	var/fullprint = H.get_full_print()
	LAZYSET(evidence, fullprint, fullprint)
	name = "[initial(name)] (\the [H])"
	icon_state = "fingerprint1"

/obj/item/sample/print/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	if(!ishuman(M))
		return ..()

	if(evidence && length(evidence))
		return ITEM_INTERACT_FAILURE

	var/mob/living/carbon/human/H = M

	if(H.get_equipped_item(SLOT_ID_GLOVES))
		to_chat(user, span_warning("\The [H] is wearing gloves."))
		return ITEM_INTERACT_FAILURE

	if(user != H && !IS_HELPING(H) && !H.lying)
		user.visible_message(span_danger("\The [user] tries to take prints from \the [H], but they move away."))
		return ITEM_INTERACT_FAILURE

	if(user.zone_sel.selecting == BP_R_HAND || user.zone_sel.selecting == BP_L_HAND)
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
			return ITEM_INTERACT_FAILURE
		user.visible_message("[user] takes a copy of \the [H]'s fingerprints.")
		var/fullprint = H.get_full_print()
		LAZYSET(evidence, fullprint, fullprint)
		copy_evidence(src)
		name = "[initial(name)] (\the [H])"
		icon_state = "fingerprint1"
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

/obj/item/sample/print/copy_evidence(atom/supplied)
	var/list/print_data = supplied.forensic_data.get_prints()
	if(print_data && print_data.len)
		for(var/print in print_data)
			LAZYSET(evidence, print, print_data[print])
		supplied.forensic_data.clear_prints()

/obj/item/forensics/sample_kit
	name = "fiber collection kit"
	desc = "A magnifying glass and tweezers. Used to lift suit fibers."
	icon_state = "m_glass"
	w_class = ITEMSIZE_SMALL
	var/evidence_type = "fiber"
	var/evidence_path = /obj/item/sample/fibers

/obj/item/forensics/sample_kit/proc/can_take_sample(mob/user, atom/supplied)
	return supplied.forensic_data?.has_fibres()

/obj/item/forensics/sample_kit/proc/take_sample(mob/user, atom/supplied)
	var/obj/item/sample/S = new evidence_path(get_turf(user), supplied)
	to_chat(user, span_notice("You transfer [length(S.evidence)] [length(S.evidence) > 1 ? "[evidence_type]s" : "[evidence_type]"] to \the [S]."))

/obj/item/forensics/sample_kit/afterattack(atom/A, mob/user, proximity)
	if(!proximity)
		return
	add_fingerprint(user)
	if(can_take_sample(user, A))
		take_sample(user,A)
		return 1
	else
		to_chat(user, span_warning("You are unable to locate any [evidence_type]s on \the [A]."))
		return ..()

/obj/item/forensics/sample_kit/powder
	name = "fingerprint powder"
	desc = "A jar containing aluminum powder and a specialized brush."
	icon_state = "dust"
	evidence_type = "fingerprint"
	evidence_path = /obj/item/sample/print

/obj/item/forensics/sample_kit/powder/can_take_sample(mob/user, atom/supplied)
	return supplied.forensic_data?.has_prints()
