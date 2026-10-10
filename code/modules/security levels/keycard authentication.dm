/obj/machinery/keycard_auth
	name = "Keycard Authentication Device"
	desc = "This device is used to trigger station functions, which require more than one ID card to authenticate."
	icon = 'icons/obj/monitors.dmi'
	icon_state = "auth_off"
	layer = ABOVE_WINDOW_LAYER
	circuit = /obj/item/circuitboard/keycard_auth
	flags = WALL_ITEM
	active = 0 //This gets set to 1 on all devices except the one where the initial request was made.
	var/event = ""
	var/screen = 1
	var/confirmed = 0 //This variable is set by the device that confirms the request.
	var/confirm_delay = 20 //(2 seconds)
	var/tmp/obj/machinery/keycard_auth/event_source
	var/tmp/mob/event_triggered_by
	var/tmp/mob/event_confirmed_by
	//1 = select event
	//2 = authenticate
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON

MSG_DEF_SELF(keycard_auth/unpowered, "this device is not powered")

/// Old attack_ai: refuse silicons.
/obj/machinery/keycard_auth/proc/keycard_auth_silicon_refuse(datum/act/op/A)
	to_chat(A.actor, span_warning("A firewall prevents you from interfacing with this device!"))
	return OP_OK

/obj/machinery/keycard_auth/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	use_tool(user, tool, src, delay = 1 SECOND, volume = 50, start_self = "You begin removing the faceplate from the [src]", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	return OP_OK

/obj/machinery/keycard_auth/proc/screwdriver_act_tool_done(mob/user)
	to_chat(user, "You remove the faceplate from the [src]")
	var/obj/structure/frame/A = new /obj/structure/frame(loc)
	var/obj/item/circuitboard/board = circuit
	rel_set(A, nameof(A.frame_type), frame_type_copy(board.board_type)) // the board owns its frame type; the frame takes a copy
	board.forceMove(A)
	own_move(board, A, nameof(A.circuit)) // the board goes from this machine to the frame
	A.need_circuit = FALSE
	A.pixel_x = pixel_x
	A.pixel_y = pixel_y
	A.set_dir(dir)
	A.set_anchored(TRUE)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/C in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(istype(C, /obj/item/circuitboard))
			C.forceMove(A)
			continue
		C.forceMove(loc)
	rel_move(src, nameof(forensic_data), A, nameof(A.forensic_data)) //carry crime data over.
	A.state = FRAME_WIRED
	changed(A)
	destroyed(src, user, "deconstructed")
	return ITEM_INTERACT_SUCCESS

/// Old attackby never called ..(): every item is swallowed by this, id cards checked for access.
/obj/machinery/keycard_auth/proc/interaction_swipe(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/card/id))
		var/obj/item/card/id/ID = W
		if(ACCESS_KEYCARD_AUTH in ID.GetAccess())
			if(active == 1)
				//This is not the device that made the initial request. It is the device confirming the request.
				if(event_source())
					event_source().confirmed = 1
					rel_set(event_source(), nameof(/obj/machinery/keycard_auth::event_confirmed_by), user)
			else if(screen == 2)
				rel_set(src, nameof(event_triggered_by), user)
				broadcast_request(user) //This is the device making the initial event request. It needs to broadcast to other devices
	return OP_OK

/obj/machinery/keycard_auth/power_change()
	. = ..()
	if(power_lost())
		icon_state = "auth_off"

// TGUI migration. attack_hand opens KeycardAuth.tsx;
// Topic event/reset actions move to tgui_act.
/// Requirement: TRUE, or why the panel can't be opened. Non-dexterous users fall through in the effect.
/obj/machinery/keycard_auth/proc/can_open_panel(mob/user, atom/target, obj/item/held)
	if(user.stat || !operable())
		return "this device is not powered"
	if(user.IsAdvancedToolUser() && work_busy(src))
		return "this device is busy"
	return TRUE

/// Requirement: the panel can be opened.
/obj/machinery/keycard_auth/proc/can_open_panel_holds(datum/act/op/A)
	var/answer = can_open_panel(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_open_panel_holds refuses: the check's own text.
/obj/machinery/keycard_auth/proc/can_open_panel_refusal(datum/act/op/A)
	var/answer = can_open_panel(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Requirement: the device is powered.
/obj/machinery/keycard_auth/proc/swipe_powered(datum/act/op/A)
	return (operable()) ? null : MSG(keycard_auth/unpowered)

/obj/machinery/keycard_auth/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.IsAdvancedToolUser())
		return OP_DECLINE
	tgui_interact(user)
	return OP_OK

CAPABILITIES(/obj/machinery/keycard_auth)
	interface("KeycardAuth", title = "Keycard Authentication")
	without("ui_open")
	op("triggerevent", ui_act("triggerevent", arg("event", schema_text(4096))), then(PROC_REF(ui_act_triggerevent)))
	op("reset", ui_act("reset"), then(PROC_REF(ui_act_reset)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("keycard_auth_silicon_refuse", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(keycard_auth_silicon_refuse)))
	op("keycard_auth_swipe", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 2), label("Swipe"), needs(req(PROC_REF(swipe_powered))), then(PROC_REF(interaction_swipe)))
	op("keycard_auth_open_ui", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 3), label("Use"), needs(req_bool(PROC_REF(can_open_panel_holds), because = PROC_REF(can_open_panel_refusal))), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/keycard_auth/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["screen"] = screen
	data["event"] = event
	var/list/merged_1 = ui_data_obj_machinery_keycard_auth(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/keycard_auth's window data.
/obj/machinery/keycard_auth/proc/ui_data_obj_machinery_keycard_auth(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["ert_admin_only"] = CONFIG_GET(flag/ert_admin_call_only) ? 1 : 0
	return data

/obj/machinery/keycard_auth/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(work_busy(src))
		to_chat(user, "This device is busy.")
		return FALSE
	if(user.stat || !operable())
		to_chat(user, "This device is without power.")
		return FALSE
	return TRUE

/obj/machinery/keycard_auth/proc/ui_act_triggerevent(datum/act/op/A, event_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	event = event_arg
	screen = 2
	add_fingerprint(user)
	return TRUE

/obj/machinery/keycard_auth/proc/ui_act_reset(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	reset()
	add_fingerprint(user)
	return TRUE

/obj/machinery/keycard_auth/proc/reset()
	set_active(0)
	event = ""
	screen = 1
	confirmed = 0
	rel_clear(src, nameof(event_source))
	icon_state = "auth_off"
	rel_clear(src, nameof(event_triggered_by))
	rel_clear(src, nameof(event_confirmed_by))

/obj/machinery/keycard_auth/proc/broadcast_request(mob/user)
	icon_state = "auth_on"
	for(var/obj/machinery/keycard_auth/KA in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(KA == src) continue
		KA.reset()
		KA.receive_request(src)

	after(src, confirm_delay, PROC_REF(request_window_closed), with = list(user))

/// The confirmation window is over: fire the event if someone confirmed it.
/obj/machinery/keycard_auth/proc/request_window_closed(mob/user)
	if(confirmed)
		confirmed = 0
		trigger_event(user)
		log_game("[key_name(event_triggered_by())] triggered and [key_name(event_confirmed_by())] confirmed event [event]")
		message_admins("[key_name(event_triggered_by())] triggered and [key_name(event_confirmed_by())] confirmed event [event]", 1)
	reset()

/obj/machinery/keycard_auth/proc/receive_request(obj/machinery/keycard_auth/source)
	if(!operable())
		return
	rel_set(src, nameof(event_source), source)
	// Busy for the confirmation window: a hold claims the device and closes the window when it ends.
	release_busy(src, PROC_REF(receive_window_closed))
	set_active(1)
	icon_state = "auth_on"
	hold_busy(src, confirm_delay, PROC_REF(receive_window_closed))

/obj/machinery/keycard_auth/proc/receive_window_closed()
	rel_clear(src, nameof(event_source))
	icon_state = "auth_off"
	set_active(0)

/obj/machinery/keycard_auth/proc/trigger_event(mob/user)
	switch(event)
		if("Red alert")
			set_security_level(SEC_LEVEL_RED)
			feedback_inc("alert_keycard_auth_red",1)
		if("Grant Emergency Maintenance Access")
			make_maint_all_access()
			feedback_inc("alert_keycard_auth_maintGrant",1)
		if("Revoke Emergency Maintenance Access")
			revoke_maint_all_access()
			feedback_inc("alert_keycard_auth_maintRevoke",1)
		if("Emergency Response Team")
			if(is_ert_blocked())
				to_chat(user, span_red("All emergency response teams are dispatched and can not be called at this time."))
				return

			trigger_armed_response_team(1)
			feedback_inc("alert_keycard_auth_ert",1)

/obj/machinery/keycard_auth/proc/is_ert_blocked()
	if(CONFIG_GET(flag/ert_admin_call_only)) return 1
	return ticker_mode() && ticker_mode().ert_disabled

GLOBAL_VAR_INIT(maint_all_access, FALSE)

/proc/make_maint_all_access()
	GLOB.maint_all_access = TRUE
	to_chat(world, span_alert(span_red(span_huge("Attention!"))))
	to_chat(world, span_alert(span_red("The maintenance access requirement has been revoked on all airlocks.")))

/proc/revoke_maint_all_access()
	GLOB.maint_all_access = FALSE
	to_chat(world, span_alert(span_red(span_huge("Attention!"))))
	to_chat(world, span_alert(span_red("The maintenance access requirement has been readded on all maintenance airlocks.")))

/obj/machinery/door/airlock/allowed(mob/M)
	if(GLOB.maint_all_access && src.check_access_list(list(ACCESS_MAINT_TUNNELS)))
		return 1
	return ..(M)

/// The event_triggered_by (a relation view).
/obj/machinery/keycard_auth/proc/event_triggered_by() as /mob
	return event_triggered_by

/// The event_confirmed_by (a relation view).
/obj/machinery/keycard_auth/proc/event_confirmed_by() as /mob
	return event_confirmed_by

/// The event_source (a relation view).
/obj/machinery/keycard_auth/proc/event_source() as /obj/machinery/keycard_auth
	return event_source
