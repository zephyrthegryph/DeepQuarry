/obj/machinery/computer/shuttle_control/multi
	circuit = /obj/item/circuitboard/shuttle_console/multi
	tgui_subtemplate = "ShuttleControlConsoleMulti"

/obj/machinery/computer/shuttle_control/multi/shuttlerich_tgui_data(datum/shuttle/autodock/multi/shuttle)
	. = ..()
	if(istype(shuttle))
		. += list(
			"destination_name" = shuttle.next_location() ? shuttle.next_location().name : "No destination set.",
			"can_pick" = shuttle.moving_status == SHUTTLE_IDLE,
			"can_cloak" = shuttle.can_cloak ? 1 : 0,
			"cloaked" = shuttle.cloaked ? 1 : 0,
			"legit" = shuttle.legit ? 1 : 0,
			// "engines_charging" = ((shuttle.last_move + (shuttle.cooldown SECONDS)) > world.time), // Replaced by longer warmup_time
		)

/obj/machinery/computer/shuttle_control/multi/console_gate(mob/user)
	if(!..())
		return FALSE
	var/datum/shuttle/autodock/multi/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(!istype(shuttle))
		to_chat(user, span_warning("Unable to establish link with the shuttle."))
		return FALSE
	return TRUE

CAPABILITIES(/obj/machinery/computer/shuttle_control/multi)
	op("pick", ui_act("pick"), then(PROC_REF(ui_act_pick)))
	op("toggle_cloaked", ui_act("toggle_cloaked"), then(PROC_REF(ui_act_toggle_cloaked)))
/obj/machinery/computer/shuttle_control/multi/proc/ui_act_pick(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!ui_gate(A))
		return FALSE
	shuttle_destination_stage(ui, FALSE)

/obj/machinery/computer/shuttle_control/multi/proc/shuttle_destination_stage(datum/tgui/ui, answered, dest_key, datum/request/request)
	var/datum/shuttle/autodock/multi/shuttle = SSshuttles.shuttles[shuttle_tag]
	// This getter may rebuild the current landmark relation cache on every replay.
	var/list/destinations = shuttle.get_destinations()
	if(!answered)
		var/list/labels = list()
		for(var/label in destinations)
			labels += label
		open_request(ui, /datum/prompt/choice/shuttle_destination, TYPE_PROC_REF(/datum/tgui, shuttle_destination_entered), answerer = ui.user, choices = labels, captured = list())
		return
	if(dest_key)
		// CanUseTopic may report Access Denied; keep it outside pure requirements.
		var/usable = CanInteract(ui.user, GLOB.tgui_default_state)
		request.captured["late_refusal"] = usable ? null : "the console cannot be used"
		if(!request_recheck(request))
			shuttle.set_destination(dest_key, ui.user)
	// The original row returns TRUE even when CanInteract refuses the move.
	SStgui.update_uis(src)

/datum/tgui/proc/shuttle_destination_entered(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value))
		return
	var/obj/machinery/computer/shuttle_control/multi/console = src_object()
	var/allowed = console.console_gate(user)
	A.request.captured["late_refusal"] = allowed ? null : "the console action is unavailable"
	if(request_recheck(A.request))
		return
	console.shuttle_destination_stage(src, TRUE, A.answer.value, A.request)

/datum/prompt/choice/shuttle_destination
	question = "Choose shuttle destination"
	title = "Shuttle Destination"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/shuttle_destination/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/computer/shuttle_control/multi/console = original_ui.src_object()
	if(!istype(console) || QDELETED(console))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	return captured?["late_refusal"]

/obj/machinery/computer/shuttle_control/multi/proc/ui_act_toggle_cloaked(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/shuttle/autodock/multi/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(!shuttle.can_cloak)
		return TRUE
	shuttle.cloaked = !shuttle.cloaked
	if(shuttle.legit)
		to_chat(user, span_notice("Ship ATC inhibitor systems have been [(shuttle.cloaked ? "activated. The station will not" : "deactivated. The station will")] be notified of our arrival."))
	else
		to_chat(user, span_warning("Ship stealth systems have been [(shuttle.cloaked ? "activated. The station will not" : "deactivated. The station will")] be warned of our arrival."))
	return TRUE
