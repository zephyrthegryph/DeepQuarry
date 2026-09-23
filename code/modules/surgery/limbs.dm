// Limb operations: amputation, attachment, and limb-level reconstruction.

/datum/surgical_step/amputate
	name = "Amputate Limb"
	phase = SURGERY_PHASE_OPERATE
	priority = 0
	allowed_tools = list(
		/obj/item/surgical/circular_saw = 100,
		/obj/item/material/twohanded/fireaxe = 99,
		/obj/item/material/knife/machete/hatchet = 75,
	)
	part_biology = BIOLOGY_ALL
	duration = 10 SECONDS
	pain = 100
	blood_level = 2
	begin_text = "amputating"
	end_text = "amputates"
	fail_text = "slips, sawing through the bone of"
	pain_text = "Your %PART% is being ripped apart!"
	complication_kind = INJURY_CUT
	complication_amount = 30

/datum/surgical_step/amputate/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return !part.cannot_amputate

/datum/surgical_step/amputate/confirm(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	to_chat(user, span_danger("You are preparing to amputate \the [target]'s [part.name]!"))
	if(!do_after(user, 3 SECONDS, target = target))
		to_chat(user, span_warning("You reconsider performing an amputation..."))
		return FALSE
	return TRUE

/datum/surgical_step/amputate/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	add_attack_logs(user, target, "Surgically amputated [part.name]")
	log_game("SURGERY: [key_name(user)] amputated [key_name(target)]'s [part]")
	part.droplimb(TRUE, DROPLIMB_EDGE)

/// A slipped saw breaks the bone as well as cutting.
/datum/surgical_step/amputate/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	part?.fracture()


// --- Limb attachment ------------------------------------------------------------------------

/datum/surgical_step/limb
	abstract_type = /datum/surgical_step/limb
	phase = SURGERY_PHASE_OPERATE
	priority = 3
	part_biology = BIOLOGY_ALL
	infection_risk = FALSE
	complication_kind = INJURY_PIERCE
	complication_amount = 10

/datum/surgical_step/limb/attach
	name = "Attach Limb"
	allowed_tools = list(/obj/item/organ/external = 100)
	needs_missing_part = TRUE
	duration = 5 SECONDS
	begin_text = "attaching a limb to"
	end_text = "attaches a limb to"
	fail_text = "slips, gouging"
	pain_text = "Something is being pressed hard against your stump!"

/datum/surgical_step/limb/attach/can_use(mob/living/user, mob/living/carbon/human/target, zone, obj/item/tool)
	. = ..()
	if(!. || . == SURGERY_REFUSED)
		return
	var/obj/item/organ/external/E = tool
	if(!istype(E) || E.organ_tag != zone || isnull(target.species.has_limbs[zone]))
		return FALSE
	var/obj/item/organ/external/P = target.organs_by_name[E.parent_organ]
	if(!P)
		to_chat(user, span_warning("There's nothing on [target] for \the [E] to join onto."))
		return SURGERY_REFUSED
	if((P.robotic >= ORGAN_ROBOT) && (E.robotic < ORGAN_ROBOT))
		to_chat(user, span_warning("\The [P] ends in metal couplings; living flesh won't take to them."))
		return SURGERY_REFUSED
	if(istype(E, /obj/item/organ/external/head) && E.robotic >= ORGAN_ROBOT && P.robotic < ORGAN_ROBOT)
		to_chat(user, span_warning("The mounting on \the [E] would tear straight through the flesh of \the [P]."))
		return SURGERY_REFUSED
	return TRUE

/datum/surgical_step/limb/attach/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/organ/external/E = tool
	user.drop_from_inventory(E)
	E.replaced(target)
	// Modular bodyparts (prosthetics) need no reconnection.
	if(E.get_modular_limb_category() != MODULAR_BODYPART_INVALID)
		E.status &= ~ORGAN_CUT_AWAY
		for(var/obj/item/organ/external/child in E.children)
			child.status &= ~ORGAN_CUT_AWAY
	target.update_icons_body(FALSE)
	target.UpdateDamageIcon()
	log_game("SURGERY: [key_name(user)] attached [E] ([E.type]) to [key_name(target)], carrying [length(E.afflictions_here())] afflictions")

/// A failed attachment injures the stump it was being fitted to.
/datum/surgical_step/limb/attach/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/organ/external/E = tool
	var/obj/item/organ/external/P = istype(E) ? target.organs_by_name[E.parent_organ] : null
	..(user, target, part, tool, P)

/datum/surgical_step/limb/connect
	name = "Connect Limb"
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100,
		/obj/item/stack/cable_coil = 75,
		/obj/item/assembly/mousetrap = 25,
	)
	infection_risk = TRUE
	duration = 7 SECONDS
	begin_text = "connecting the tendons and muscles of"
	end_text = "connects the tendons and muscles of"
	fail_text = "slips, tearing"
	pain_text = "Something is tugging at the nerves of your %PART%!"

/datum/surgical_step/limb/connect/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return (part.status & ORGAN_CUT_AWAY) ? TRUE : FALSE

/datum/surgical_step/limb/connect/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	part.status &= ~ORGAN_CUT_AWAY
	for(var/obj/item/organ/external/child in part.children)
		child.status &= ~ORGAN_CUT_AWAY
		to_chat(user, span_notice("You attach [target]'s [child.name] as well."))
	target.update_icons_body()
	target.UpdateDamageIcon()
	log_game("SURGERY: [key_name(user)] connected [key_name(target)]'s [part]")

/datum/surgical_step/limb/mechanize
	name = "Mechanize Limb"
	allowed_tools = list(/obj/item/robot_parts = 100)
	needs_missing_part = TRUE
	duration = 9 SECONDS
	begin_text = "attaching a prosthesis to"
	end_text = "attaches a prosthesis to"
	fail_text = "slips, gouging"

/datum/surgical_step/limb/mechanize/can_use(mob/living/user, mob/living/carbon/human/target, zone, obj/item/tool)
	. = ..()
	if(!. || . == SURGERY_REFUSED)
		return
	var/obj/item/robot_parts/P = tool
	if(!istype(P) || isnull(target.species.has_limbs[zone]))
		return FALSE
	if(P.part && !(zone in P.part))
		return FALSE
	return TRUE

/datum/surgical_step/limb/mechanize/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/robot_parts/L = tool
	for(var/part_name in L.part)
		if(target.get_organ(part_name))
			continue
		var/list/organ_data = target.species.has_limbs["[part_name]"]
		if(!organ_data)
			continue
		var/new_limb_type = organ_data["path"]
		var/obj/item/organ/external/new_limb = new new_limb_type(target)
		new_limb.robotize(L.model_info)
		if(L.sabotaged)
			new_limb.sabotaged = 1
	target.update_icons_body(FALSE)
	target.UpdateDamageIcon()
	log_game("SURGERY: [key_name(user)] mechanized [key_name(target)] with [L]")
	qdel(L)

/datum/surgical_step/limb/mechanize/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..(user, target, part, tool, target.get_organ(BP_TORSO))


// --- Reconstruction -------------------------------------------------------------------------

/datum/surgical_step/reconstruct_face
	name = "Reconstruct Face"
	allowed_tools = list(
		/obj/item/surgical/retractor = 100,
		/obj/item/material/kitchen/utensil/fork = 75,
	)
	allowed_tool_qualities = list(TOOL_CROWBAR = 55)
	zones = list(BP_HEAD)
	part_biology = BIOLOGY_ORGANIC
	min_depth = FLESH_RETRACTED
	priority = 2
	duration = 7 SECONDS
	pain = 60
	begin_text = "reshaping the face of"
	end_text = "reshapes the face of"
	fail_text = "slips, tearing the skin of"
	pain_text = "Your face feels like it's being pulled apart!"
	complication_kind = INJURY_PIERCE
	complication_amount = 10

/datum/surgical_step/reconstruct_face/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return part.disfigured

/datum/surgical_step/reconstruct_face/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	part.disfigured = FALSE
	log_game("SURGERY: [key_name(user)] reconstructed [key_name(target)]'s face")

/// Rebuild husked tissue: scaffold, relocate flesh and regrow vessels in one
/// long operation.
/datum/surgical_step/dehusk
	name = "Rebuild Husked Tissue"
	allowed_tools = list(
		/obj/item/surgical/bioregen = 100,
		/obj/item/surgical/FixOVein = 80,
		/obj/item/stack/cable_coil = 50,
	)
	zones = list(BP_TORSO)
	part_biology = BIOLOGY_ORGANIC
	min_depth = FLESH_RETRACTED
	priority = 2
	duration = 12 SECONDS
	pain = 80
	blood_level = 2
	begin_text = "rebuilding the husked tissue of"
	end_text = "rebuilds the husked tissue of"
	fail_text = "slips, scraping away more of"
	complication_kind = INJURY_CUT
	complication_amount = 15

/datum/surgical_step/dehusk/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return (HUSK in target.mutations)

/datum/surgical_step/dehusk/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	target.mutations.Remove(HUSK)
	target.status_flags &= ~DISFIGURED
	target.update_icons_body()
	log_game("SURGERY: [key_name(user)] dehusked [key_name(target)]")

/// The jagged scalpel's one purpose: tearing an artery open.
/datum/surgical_step/tear_vessel
	name = "Tear Blood Vessel"
	allowed_tools = list(/obj/item/surgical/scalpel/ripper = 100)
	part_biology = BIOLOGY_ORGANIC
	min_depth = INCISION_MADE
	priority = 1
	duration = 4 SECONDS
	pain = 100
	blood_level = 2
	begin_text = "digging into the vessels of"
	end_text = "tears open an artery in"
	fail_text = "slips, bruising"
	pain_text = "Something is ripping at the inside of your %PART%!"
	complication_kind = INJURY_BLUNT
	complication_amount = 20

/datum/surgical_step/tear_vessel/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	add_attack_logs(user, target, "Tore a blood vessel in [part.name] with [tool]")
	target.injure(INJURY_CUT, 30, part, tool, affliction = /datum/affliction/wound/internal_bleeding, flags = INJURE_IGNORE_RESISTANCE)
	target.drip(30)
	new /obj/effect/gibspawner/human(target.loc, target.dna, target.species.flesh_color, target.species.blood_color)
	target.emote("scream")


// --- Hardsuits ------------------------------------------------------------------------------

/datum/surgical_step/cut_hardsuit
	name = "Remove Hardsuit"
	phase = SURGERY_PHASE_ACCESS
	allowed_tools = list(
		/obj/item/pickaxe/plasmacutter = 100,
		/obj/item/weldingtool = 80,
		/obj/item/surgical/circular_saw = 60,
	)
	zones = list(BP_TORSO)
	part_biology = BIOLOGY_ALL
	duration = 15 SECONDS
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "cutting through the support systems around"
	end_text = "cuts through the support systems around"
	fail_text = "can't quite get through the metal around"
	complication_amount = 0

/datum/surgical_step/cut_hardsuit/proc/locked_rig(mob/living/carbon/human/target)
	if(istype(target.back, /obj/item/rig) && !target.back.canremove)
		return target.back
	if(istype(target.belt, /obj/item/rig) && !target.belt.canremove)
		return target.belt
	return null

/// The rig is in the way of everything else, so it doesn't care about access.
/datum/surgical_step/cut_hardsuit/coverage_check(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part)
	return FALSE

/datum/surgical_step/cut_hardsuit/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(istype(tool, /obj/item/weldingtool))
		var/obj/item/weldingtool/welder = tool
		if(!welder.isOn())
			return FALSE
	return locked_rig(target) ? TRUE : FALSE

/datum/surgical_step/cut_hardsuit/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/rig/rig = locked_rig(target)
	if(istype(tool, /obj/item/weldingtool))
		var/obj/item/weldingtool/welder = tool
		if(!welder.remove_fuel(1, user))
			return
	rig?.cut_suit()
	log_game("SURGERY: [key_name(user)] cut [key_name(target)] out of [rig]")
