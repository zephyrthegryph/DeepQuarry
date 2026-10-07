/obj/machinery/computer/shuttle_control
	// Navigation consoles are protected scenario controls and intentionally ignore structural damage.
	resistance_flags = INDESTRUCTIBLE
	name = "shuttle control console"
	desc = "Used to control a linked shuttle."
	icon_keyboard = "atmos_key"
	icon_screen = "shuttle"
	circuit = null

	var/shuttle_tag  // Used to coordinate data in shuttle controller.
	var/hacked = 0   // Has been emagged, no access restrictions.

	var/skip_act = FALSE
	var/tgui_subtemplate = "ShuttleControlConsoleDefault"
	var/ai_control = TRUE // AI/Borgs shouldn't really be flying off in ships without crew help //ChompStation Edit: Flying is better prevented by restricting the helm console if wanted. This is only an unnecessary nuisance that also breaks various other uses for the shuttle console.

/obj/machinery/computer/shuttle_control/proc/lets_silicon_in(mob/actor, atom/target, obj/item/held)
	if(!ai_control && issilicon(actor))
		return FALSE
	return TRUE

/obj/machinery/computer/shuttle_control/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/shuttle_control/proc/shuttlerich_tgui_data(datum/shuttle/autodock/shuttle)
	var/shuttle_state
	switch(shuttle.moving_status)
		if(SHUTTLE_IDLE) shuttle_state = "idle"
		if(SHUTTLE_WARMUP) shuttle_state = "warmup"
		if(SHUTTLE_INTRANSIT) shuttle_state = "in_transit"

	var/shuttle_status
	switch(shuttle.process_state)
		if(IDLE_STATE)
			var/cannot_depart = shuttle.current_location().cannot_depart(shuttle)
			if (shuttle.in_use)
				shuttle_status = "Busy."
			else if(cannot_depart)
				shuttle_status = cannot_depart
			else
				shuttle_status = "Standing-by at \the [shuttle.get_location_name()]."

		if(WAIT_LAUNCH, FORCE_LAUNCH)
			shuttle_status = "Shuttle has received command and will depart shortly."
		if(WAIT_ARRIVE)
			shuttle_status = "Proceeding to \the [shuttle.get_destination_name()]."
		if(WAIT_FINISH)
			shuttle_status = "Arriving at destination now."

	return list(
		"shuttle_status" = shuttle_status,
		"shuttle_state" = shuttle_state,
		"has_docking" = shuttle.shuttle_docking_controller ? 1 : 0,
		"docking_status" = shuttle.shuttle_docking_controller?.get_docking_status(),
		"docking_override" = shuttle.shuttle_docking_controller?.override_enabled,
		"can_launch" = shuttle.can_launch(),
		"can_cancel" = shuttle.can_cancel(),
		"can_force" = shuttle.can_force(),
		"docking_codes" = shuttle.docking_codes,
		"subtemplate" = tgui_subtemplate,
	)

// This is a subset of the actual checks; contains those that give messages to the user.
// This enables us to give nice error messages as well as not even bother proceeding if we can't.
/obj/machinery/computer/shuttle_control/proc/can_move(datum/shuttle/autodock/shuttle, user)
	var/cannot_depart = shuttle.current_location().cannot_depart(shuttle)
	if(cannot_depart)
		to_chat(user, span_warning("[cannot_depart]"))
		if(shuttle.debug_logging)
			log_shuttle("Shuttle [shuttle] cannot depart [shuttle.current_location()] because: [cannot_depart].")
		return FALSE
	if(!shuttle.next_location().is_valid(shuttle))
		to_chat(user, span_warning("Destination zone is invalid or obstructed."))
		if(shuttle.debug_logging)
			log_shuttle("Shuttle [shuttle] destination [shuttle.next_location()] is invalid.")
		return FALSE
	return TRUE

/obj/machinery/computer/shuttle_control/proc/ui_gate(datum/act/op/A)
	return console_gate(A.actor)

/// The console's guard on every button, and on the answer to a question one of them asked: the shuttle is still linked (a print, a warning).
/obj/machinery/computer/shuttle_control/proc/console_gate(mob/user)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(skip_act)
		return FALSE
	add_fingerprint(user)
	if(!istype(shuttle))
		to_chat(user, span_warning("Unable to establish link with the shuttle."))
		return FALSE
	return TRUE

/obj/machinery/computer/shuttle_control/proc/ui_act_move(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(can_move(shuttle, user))
		shuttle.launch(src, user)
	return TRUE

/obj/machinery/computer/shuttle_control/proc/ui_act_force(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(can_move(shuttle, user))
		shuttle.force_launch(src, user)
	return TRUE

/obj/machinery/computer/shuttle_control/proc/ui_act_cancel(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	shuttle.cancel_launch(src, user)
	return TRUE

/obj/machinery/computer/shuttle_control/proc/ui_act_set_codes(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!ui_gate(A))
		return FALSE
	shuttle_codes_stage(ui, user, FALSE)

/obj/machinery/computer/shuttle_control/proc/shuttle_codes_stage(datum/tgui/ui, mob/actor, answered, newcode)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(!answered)
		open_request(ui, /datum/prompt/text/shuttle_docking_codes, TYPE_PROC_REF(/datum/tgui, shuttle_codes_entered), answerer = actor, default = shuttle.docking_codes, captured = list())
		return
	if(newcode)
		shuttle.set_docking_codes(uppertext(newcode))
	SStgui.update_uis(src)

/datum/tgui/proc/shuttle_codes_entered(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value))
		return
	var/obj/machinery/computer/shuttle_control/console = src_object()
	// The original virtual guard fingerprints and reports failures; it is an effect.
	var/allowed = console.console_gate(user)
	A.request.captured["late_refusal"] = allowed ? null : "the console action is unavailable"
	if(request_recheck(A.request))
		return
	console.shuttle_codes_stage(src, A.request.answerer, TRUE, A.answer.value)

/datum/prompt/text/shuttle_docking_codes
	question = "Input new docking codes"
	title = "Docking codes"
	max_len = MAX_NAME_LEN
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/shuttle_docking_codes/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/text/shuttle_docking_codes/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui) || QDELETED(answerer))
		return "gone"
	var/obj/machinery/computer/shuttle_control/console = original_ui.src_object()
	if(!istype(console) || QDELETED(console))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	return captured?["late_refusal"]

CAPABILITIES(/obj/machinery/computer/shuttle_control)
	interface("ShuttleControl")
	without("ui_open")
	op("move", ui_act("move"), then(PROC_REF(ui_act_move)))
	op("force", ui_act("force"), then(PROC_REF(ui_act_force)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))
	op("set_codes", ui_act("set_codes"), then(PROC_REF(ui_act_set_codes)))
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(shuttle_console_ricochet))))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/obj/machinery/computer/shuttle_control/ui_title(mob/user)
	return "[shuttle_tag] Shuttle Control"

// We delegate populating data to another proc to make it easier for overriding types to add their data.
/obj/machinery/computer/shuttle_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/merged_1 = ui_data_obj_machinery_computer_shuttle_control(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/computer/shuttle_control's window data.
/obj/machinery/computer/shuttle_control/proc/ui_data_obj_machinery_computer_shuttle_control(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(!istype(shuttle))
		to_chat(user, span_warning("Unable to establish link with the shuttle."))
		return

	return shuttlerich_tgui_data(shuttle)

// Call to set the linked shuttle tag; override to add behaviour to shuttle tag changes
/obj/machinery/computer/shuttle_control/proc/set_shuttle_tag(new_shuttle_tag)
	if(shuttle_tag == new_shuttle_tag)
		return FALSE
	shuttle_tag = new_shuttle_tag
	return TRUE

/obj/machinery/computer/shuttle_control/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if (!hacked)
		req_access = list()
		req_one_access = list()
		hacked = 1
		to_chat(user, "You short out the console's ID checking system. It's now available to everyone!")
		return OP_OK
	return OP_DECLINE


/// Rounds ricochet off the console harmlessly.
/obj/machinery/computer/shuttle_control/proc/shuttle_console_ricochet(datum/act/hit/projectile/A)
	var/datum/damage_packet/packet = A.packet
	visible_message("\The [packet.source] ricochets off \the [src]!")
	return OP_OK

/obj/item/paper/dockingcodes
	name = "Docking Codes"
	var/codes_from_z = null //So you can put codes from the station other places to give to antags or whatever

/obj/item/paper/dockingcodes/proc/populate_info()
	var/dockingcodes = null
	var/turf/T = get_turf(src)
	var/our_z
	if(T)
		our_z = T.z
	var/z_to_check = codes_from_z ? codes_from_z : our_z
	if(using_map.use_overmap)
		var/obj/effect/overmap/visitable/location = get_overmap_sector(z_to_check)
		if(location && location.docking_codes)
			dockingcodes = location.docking_codes

	if(!dockingcodes)
		info = "<center><h2>Daily Docking Codes</h2></center><br>The docking security system is down for maintenance. Please exercise caution when shuttles dock and depart."
	else
		info = "<center><h2>Daily Docking Codes</h2></center><br>The docking codes for this shift are '[dockingcodes]'.<br>These codes are secret, as they will allow hostile shuttles to dock with impunity if discovered.<br>"
	info_links = info
	icon_state = "paper_words"
