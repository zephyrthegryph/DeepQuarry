//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/aiupload
	name = "\improper AI upload console"
	desc = "Used to upload laws to the AI."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/aiupload
	var/mob/living/silicon/ai/current
	var/opened = 0


EXTEND_INTERACTIONS(/obj/machinery/computer/aiupload, \
	INTERACT_VERB("Access Computer's Internals", PROC_REF(interaction_access_internals)), \
	INTERACT_INSERT(/obj/item, PROC_REF(interaction_install), "Install module", REQ_TARGET_STATE(/obj/machinery/computer/aiupload/proc/can_connect)), \
	INTERACT_HAND_UNGATED("Select AI", PROC_REF(interaction_select_ai), REQ_TARGET_STATE(/obj/machinery/computer/aiupload/proc/can_select_ai)), \
	INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_swallow)), \
)

/obj/machinery/computer/aiupload/proc/interaction_access_internals(mob/user, obj/item/held, datum/interaction/interaction)
	if(get_dist(src, user) > 1 || user.restrained() || user.lying || user.stat || istype(user, /mob/living/silicon))
		return TRUE

	opened = !opened
	if(opened)
		to_chat(user, span_notice("The access panel is now open."))
	else
		to_chat(user, span_notice("The access panel is now closed."))
	return TRUE

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

/obj/machinery/computer/aiupload/proc/interaction_select_ai(mob/user, obj/item/held, datum/interaction/interaction)
	// Also the selection prompt's callback: re-check quietly (can_select_ai() told the user up front).
	if(has_stat(NOPOWER) || has_stat(BROKEN) || !length(active_ais()))
		return TRUE
	var/mob/living/silicon/ai/picked = select_active_ai(user, src, PROC_REF(interaction_select_ai), args)
	if(picked)
		rel_set(src, nameof(current), picked)
		to_chat(user, "[src.current().name] selected for law changes.")
	return TRUE

/obj/machinery/computer/borgupload
	name = "cyborg upload console"
	desc = "Used to upload laws to Cyborgs."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/borgupload
	var/mob/living/silicon/robot/current


EXTEND_INTERACTIONS(/obj/machinery/computer/borgupload, \
	INTERACT_INSERT(/obj/item/aiModule, PROC_REF(interaction_install), "Install module"), \
	INTERACT_HAND_UNGATED("Select cyborg", PROC_REF(interaction_select_borg), REQ_TARGET_STATE(/obj/machinery/computer/borgupload/proc/can_select_borg)), \
	INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_swallow)), \
)

/obj/machinery/computer/borgupload/proc/interaction_install(mob/user, obj/item/aiModule/module, datum/interaction/interaction)
	module.install(src, user)
	return TRUE

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
		rel_set(src, nameof(current), picked)
		to_chat(user, "[src.current().name] selected for law changes.")
	return TRUE


/// current (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/aiupload/proc/current() as /mob/living/silicon/ai
	return current

/// current (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/borgupload/proc/current() as /mob/living/silicon/robot
	return current
