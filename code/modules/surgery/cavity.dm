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

/datum/surgical_step/place_item
	name = "Implant Object"
	phase = SURGERY_PHASE_OPERATE
	priority = -1
	allowed_tools = list(/obj/item = 100)
	// Tools with procedures of their own never go in the cavity by accident.
	excluded_tools = list(
		/obj/item/surgical,
		/obj/item/organ,
		/obj/item/stack,
		/obj/item/tool,
		/obj/item/weldingtool,
		/obj/item/autopsy_scanner,
		/obj/item/mmi,
		/obj/item/robot_parts,
		/obj/item/holder,
		/obj/item/material/knife,
		/obj/item/flame/lighter,
		/obj/item/clothing/mask/smokable/cigarette,
	)
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
	return ..(tool)

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
	part.implants += placed
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
	var/atom/movable/removed = tgui_input_list(user, "Which embedded object do you wish to remove?", name, part.implants)
	if(!removed || !(removed in part.implants))
		to_chat(user, span_notice("You draw \the [tool] back out of [target]'s [part.name]."))
		return
	if(istype(removed, /obj/item/implant))
		var/obj/item/implant/imp = removed
		if(!imp.islegal())
			to_chat(user, span_notice("\The [imp] is anchored deep; you work it loose carefully..."))
			if(!do_after(user, duration, target, max_distance = tool.reach))
				to_chat(user, span_warning("\The [imp] slips back out of your grip."))
				return
	part.implants -= removed
	if(!target.has_embedded_objects())
		target.clear_alert("embeddedobject")
	BITSET(target.hud_updateflag, IMPLOYAL_HUD)
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
	removed.update_icon()
	to_chat(user, span_notice("You pull \the [removed] out of [target]'s [part.name]."))
	if(istype(removed, /obj/item/implant))
		var/obj/item/implant/imp = removed
		imp.imp_in = null
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
	playsound(imp, 'sound/items/countdown.ogg', 75, 1, -3)
	addtimer(CALLBACK(imp, TYPE_PROC_REF(/obj/item/implant, activate)), 2.5 SECONDS)
