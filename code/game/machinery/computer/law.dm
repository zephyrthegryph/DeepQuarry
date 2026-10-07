//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/aiupload
	name = "\improper AI upload console"
	desc = "Used to upload laws to the AI."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/aiupload
	var/mob/living/silicon/ai/current
	var/opened = 0


CAPABILITIES(/obj/machinery/computer/aiupload)
	op("access_internals", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Access Computer's Internals"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_access_internals)))
	op("install_module", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Install module"), needs(req(PROC_REF(can_connect_holds), because = PROC_REF(can_connect_refusal))), then(PROC_REF(interaction_install)))
	op("select_ai", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Select AI"), needs(req(PROC_REF(can_select_ai_holds), because = PROC_REF(can_select_ai_refusal))),
		asks(/datum/prompt/choice/ai_upload_selection, fields = list("title" = "AI selection", "question" = "AI signals detected:"), step = "selection"), then(PROC_REF(interaction_select_ai)))
	op("observer_view", observer(), priority(OP_PRIORITY_DEFAULT - 1), label("View"), then(TYPE_PROC_REF(/atom, op_swallow)))
/obj/machinery/computer/aiupload/proc/interaction_access_internals(datum/act/op/A)
	var/mob/user = A.actor
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
	if(power_lost())
		return "the upload computer has no power"
	if(broken_now())
		return "the upload computer is broken"
	return TRUE

/obj/machinery/computer/aiupload/proc/interaction_install(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/aiModule))
		var/obj/item/aiModule/M = O
		M.install(src, user)
		return TRUE
	return FALSE

/obj/machinery/computer/aiupload/proc/interaction_select_ai(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/ai/picked = A.step_value("selection")
	if(!(picked in active_ais()))
		return OP_OK
	if(picked)
		rel_set(src, nameof(current), picked)
		to_chat(user, "[src.current().name] selected for law changes.")
	return OP_OK

/obj/machinery/computer/borgupload
	name = "cyborg upload console"
	desc = "Used to upload laws to Cyborgs."
	icon_keyboard = "rd_key"
	icon_screen = "command"
	circuit = /obj/item/circuitboard/borgupload
	var/mob/living/silicon/robot/current


CAPABILITIES(/obj/machinery/computer/borgupload)
	op("install_module", item(/obj/item/aiModule), priority(OP_PRIORITY_DEFAULT - 1), label("Install module"), then(PROC_REF(interaction_install)))
	op("select_borg", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Select cyborg"), needs(req(PROC_REF(can_select_borg_holds), because = PROC_REF(can_select_borg_refusal))),
		asks(/datum/prompt/choice/borg_upload_selection, fields = list("title" = "Borg selection", "question" = "Unshackled borg signals detected:"), step = "selection"), then(PROC_REF(interaction_select_borg)))
	op("observer_view", observer(), priority(OP_PRIORITY_DEFAULT - 1), label("View"), then(TYPE_PROC_REF(/atom, op_swallow)))
/obj/machinery/computer/borgupload/proc/interaction_install(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/aiModule/module = A.held
	module.install(src, user)
	return TRUE

/// Requirement: TRUE, or why no cyborg can be selected.
/obj/machinery/computer/borgupload/proc/can_select_borg(mob/user, atom/target, obj/item/held)
	if(power_lost())
		return "the upload computer has no power"
	if(broken_now())
		return "the upload computer is broken"
	return TRUE

/obj/machinery/computer/borgupload/proc/interaction_select_borg(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/robot/picked = free_borg_choices()[A.step_value("selection")]
	if(picked)
		rel_set(src, nameof(current), picked)
		to_chat(user, "[src.current().name] selected for law changes.")
	return OP_OK

/// current (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/aiupload/proc/current() as /mob/living/silicon/ai
	return current

/// current (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/borgupload/proc/current() as /mob/living/silicon/robot
	return current


/obj/machinery/computer/aiupload/proc/can_select_ai_holds(datum/act/op/A)
	return can_select_ai(A.actor, src, A.held) == TRUE

/obj/machinery/computer/aiupload/proc/can_select_ai_refusal(datum/act/op/A)
	return can_select_ai(A.actor, src, A.held)

/obj/machinery/computer/aiupload/proc/can_connect_holds(datum/act/op/A)
	return can_connect(A.actor, src, A.held) == TRUE

/obj/machinery/computer/aiupload/proc/can_connect_refusal(datum/act/op/A)
	return can_connect(A.actor, src, A.held)


/obj/machinery/computer/borgupload/proc/can_select_borg_holds(datum/act/op/A)
	return can_select_borg(A.actor, src, A.held) == TRUE

/obj/machinery/computer/borgupload/proc/can_select_borg_refusal(datum/act/op/A)
	return can_select_borg(A.actor, src, A.held)

/// Current registry candidates are request fields, not a cached world output.
/datum/prompt/choice/ai_upload_selection
	recheck_on_open = TRUE

/datum/prompt/choice/ai_upload_selection/prepare(datum/act/A)
	..()
	choices = active_ais()

/datum/prompt/choice/ai_upload_selection/recheck_extra()
	if(!length(active_ais()))
		return "no active AIs detected"
	return null

/datum/prompt/choice/borg_upload_selection
	recheck_on_open = TRUE

/datum/prompt/choice/borg_upload_selection/prepare(datum/act/A)
	..()
	choices = free_borg_choices()

/datum/prompt/choice/borg_upload_selection/recheck_extra()
	if(!length(free_borg_choices()))
		return "no free cyborgs detected"
	return null
