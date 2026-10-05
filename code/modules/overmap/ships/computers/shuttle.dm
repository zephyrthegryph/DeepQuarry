// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//Shuttle controller computer for shuttles going between sectors
/obj/machinery/computer/shuttle_control/explore
	name = "general shuttle control console"
	circuit = /obj/item/circuitboard/shuttle_console/explore
	tgui_subtemplate = "ShuttleControlConsoleExploration"

/obj/machinery/computer/shuttle_control/explore/shuttlerich_tgui_data(datum/shuttle/autodock/overmap/shuttle)
	. = ..()
	if(istype(shuttle))
		var/total_gas = 0
		for(var/obj/structure/fuel_port/FP in shuttle.fuel_ports) //loop through fuel ports
			var/obj/item/tank/fuel_tank = locate_within(FP, /obj/item/tank)
			if(fuel_tank)
				total_gas += fuel_tank.air_contents.total_moles()

		var/fuel_span = "good"
		if(total_gas < shuttle.fuel_consumption * 2)
			fuel_span = "bad"

		. += list(
			"destination_name" = shuttle.get_destination_name(),
			"can_pick" = shuttle.moving_status == SHUTTLE_IDLE,
			"fuel_usage" = shuttle.fuel_consumption * 100,
			"remaining_fuel" = round(total_gas, 0.01) * 100,
			"fuel_span" = fuel_span,
			"expedition" = expedition_data(),
			"can_plot_expedition" = shuttle.moving_status == SHUTTLE_IDLE && can_plot_expedition()
		)

/obj/machinery/computer/shuttle_control/explore/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/datum/shuttle/autodock/overmap/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(!istype(shuttle))
		to_chat(ui.user, span_warning("Unable to establish link with the shuttle."))
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/computer/shuttle_control/explore, "plot_expedition", ui_act_plot_expedition)
UI_ACT_PROC(/obj/machinery/computer/shuttle_control/explore, ui_act_plot_expedition)
	var/datum/shuttle/autodock/overmap/shuttle = SSshuttles.shuttles[shuttle_tag]
	plot_expedition(ui.user, shuttle)
	return TRUE

UI_ACT(/obj/machinery/computer/shuttle_control/explore, "pick", ui_act_pick)
UI_ACT_PROC(/obj/machinery/computer/shuttle_control/explore, ui_act_pick)
	return explore_destination_stage(ui, FALSE)

/obj/machinery/computer/shuttle_control/explore/proc/explore_destination_stage(datum/tgui/ui, answered, selected, datum/request/request)
	var/datum/shuttle/autodock/overmap/shuttle = SSshuttles.shuttles[shuttle_tag]
	var/list/possible_d = shuttle.get_possible_destinations()
	var/destination_key
	if(possible_d.len)
		if(!answered)
			var/list/labels = list()
			for(var/label in possible_d)
				labels += label
			open_request(ui, /datum/prompt/choice/explore_shuttle_destination, TYPE_PROC_REF(/datum/tgui, explore_shuttle_destination_entered), answerer = ui.user, choices = labels, captured = list())
			return
		destination_key = selected
	else
		to_chat(ui.user,span_warning("No valid landing sites in range."))
	possible_d = shuttle.get_possible_destinations()
	// CanUseTopic may emit Access Denied even when there was no selected destination.
	var/usable = CanInteract(ui.user, GLOB.tgui_default_state)
	var/refusal = explore_destination_refusal(usable, destination_key, possible_d)
	if(request)
		request.captured["late_refusal"] = refusal
		refusal = request_recheck(request)
	if(!refusal)
		shuttle.set_destination(possible_d[destination_key])
	return TRUE

/datum/tgui/proc/explore_shuttle_destination_entered(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value))
		return
	var/obj/machinery/computer/shuttle_control/explore/console = src_object()
	var/allowed = console.ui_act_allowed(user, "pick", src, state())
	A.request.captured["late_refusal"] = allowed ? null : "the console action is unavailable"
	if(request_recheck(A.request))
		return
	if(console.explore_destination_stage(src, TRUE, A.answer.value, A.request))
		SStgui.update_uis(console)

/proc/explore_destination_refusal(usable, destination_key, list/possible_d)
	if(!usable || !(destination_key in possible_d))
		return "the destination cannot be selected"
	return null

/datum/prompt/choice/explore_shuttle_destination
	question = "Choose shuttle destination"
	title = "Shuttle Destination"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/explore_shuttle_destination/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/computer/shuttle_control/explore/console = original_ui.src_object()
	if(!istype(console) || QDELETED(console))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	return captured?["late_refusal"]
