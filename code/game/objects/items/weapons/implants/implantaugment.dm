//////////////////////////////
//	Nanite Organ Implant
//////////////////////////////
/obj/item/implant/organ
	name = "nanite fabrication implant"
	desc = "A buzzing implant covered in a writhing layer of metal insects."
	icon_state = "implant_evil"

	var/organ_to_implant = /obj/item/organ/internal/augment/bioaugment/thermalshades
	var/organ_display_name = "unknown organ"

/obj/item/implant/organ/get_data()
	var/dat = {"
<b>Implant Specifications:</b><BR>
<b>Name:</b> \"GreyDoctor\" Class Nanite Hive<BR>
<b>Life:</b> Activates upon implantation, destroying itself in the process.<BR>
<b>Important Notes:</b> Nanites will fail to complete their task if a suitable location cannot be found for the organ.<BR>
<HR>
<b>Implant Details:</b><BR>
<b>Function:</b> Nanites will fabricate: [span_alien("[organ_display_name]")]<BR>
<b>Special Features:</b> Organ identification protocols.<BR>
<b>Integrity:</b> N/A"}
	return dat

/obj/item/implant/organ/post_implant(mob/M)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M

		var/obj/item/organ/NewOrgan = new organ_to_implant()

		var/obj/item/organ/external/E = H.get_organ(NewOrgan.parent_organ)
		to_chat(H, span_notice("You feel a tingling sensation in your [part]."))
		// A ledger move into the limb; the attach hook does the rest.
		if(E && !(H.organ_in(NewOrgan.organ_tag)) && NewOrgan.replaced(H, E))
			after(H, rand(1 SECONDS, 30 SECONDS), GLOBAL_PROC_REF(to_chat), with = list(H, span_alien("You feel a pressure in your [E] as the tingling fades, the lump caused by the implant now gone.")))

			expire(1)

		else
			spent(NewOrgan, M)
			to_chat(H, span_warning("You feel a pinching sensation in your [part]. The implant remains."))

/obj/item/implant/organ/islegal()
	return 0

/*
 * Arm / leg mounted augments.
 */

/obj/item/implant/organ/limbaugment
	name = "nanite implant"

	organ_to_implant = /obj/item/organ/internal/augment/armmounted/taser
	organ_display_name = "physiological augment"

TYPE_TABLE_DECLARE(/obj/item/implant/organ/limbaugment, limbaugment_targets, list(O_AUG_L_FOREARM, O_AUG_R_FOREARM))


/obj/item/implant/organ/limbaugment/post_implant(mob/M, mob/user = null)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M

		var/list/choices = augment_choices(H)
		if(length(choices) > 1)
			if(user && !QDELETED(user))
				open_request(src, /datum/prompt/choice/augment_location, PROC_REF(augment_location_chosen), answerer = user, choices = choices, patient = H)
			return
		install_augment(H, length(choices) ? choices[1] : null)

/// Where a limb augment goes on `patient`.
/datum/prompt/choice/augment_location
	timeout = 0
	title = "Choose Location"
	question = "Choose augment location:"
	var/mob/living/carbon/human/patient

CAPABILITIES(/datum/prompt/choice/augment_location)
	ref_one(nameof(patient), /mob/living/carbon/human)

/datum/prompt/choice/augment_location/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured_patient = patient
	rel_clear(src, nameof(patient))
	rel_set(src, nameof(patient), captured_patient)

/obj/item/implant/organ/limbaugment/proc/augment_location_chosen(datum/act/request/A)
	var/datum/prompt/choice/augment_location/ask = A.request
	if(!A.answer || QDELETED(ask.answerer) || QDELETED(ask.patient))
		return
	install_augment(ask.patient, ask.value)

/obj/item/implant/organ/limbaugment/proc/augment_choices(mob/living/carbon/human/H)
	. = TYPE_TABLE_COPY(src, limbaugment_targets)
	for(var/targ in TYPE_TABLE_GET(src, limbaugment_targets))
		if(H.organ_in(targ))
			. -= targ

/obj/item/implant/organ/limbaugment/proc/install_augment(mob/living/carbon/human/H, target_choice)
	var/obj/item/organ/NewOrgan = new organ_to_implant()

	var/obj/item/organ/external/E = setup_augment_slots(H, NewOrgan, target_choice)
	to_chat(H, span_notice("You feel a tingling sensation in your [part]."))
	// A ledger move into the limb; the attach hook does the rest. An
	// incompatible augment is deleted below, which detaches it again.
	if(istype(E) && !(H.organ_in(NewOrgan.organ_tag)) && NewOrgan.replaced(H, E) && NewOrgan.check_verb_compatability())
		after(H, rand(1 SECONDS, 30 SECONDS), GLOBAL_PROC_REF(to_chat), with = list(H, span_alien("You feel a pressure in your [E] as the tingling fades, the lump caused by the implant now gone.")))

		expire(1)

	else
		consumed(NewOrgan, src)
		to_chat(H, span_warning("You feel a pinching sensation in your [part]. The implant remains."))

/obj/item/implant/organ/limbaugment/proc/setup_augment_slots(mob/living/carbon/human/H, obj/item/organ/internal/augment/armmounted/I, target_choice)
	if(target_choice)
		switch(target_choice)
			if(O_AUG_R_HAND)
				I.organ_tag = O_AUG_R_HAND
				I.parent_organ = BP_R_HAND
				I.target_slot = SLOT_ID_HAND_R
			if(O_AUG_L_HAND)
				I.organ_tag = O_AUG_L_HAND
				I.parent_organ = BP_L_HAND
				I.target_slot = SLOT_ID_HAND_L

			if(O_AUG_R_FOREARM)
				I.organ_tag = O_AUG_R_FOREARM
				I.parent_organ = BP_R_ARM
				I.target_slot = SLOT_ID_HAND_R
			if(O_AUG_L_FOREARM)
				I.organ_tag = O_AUG_L_FOREARM
				I.parent_organ = BP_L_ARM
				I.target_slot = SLOT_ID_HAND_L

			if(O_AUG_R_UPPERARM)
				I.organ_tag = O_AUG_R_UPPERARM
				I.parent_organ = BP_R_ARM
				I.target_slot = SLOT_ID_HAND_R
			if(O_AUG_L_UPPERARM)
				I.organ_tag = O_AUG_L_UPPERARM
				I.parent_organ = BP_L_ARM
				I.target_slot = SLOT_ID_HAND_L

		. = H.get_organ(I.parent_organ)

/*
 * Limb implant primary subtypes.
 */

/obj/item/implant/organ/limbaugment/upperarm
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/shoulder/multiple
	organ_display_name = "multi-use augment"

TYPE_TABLE(/obj/item/implant/organ/limbaugment/upperarm, limbaugment_targets, list(O_AUG_R_UPPERARM,O_AUG_L_UPPERARM))


/obj/item/implant/organ/limbaugment/wrist
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/hand
	organ_display_name = "wrist augment"

TYPE_TABLE(/obj/item/implant/organ/limbaugment/wrist, limbaugment_targets, list(O_AUG_R_HAND,O_AUG_L_HAND))


/*
 * Limb implant general subtypes.
 */

// Wrist
/obj/item/implant/organ/limbaugment/wrist/sword
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/hand/sword
	organ_display_name = "weapon augment"

/obj/item/implant/organ/limbaugment/wrist/blade
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/hand/blade
	organ_display_name = "weapon augment"

// Fore-arm
/obj/item/implant/organ/limbaugment/laser
	organ_to_implant = /obj/item/organ/internal/augment/armmounted
	organ_display_name = "weapon augment"

/obj/item/implant/organ/limbaugment/dart
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/dartbow
	organ_display_name = "weapon augment"

// Upper-arm.
/obj/item/implant/organ/limbaugment/upperarm/medkit
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/shoulder/multiple/medical

/obj/item/implant/organ/limbaugment/upperarm/surge
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/shoulder/surge

/obj/item/implant/organ/limbaugment/upperarm/blade
	organ_to_implant = /obj/item/organ/internal/augment/armmounted/shoulder/blade
	organ_display_name = "weapon augment"

/*
 * Others
 */

/obj/item/implant/organ/pelvic/sprint
	name = "locomotive optimization implant"
	organ_to_implant = /obj/item/organ/internal/augment/bioaugment/sprint_enhance
	organ_display_name = "pelvic augment"

/obj/item/implant/organ/pelvic/scanner
	name = "medican scanner implant"
	organ_to_implant = /obj/item/organ/internal/augment/bioaugment/health_scan
	organ_display_name = "pelvic augment"
