//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/aiupload
	name = "\improper AI upload console"
	desc = "Used to upload laws to the AI."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/aiupload
	var/mob/living/silicon/ai/current = null
	var/opened = 0


/obj/machinery/computer/aiupload/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_verb/aiupload_access_internals,
		/datum/interaction/machine_item/aiupload_install,
		/datum/interaction/machine_hand/ungated/aiupload_select_ai,
	)
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
	effect = /obj/machinery/computer/aiupload/proc/interaction_install

/obj/machinery/computer/aiupload/proc/interaction_install(mob/user, obj/item/O, datum/interaction/interaction)
	if(using_map && !(user.z in using_map.contact_levels))
		to_chat(user, span_danger("Unable to establish a connection:") + " You're too far away from the station!")
		return TRUE
	if(istype(O, /obj/item/aiModule))
		var/obj/item/aiModule/M = O
		M.install(src, user)
		return TRUE
	return FALSE

/// The old attack_hand: never called ..(), selected an active AI for law changes.
/datum/interaction/machine_hand/ungated/aiupload_select_ai
	id = "aiupload_select_ai"
	name = "Select AI"
	effect = /obj/machinery/computer/aiupload/proc/interaction_select_ai

/obj/machinery/computer/aiupload/proc/interaction_select_ai(mob/user, obj/item/held, datum/interaction/interaction)
	if(src.stat & NOPOWER)
		to_chat(user, "The upload computer has no power!")
		return TRUE
	if(src.stat & BROKEN)
		to_chat(user, "The upload computer is broken!")
		return TRUE

	src.current = select_active_ai(user)

	if (!src.current)
		to_chat(user, "No active AIs detected.")
	else
		to_chat(user, "[src.current.name] selected for law changes.")
	return TRUE

/obj/machinery/computer/aiupload/attack_ghost(user as mob)
	return 1


/obj/machinery/computer/borgupload
	name = "cyborg upload console"
	desc = "Used to upload laws to Cyborgs."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/borgupload
	var/mob/living/silicon/robot/current = null


/obj/machinery/computer/borgupload/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/borgupload_install,
		/datum/interaction/machine_hand/ungated/borgupload_select_borg,
	)
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
	effect = /obj/machinery/computer/borgupload/proc/interaction_select_borg

/obj/machinery/computer/borgupload/proc/interaction_select_borg(mob/user, obj/item/held, datum/interaction/interaction)
	if(src.stat & NOPOWER)
		to_chat(user, "The upload computer has no power!")
		return TRUE
	if(src.stat & BROKEN)
		to_chat(user, "The upload computer is broken!")
		return TRUE

	src.current = freeborg()

	if (!src.current)
		to_chat(user, "No free cyborgs detected.")
	else
		to_chat(user, "[src.current.name] selected for law changes.")
	return TRUE

/obj/machinery/computer/borgupload/attack_ghost(user as mob)
	return 1
