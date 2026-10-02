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

/obj/machinery/computer/shuttle_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/shuttle_control_open_ui,
	)
	..()

/datum/interaction/machine_hand/shuttle_control_open_ui
	id = "shuttle_control_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_ACTOR, /obj/machinery/computer/shuttle_control/proc/lets_silicon_in, "access denied"), REQ_ON(PRED_ACTOR, /obj/machinery/computer/shuttle_control/proc/lets_in, "access denied"))
	effect = /atom/proc/interaction_open_ui

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

/obj/machinery/computer/shuttle_control/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(skip_act)
		return FALSE
	add_fingerprint(ui.user)
	if(!istype(shuttle))
		to_chat(ui.user, span_warning("Unable to establish link with the shuttle."))
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/computer/shuttle_control, "move", ui_act_move)
UI_ACT_PROC(/obj/machinery/computer/shuttle_control, ui_act_move)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(can_move(shuttle, ui.user))
		shuttle.launch(src, ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/shuttle_control, "force", ui_act_force)
UI_ACT_PROC(/obj/machinery/computer/shuttle_control, ui_act_force)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	if(can_move(shuttle, ui.user))
		shuttle.force_launch(src, ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/shuttle_control, "cancel", ui_act_cancel)
UI_ACT_PROC(/obj/machinery/computer/shuttle_control, ui_act_cancel)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	shuttle.cancel_launch(src, ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/shuttle_control, "set_codes", ui_act_set_codes)
UI_ACT_PROC(/obj/machinery/computer/shuttle_control, ui_act_set_codes)
	var/datum/shuttle/autodock/shuttle = SSshuttles.shuttles[shuttle_tag]
	var/newcode = act_ask(ui.user, action, params, ui, "k121", /datum/om/prompt/text, message = "Input new docking codes", title = "Docking codes", default = shuttle.docking_codes, max_length = MAX_NAME_LEN)
	if(isnull(newcode))
		return
	// The answer's re-run already re-checked the window is still usable.
	if(newcode)
		shuttle.set_docking_codes(uppertext(newcode))
	return TRUE

DECLARE_UI(/obj/machinery/computer/shuttle_control, "ShuttleControl")

/obj/machinery/computer/shuttle_control/ui_title(mob/user)
	return "[shuttle_tag] Shuttle Control"

// We delegate populating data to another proc to make it easier for overriding types to add their data.
UI_DATA_REPLACE(/obj/machinery/computer/shuttle_control, "merge:ui_data_obj_machinery_computer_shuttle_control{}")

/// The computed part of /obj/machinery/computer/shuttle_control's window data (declared on its UI_DATA row).
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

DECLARE_EMAG_REPEATABLE(/obj/machinery/computer/shuttle_control, PROC_REF(on_emag), null)
/obj/machinery/computer/shuttle_control/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if (!hacked)
		req_access = list()
		req_one_access = list()
		hacked = 1
		to_chat(user, "You short out the console's ID checking system. It's now available to everyone!")
		return 1

DAMAGE_REACTION(/obj/machinery/computer/shuttle_control, DAMAGE_PROJECTILE, PROC_REF(shuttle_console_ricochet))

/// Rounds ricochet off the console harmlessly.
/obj/machinery/computer/shuttle_control/proc/shuttle_console_ricochet(datum/damage_packet/packet)
	visible_message("\The [packet.source] ricochets off \the [src]!")
	return DAMAGE_REACTION_BLOCK

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
