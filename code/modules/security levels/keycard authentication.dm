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
	var/busy = 0 //Busy when waiting for authentication or an event request has been sent from this device.
	var/obj/machinery/keycard_auth/event_source
	var/mob/event_triggered_by
	var/mob/event_confirmed_by
	//1 = select event
	//2 = authenticate
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON

/obj/machinery/keycard_auth/attack_ai(mob/user)
	to_chat(user, span_warning("A firewall prevents you from interfacing with this device!"))
	return

/obj/machinery/keycard_auth/attackby(obj/item/W, mob/user)
	if(W.has_tool_quality(TOOL_SCREWDRIVER))
		to_chat(user, "You begin removing the faceplate from the [src]")
		playsound(src, W.usesound, 50, 1)
		if(do_after(user, 1 SECOND * W.toolspeed, target = src))
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
			for(var/obj/C in src)
				if(istype(C, /obj/item/circuitboard))
					C.forceMove(A)
					continue
				C.forceMove(loc)
			A.forensic_data = forensic_data //carry crime data over.
			A.state = FRAME_WIRED
			A.update_icon()
			qdel(src)
			return

	if(stat & (NOPOWER|BROKEN))
		to_chat(user, "This device is not powered.")
		return

	if(istype(W,/obj/item/card/id))
		var/obj/item/card/id/ID = W
		if(ACCESS_KEYCARD_AUTH in ID.GetAccess())
			if(active == 1)
				//This is not the device that made the initial request. It is the device confirming the request.
				if(event_source)
					event_source.confirmed = 1
					event_source.event_confirmed_by = user
			else if(screen == 2)
				event_triggered_by = user
				broadcast_request(user) //This is the device making the initial event request. It needs to broadcast to other devices

/obj/machinery/keycard_auth/power_change()
	..()
	if(stat &NOPOWER)
		icon_state = "auth_off"

// TGUI migration. attack_hand opens KeycardAuth.tsx;
// Topic event/reset actions move to tgui_act.
/obj/machinery/keycard_auth/attack_hand(mob/user as mob)
	if(user.stat || stat & (NOPOWER|BROKEN))
		to_chat(user, "This device is not powered.")
		return
	if(!user.IsAdvancedToolUser())
		return 0
	if(busy)
		to_chat(user, "This device is busy.")
		return
	tgui_interact(user)

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
	if(busy)
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
	event_source = null
	icon_state = "auth_off"
	event_triggered_by = null
	event_confirmed_by = null

/obj/machinery/keycard_auth/proc/broadcast_request(mob/user)
	icon_state = "auth_on"
	for(var/obj/machinery/keycard_auth/KA in GLOB.machines)
		if(KA == src) continue
		KA.reset()
		spawn()
			KA.receive_request(src)

	sleep(confirm_delay)
	if(confirmed)
		confirmed = 0
		trigger_event(user)
		log_game("[key_name(event_triggered_by)] triggered and [key_name(event_confirmed_by)] confirmed event [event]")
		message_admins("[key_name(event_triggered_by)] triggered and [key_name(event_confirmed_by)] confirmed event [event]", 1)
	reset()

/obj/machinery/keycard_auth/proc/receive_request(obj/machinery/keycard_auth/source)
	if(stat & (BROKEN|NOPOWER))
		return
	event_source = source
	busy = 1
	active = 1
	icon_state = "auth_on"

	sleep(confirm_delay)

	event_source = null
	icon_state = "auth_off"
	active = 0
	busy = 0

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
