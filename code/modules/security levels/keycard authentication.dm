/obj/machinery/keycard_auth
	name = "Keycard Authentication Device"
	desc = "This device is used to trigger station functions, which require more than one ID card to authenticate."
	icon = 'icons/obj/monitors.dmi'
	icon_state = "auth_off"
	layer = ABOVE_WINDOW_LAYER
	circuit = /obj/item/circuitboard/keycard_auth
	flags = WALL_ITEM
	var/active = 0 //This gets set to 1 on all devices except the one where the initial request was made.
	var/event = ""
	var/screen = 1
	var/confirmed = 0 //This variable is set by the device that confirms the request.
	var/confirm_delay = 20 //(2 seconds)
	var/tmp/event_source_handle
	var/tmp/event_triggered_by_handle
	var/tmp/event_confirmed_by_handle
	//1 = select event
	//2 = authenticate
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON

/// Old attack_ai: refuse silicons.
/obj/machinery/keycard_auth/proc/keycard_auth_silicon_refuse(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_warning("A firewall prevents you from interfacing with this device!"))
	return TRUE

/obj/machinery/keycard_auth/screwdriver_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 1 SECOND, volume = 50, start_self = "You begin removing the faceplate from the [src]", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_BLOCKING

/obj/machinery/keycard_auth/proc/screwdriver_act_tool_done(mob/user)
	to_chat(user, "You remove the faceplate from the [src]")
	var/obj/structure/frame/A = new /obj/structure/frame(loc)
	A.circuit = circuit
	A.frame_type = circuit.board_type
	circuit = null
	A.need_circuit = FALSE
	A.pixel_x = pixel_x
	A.pixel_y = pixel_y
	A.set_dir(dir)
	A.anchored = TRUE
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/C in contents_of(src)) // ALLOW(latent): materialized above
		if(istype(C, /obj/item/circuitboard))
			C.forceMove(A)
			continue
		C.forceMove(loc)
	A.forensic_data = forensic_data //carry crime data over.
	A.state = FRAME_WIRED
	A.update_icon()
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/keycard_auth/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_SILICON("Use", PROC_REF(keycard_auth_silicon_refuse)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_item/keycard_auth_swipe,
		/datum/interaction/machine_hand/ungated/keycard_auth_open_ui,
	)
	..()

/// Old attackby never called ..(): every item is swallowed by this, id cards checked for access.
/datum/interaction/machine_item/keycard_auth_swipe
	id = "keycard_auth_swipe"
	name = "Swipe"
	held_type = /obj/item
	effect = /obj/machinery/keycard_auth/proc/interaction_swipe

/obj/machinery/keycard_auth/proc/interaction_swipe(mob/user, obj/item/W, datum/interaction/interaction)
	if(stat & (NOPOWER|BROKEN))
		to_chat(user, "This device is not powered.")
		return TRUE

	if(istype(W,/obj/item/card/id))
		var/obj/item/card/id/ID = W
		if(ACCESS_KEYCARD_AUTH in ID.GetAccess())
			if(active == 1)
				//This is not the device that made the initial request. It is the device confirming the request.
				if(event_source())
					event_source().confirmed = 1
					event_source().event_confirmed_by_handle = om_handle(user)
			else if(screen == 2)
				event_triggered_by_handle = om_handle(user)
				broadcast_request(user) //This is the device making the initial event request. It needs to broadcast to other devices
	return TRUE

/obj/machinery/keycard_auth/power_change()
	..()
	if(stat &NOPOWER)
		icon_state = "auth_off"

// TGUI migration. attack_hand opens KeycardAuth.tsx;
// Topic event/reset actions move to tgui_act.
/datum/interaction/machine_hand/ungated/keycard_auth_open_ui
	id = "keycard_auth_open_ui"
	name = "Use"
	effect = /obj/machinery/keycard_auth/proc/interaction_open_ui_impl

/obj/machinery/keycard_auth/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || stat & (NOPOWER|BROKEN))
		to_chat(user, "This device is not powered.")
		return TRUE
	if(!user.IsAdvancedToolUser())
		return FALSE
	if(om_busy(src))
		to_chat(user, "This device is busy.")
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/keycard_auth/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "KeycardAuth", "Keycard Authentication")
		ui.open()

/obj/machinery/keycard_auth/tgui_data(mob/user)
	var/list/data = list()
	data["screen"] = screen
	data["event"] = event
	data["ert_admin_only"] = CONFIG_GET(flag/ert_admin_call_only) ? 1 : 0
	return data

/obj/machinery/keycard_auth/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(om_busy(src))
		to_chat(usr, "This device is busy.")
		return TRUE
	if(usr.stat || stat & (BROKEN|NOPOWER))
		to_chat(usr, "This device is without power.")
		return TRUE
	switch(action)
		if("triggerevent")
			event = params["event"]
			screen = 2
			add_fingerprint(usr)
			return TRUE
		if("reset")
			reset()
			add_fingerprint(usr)
			return TRUE

/obj/machinery/keycard_auth/proc/reset()
	active = 0
	event = ""
	screen = 1
	confirmed = 0
	event_source_handle = null
	icon_state = "auth_off"
	event_triggered_by_handle = null
	event_confirmed_by_handle = null

/obj/machinery/keycard_auth/proc/broadcast_request(mob/user)
	icon_state = "auth_on"
	for(var/obj/machinery/keycard_auth/KA in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(KA == src) continue
		KA.reset()
		KA.receive_request(src)

	om_after(src, confirm_delay, PROC_REF(request_window_closed), user)

/// The confirmation window is over: fire the event if someone confirmed it.
/obj/machinery/keycard_auth/proc/request_window_closed(mob/user)
	if(confirmed)
		confirmed = 0
		trigger_event(user)
		log_game("[key_name(event_triggered_by())] triggered and [key_name(event_confirmed_by())] confirmed event [event]")
		message_admins("[key_name(event_triggered_by())] triggered and [key_name(event_confirmed_by())] confirmed event [event]", 1)
	reset()

/obj/machinery/keycard_auth/proc/receive_request(obj/machinery/keycard_auth/source)
	if(stat & (BROKEN|NOPOWER))
		return
	event_source_handle = om_handle(source)
	// Busy for the confirmation window: a hold claims the device and closes the window when it ends.
	om_release_busy(src, "new request")
	active = 1
	icon_state = "auth_on"
	om_hold_busy(src, confirm_delay, PROC_REF(receive_window_closed))

/obj/machinery/keycard_auth/proc/receive_window_closed()
	event_source_handle = null
	icon_state = "auth_off"
	active = 0

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
	return SSticker.mode && SSticker.mode.ert_disabled

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

/// LC-refs: the event_triggered_by this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/keycard_auth/proc/event_triggered_by() as /mob
	return om_resolve(event_triggered_by_handle)

/// LC-refs: the event_confirmed_by this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/keycard_auth/proc/event_confirmed_by() as /mob
	return om_resolve(event_confirmed_by_handle)

/// LC-refs: the event_source this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/keycard_auth/proc/event_source() as /obj/machinery/keycard_auth
	return om_resolve(event_source_handle)
