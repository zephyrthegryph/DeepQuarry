// Body cavities: placing objects inside an opened region, and taking foreign
// objects (implants, shrapnel, cavity items) back out.

/// Largest total w_class a region's cavity holds.
/proc/surgical_cavity_capacity(obj/item/organ/external/part)
	switch(part.organ_tag)
		if(BP_HEAD)
			return ITEMSIZE_TINY
		if(BP_TORSO)
			return ITEMSIZE_NORMAL
		if(BP_GROIN)
			return ITEMSIZE_SMALL
	return 0

/proc/surgical_cavity_name(obj/item/organ/external/part)
	switch(part.organ_tag)
		if(BP_HEAD)
			return "cranial"
		if(BP_TORSO)
			return "thoracic"
		if(BP_GROIN)
			return "abdominal"
	return ""

// --- What may go into a cavity --------------------------------------------------------------
// Opt-out per type: anything with a use of its own on a patient (instruments, tools,
// reagent containers) must never be swallowed by the cavity step instead of being used.

/// Whether the Implant Object surgical step may place this item in a body cavity.
/obj/item/var/cavity_implantable = TRUE

/obj/item/surgical
	cavity_implantable = FALSE
/obj/item/organ
	cavity_implantable = FALSE
/obj/item/stack
	cavity_implantable = FALSE
/obj/item/tool
	cavity_implantable = FALSE
/obj/item/weldingtool
	cavity_implantable = FALSE
/obj/item/autopsy_scanner
	cavity_implantable = FALSE
/obj/item/mmi
	cavity_implantable = FALSE
/obj/item/robot_parts
	cavity_implantable = FALSE
/obj/item/holder
	cavity_implantable = FALSE
/obj/item/material/knife
	cavity_implantable = FALSE
/obj/item/flame/lighter
	cavity_implantable = FALSE
/obj/item/clothing/mask/smokable/cigarette
	cavity_implantable = FALSE
/obj/item/reagent_containers
	cavity_implantable = FALSE
/obj/item/decompression_needle
	cavity_implantable = FALSE
/obj/item/airway_kit
	cavity_implantable = FALSE
/obj/item/bag_valve_mask
	cavity_implantable = FALSE
/obj/item/tourniquet
	cavity_implantable = FALSE
/obj/item/shockpaddles
	cavity_implantable = FALSE
/obj/item/healthanalyzer
	cavity_implantable = FALSE
/obj/item/analyzer
	cavity_implantable = FALSE
/obj/item/reagent_scanner
	cavity_implantable = FALSE
/obj/item/gene_scanner
	cavity_implantable = FALSE
/obj/item/slime_scanner
	cavity_implantable = FALSE
/obj/item/robotanalyzer
	cavity_implantable = FALSE

/datum/surgical_step/place_item
	name = "Implant Object"
	phase = SURGERY_PHASE_OPERATE
	priority = -1
	allowed_tools = list(/obj/item = 100)
	zones = list(BP_HEAD, BP_TORSO, BP_GROIN)
	part_biology = BIOLOGY_ALL
	needs_full_access = TRUE
	duration = 8 SECONDS
	pain = 60
	begin_text = "putting something into the body cavity of"
	end_text = "puts something into the body cavity of"
	fail_text = "slips, scraping around inside"
	pain_text = "The pain in your %PART% is living hell!"
	complication_kind = INJURY_CUT
	complication_amount = 20

/// A robot places whatever its gripper holds.
/datum/surgical_step/place_item/proc/placed_item(mob/living/user, obj/item/tool)
	if(istype(tool, /obj/item/gripper))
		var/obj/item/gripper/gripper = tool
		return gripper.get_wrapped_item()
	return tool

/datum/surgical_step/place_item/tool_quality(obj/item/tool)
	if(istype(tool, /obj/item/gripper))
		var/obj/item/gripper/gripper = tool
		tool = gripper.get_wrapped_item()
		if(!tool)
			return 0
	if(!tool.cavity_implantable)
		return 0
	return ..(tool)

/datum/surgical_step/place_item/confirm_text(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/obj/item/placed = placed_item(user, tool)
	return placed ? "Implant 	he [placed] into [target]'s [surgical_cavity_name(part)] cavity?" : null

/datum/surgical_step/place_item/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/obj/item/placed = placed_item(user, tool)
	if(!placed)
		return FALSE
	var/total_volume = placed.w_class
	for(var/obj/item/I in part.implants)
		if(!istype(I, /obj/item/implant))
			total_volume += I.w_class
	return total_volume <= surgical_cavity_capacity(part)

/datum/surgical_step/place_item/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/placed = placed_item(user, tool)
	if(!placed)
		return
	if(istype(tool, /obj/item/gripper))
		var/obj/item/gripper/G = tool
		G.drop_item_nm()
	else
		user.drop_item()
	to_chat(user, span_notice("You settle \the [placed] into [target]'s [surgical_cavity_name(part)] cavity."))
	// A big object tears the vessels it's forced past.
	if(placed.w_class > surgical_cavity_capacity(part) / 2 && prob(50) && (target.body.biology_of(part) & BIOLOGY_ORGANIC))
		to_chat(user, span_danger("You feel something give way as you force \the [placed] into place."))
		target.injure(INJURY_CUT, 10, part, placed, affliction = /datum/affliction/wound/internal_bleeding, flags = INJURE_IGNORE_RESISTANCE)
		target.custom_pain("You feel something rip in your [part.name]!", 1)
	rel_add(part, nameof(part.implants), placed)
	placed.forceMove(part)
	if(istype(placed, /obj/item/nif))
		var/obj/item/nif/N = placed
		N.implant(target)
	log_game("SURGERY: [key_name(user)] placed [placed] in [key_name(target)]'s [part]")


/// Foreign body extraction also takes out implants, shrapnel and cavity items:
/// needed when anything is embedded in the region.
/datum/surgical_step/treat/extract_foreign_body/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(length(part.implants))
		return TRUE
	return ..()

/datum/surgical_step/treat/extract_foreign_body/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	if(!length(part.implants))
		return
	open_request(src, /datum/prompt/choice/extract_foreign_body, PROC_REF(foreign_body_chosen), answerer = user, title = name, choices = part.implants, subject = target, part = part, tool = tool)

/// Which embedded object to pull out. Re-checked on the answer: the surgeon is still next to the
/// patient and able, the part is still theirs, the pick is still in it and the tool still in hand.
/datum/prompt/choice/extract_foreign_body
	question = "Which embedded object do you wish to remove?"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	timeout = 0
	var/obj/item/organ/external/part
	var/obj/item/tool

CAPABILITIES(/datum/prompt/choice/extract_foreign_body)
	ref_one(nameof(subject), /mob/living/carbon/human)
	ref_one(nameof(part), /obj/item/organ/external)
	ref_one(nameof(tool), /obj/item)

/datum/prompt/choice/extract_foreign_body/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured_patient = subject
	var/obj/item/organ/external/captured_part = part
	var/obj/item/captured_tool = tool
	var/datum/request/request = src
	rel_clear(request, nameof(request.subject))
	rel_clear(src, nameof(part))
	rel_clear(src, nameof(tool))
	rel_set(request, nameof(request.subject), captured_patient)
	rel_set(src, nameof(part), captured_part)
	rel_set(src, nameof(tool), captured_tool)

/datum/prompt/choice/extract_foreign_body/recheck_extra()
	. = ..()
	if(.)
		return
	var/atom/movable/selected = value
	if(QDELETED(subject) || QDELETED(part) || QDELETED(tool) || !istype(selected) || QDELETED(selected) || !(selected in part.implants) || part.owner != subject || answerer.get_active_hand() != tool)
		return "lost the grip"
	return null

/datum/surgical_step/treat/extract_foreign_body/proc/foreign_body_chosen(datum/act/request/A)
	var/datum/prompt/choice/extract_foreign_body/ask = A.request
	if(!A.answer)
		if(!isnull(ask.value) && !QDELETED(ask.answerer) && !QDELETED(ask.tool) && !QDELETED(ask.subject) && !QDELETED(ask.part))
			to_chat(ask.answerer, span_notice("You draw \the [ask.tool] back out of [ask.subject]'s [ask.part.name]."))
		return
	var/mob/living/user = ask.answerer
	var/mob/living/carbon/human/target = ask.subject
	var/obj/item/organ/external/part = ask.part
	var/obj/item/tool = ask.tool
	var/atom/movable/removed = ask.value
	var/wait = 0
	if(istype(removed, /obj/item/implant))
		var/obj/item/implant/imp = removed
		if(!imp.islegal())
			to_chat(user, span_notice("\The [imp] is anchored deep; you work it loose carefully..."))
			wait = duration
	if(!wait)
		extract_body(user, target, part, removed)
		return
	var/datum/op_result/working = perform_op(user, src, "extract_body", null, ORIGIN_SYSTEM, AUTH_PHYSICAL, with = list("target" = target, "part" = part, "removed" = removed, "duration" = wait))
	if(working.outcome == ACT_REFUSED)
		to_chat(user, span_warning("\The [removed] slips back out of your grip."))

/// Working a foreign body out of a part slowly, for an anchored implant.
CAPABILITIES(/datum/surgical_step/treat/extract_foreign_body)
	op("extract_body", ai(), takes("target", "part", "removed", "duration"), wait(PROC_REF(extract_time)), on_interrupt(PROC_REF(extract_slipped)), then(PROC_REF(extract_done)))

/datum/surgical_step/treat/extract_foreign_body/proc/extract_time(datum/act/op/A)
	return A.arg("duration")


/datum/surgical_step/treat/extract_foreign_body/proc/extract_slipped(datum/act/op/A)
	to_chat(A.actor, span_warning("\The [A.arg("removed")] slips back out of your grip."))

/datum/surgical_step/treat/extract_foreign_body/proc/extract_done(datum/act/op/A)
	extract_body(A.actor, A.arg("target"), A.arg("part"), A.arg("removed"))

/// Pulls the foreign body out of the part.
/datum/surgical_step/treat/extract_foreign_body/proc/extract_body(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, atom/movable/removed)
	if(!(removed in part.implants))
		return
	rel_remove(part, nameof(part.implants), removed)
	if(!target.has_embedded_objects())
		target.clear_alert("embeddedobject")
	target.flag_hud_update(IMPLOYAL_HUD)
	log_game("SURGERY: [key_name(user)] extracted [removed] ([removed.type]) from [key_name(target)]'s [part]")
	if(istype(removed, /mob/living/simple_mob/animal/borer))
		var/mob/living/simple_mob/animal/borer/worm = removed
		if(worm.controlling)
			target.release_control()
		worm.detatch()
		worm.leave_host()
		return
	removed.forceMove(get_turf(target))
	removed.add_blood(target)
	to_chat(user, span_notice("You pull \the [removed] out of [target]'s [part.name]."))
	if(istype(removed, /obj/item/implant))
		var/obj/item/implant/imp = removed
		rel_clear(imp, nameof(imp.imp_in))
		imp.implanted = FALSE
	else if(istype(removed, /obj/item/nif))
		var/obj/item/nif/N = removed
		N.unimplant(target)

/// Rummaging around a live implant can set it off.
/datum/surgical_step/treat/extract_foreign_body/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	if(!part || !length(part.implants))
		return
	var/obj/item/implant/imp = part.implants[1]
	if(!istype(imp) || !prob(10 + 100 - tool_quality(tool)))
		return
	user.visible_message(span_danger("Something beeps inside [target]'s [part.name]!"))
	play_sfx(imp, SFX_ITEMS_COUNTDOWN)
	after(imp, 2.5 SECONDS, TYPE_PROC_REF(/obj/item/implant, activate))
