//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/aiupload
	name = "\improper AI upload console"
	desc = "Used to upload laws to the AI."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/aiupload
	var/current_handle
	var/opened = 0


/obj/machinery/computer/aiupload/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_verb/aiupload_access_internals,
		/datum/interaction/machine_item/aiupload_install,
		/datum/interaction/machine_hand/ungated/aiupload_select_ai,
	)
	into += dq_interaction_from_spec(type, INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_swallow)))
	..()

/// The old "Access Computer's Internals" object verb.
/datum/interaction/machine_verb/aiupload_access_internals
	id = "aiupload_access_internals"
	name = "Access Computer's Internals"
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/computer/aiupload/proc/interaction_access_internals

/obj/machinery/computer/aiupload/proc/interaction_access_internals(mob/user, obj/item/held, datum/interaction/interaction)
	if(get_dist(src, user) > 1 || user.restrained() || user.lying || user.stat || istype(user, /mob/living/silicon))
		return TRUE

	opened = !opened
	if(opened)
		to_chat(user, span_notice("The access panel is now open."))
	else
		to_chat(user, span_notice("The access panel is now closed."))
	return TRUE

/// The old attackby: installs an AI module, else falls through to the base behaviour.
/datum/interaction/machine_item/aiupload_install
	id = "aiupload_install"
	name = "Install module"
	held_type = /obj/item
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/computer/aiupload/proc/can_connect))
	effect = /obj/machinery/computer/aiupload/proc/interaction_install

/// Requirement: the console only reaches the station's contact levels.
/obj/machinery/computer/aiupload/proc/can_connect(mob/user, atom/target, obj/item/held)
	if(using_map && !(user.z in using_map.contact_levels))
		return "unable to establish a connection, you're too far away from the station"
	return TRUE

/// Requirement: TRUE, or why no AI can be selected.
/obj/machinery/computer/aiupload/proc/can_select_ai(mob/user, atom/target, obj/item/held)
	if(has_stat(NOPOWER))
		return "the upload computer has no power"
	if(has_stat(BROKEN))
		return "the upload computer is broken"
	if(!length(active_ais()))
		return "no active AIs detected"
	return TRUE

/obj/machinery/computer/aiupload/proc/interaction_install(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/aiModule))
		var/obj/item/aiModule/M = O
		M.install(src, user)
		return TRUE
	return FALSE

/// The old attack_hand: never called ..(), selected an active AI for law changes.
/datum/interaction/machine_hand/ungated/aiupload_select_ai
	id = "aiupload_select_ai"
	name = "Select AI"
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/computer/aiupload/proc/can_select_ai))
	effect = /obj/machinery/computer/aiupload/proc/interaction_select_ai

/obj/machinery/computer/aiupload/proc/interaction_select_ai(mob/user, obj/item/held, datum/interaction/interaction)
	// Also the selection prompt's callback: re-check quietly (can_select_ai() told the user up front).
	if(has_stat(NOPOWER) || has_stat(BROKEN) || !length(active_ais()))
		return TRUE
	var/mob/living/silicon/ai/picked = select_active_ai(user, src, PROC_REF(interaction_select_ai), args)
	if(picked)
		src.current_handle = om_handle(picked)
		to_chat(user, "[src.current().name] selected for law changes.")
	return TRUE

/obj/machinery/computer/borgupload
	name = "cyborg upload console"
	desc = "Used to upload laws to Cyborgs."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/borgupload
	var/current_handle


/obj/machinery/computer/borgupload/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/borgupload_install,
		/datum/interaction/machine_hand/ungated/borgupload_select_borg,
	)
	into += dq_interaction_from_spec(type, INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_swallow)))
	..()

/// The old attackby: installs an AI module, else falls through to the base behaviour.
/datum/interaction/machine_item/borgupload_install
	id = "borgupload_install"
	name = "Install module"
	held_type = /obj/item/aiModule
	effect = /obj/machinery/computer/borgupload/proc/interaction_install

/obj/machinery/computer/borgupload/proc/interaction_install(mob/user, obj/item/aiModule/module, datum/interaction/interaction)
	module.install(src, user)
	return TRUE

/// The old attack_hand: never called ..(), selected a free cyborg for law changes.
/datum/interaction/machine_hand/ungated/borgupload_select_borg
	id = "borgupload_select_borg"
	name = "Select cyborg"
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/computer/borgupload/proc/can_select_borg))
	effect = /obj/machinery/computer/borgupload/proc/interaction_select_borg

/// Requirement: TRUE, or why no cyborg can be selected.
/obj/machinery/computer/borgupload/proc/can_select_borg(mob/user, atom/target, obj/item/held)
	if(has_stat(NOPOWER))
		return "the upload computer has no power"
	if(has_stat(BROKEN))
		return "the upload computer is broken"
	if(!length(free_borg_choices()))
		return "no free cyborgs detected"
	return TRUE

/obj/machinery/computer/borgupload/proc/interaction_select_borg(mob/user, obj/item/held, datum/interaction/interaction)
	// Also the selection prompt's callback: re-check quietly (can_select_borg() told the user up front).
	if(has_stat(NOPOWER) || has_stat(BROKEN) || !length(free_borg_choices()))
		return TRUE
	var/mob/living/silicon/robot/picked = freeborg(user, src, PROC_REF(interaction_select_borg), args)
	if(picked)
		src.current_handle = om_handle(picked)
		to_chat(user, "[src.current().name] selected for law changes.")
	return TRUE


/// LC-refs: current -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/aiupload/proc/current() as /mob/living/silicon/ai
	return om_resolve(current_handle)

/// LC-refs: current -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/borgupload/proc/current() as /mob/living/silicon/robot
	return om_resolve(current_handle)
