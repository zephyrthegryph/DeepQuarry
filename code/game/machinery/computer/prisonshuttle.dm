//Config stuff
#define PRISON_MOVETIME 150	//Time to station is milliseconds.
#define PRISON_STATION_AREATYPE "/area/shuttle/prison/station" //Type of the prison shuttle area for station
#define PRISON_DOCK_AREATYPE "/area/shuttle/prison/prison"	//Type of the prison shuttle area for dock

GLOBAL_VAR_INIT(prison_shuttle_moving_to_station, 0)
GLOBAL_VAR_INIT(prison_shuttle_moving_to_prison, 0)
GLOBAL_VAR_INIT(prison_shuttle_at_station, 0)
GLOBAL_VAR_INIT(prison_shuttle_can_send, 1)
GLOBAL_VAR_INIT(prison_shuttle_time, 0)
GLOBAL_VAR_INIT(prison_shuttle_timeleft, 0)

/obj/machinery/computer/prison_shuttle
	name = "prison shuttle control console"
	desc = "Used to move the prison shuttle to and from its destination."
	icon_keyboard = "security_key"
	icon_screen = "syndishuttle"
	light_color = "#00ffff"
	req_access = list(ACCESS_SECURITY)
	circuit = /obj/item/circuitboard/prison_shuttle
	var/hacked = 0
	var/allowedtocall = 0
	var/prison_break = 0
	/// The shuttle this console sent is in flight.
	var/in_flight = FALSE

/// The shuttle this console sent is in flight: prison_process() counts it down every half second.
TRACKED_BRIDGED(/obj/machinery/computer/prison_shuttle, in_flight, CHANGE_MACHINE_SETTINGS)

// TGUI migration. Replaces the browse() + Topic dispatch
// UI with PrisonShuttleConsole.tsx. Drops the `temp` "Shuttle sent"
// notification state; the chat notice already covers that flow.

/**
 * Old attack_hand: access/hacked and prison_break checks ran BEFORE the `..()` gate call, so
 * they used to fire even when the console itself was unpowered/broken. The machinery hand gate
 * now always runs first (see machine_hand) and those checks are can_open_console(), after it.
 */
/// Requirement: TRUE, or why the console can't be used.
/obj/machinery/computer/prison_shuttle/proc/can_open_console(mob/user, atom/target, obj/item/held)
	if(!allowed(user) && !hacked) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return "access denied"
	if(prison_break) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return "unable to locate shuttle"
	return TRUE

/// Requirement (was REQ_* can_open_console): the legacy check answers TRUE to pass.
/obj/machinery/computer/prison_shuttle/proc/can_open_console_holds(datum/act/op/A)
	var/answer = can_open_console(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_open_console_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/prison_shuttle/proc/can_open_console_refusal(datum/act/op/A)
	var/answer = can_open_console(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/computer/prison_shuttle/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	record_window_open(A)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/prison_shuttle)
	interface("PrisonShuttleConsole", title = "Prison Shuttle")
	extend("ui_open", needs(req(PROC_REF(can_open_console_holds), because = PROC_REF(can_open_console_refusal))), then(PROC_REF(record_window_open)))
	op("send_to_dock", ui_act("send_to_dock"), then(PROC_REF(ui_act_send_to_dock)))
	op("send_to_station", ui_act("send_to_station"), then(PROC_REF(ui_act_send_to_station)))
	every(0.5 SECONDS, then(PROC_REF(prison_process)), when = nameof(in_flight))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(can_open_console_holds), because = PROC_REF(can_open_console_refusal))), then(PROC_REF(interaction_open_ui_impl)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	extend("emag.use", binds(menu()), needs(req_adjacent(), req_capable()), label("Emag"))

/obj/machinery/computer/prison_shuttle/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["moving"] = GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison
	data["at_station"] = !!GLOB.prison_shuttle_at_station
	data["time_left"] = GLOB.prison_shuttle_timeleft
	data["can_move"] = prison_can_move() && !prison_break
	return data

/obj/machinery/computer/prison_shuttle/proc/ui_act_send_to_dock(datum/act/op/A)
	var/mob/user = A.actor
	if(!prison_can_move())
		to_chat(user, span_warning("The prison shuttle is unable to leave."))
		return TRUE
	if(!GLOB.prison_shuttle_at_station || GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison)
		return TRUE
	post_signal("prison")
	to_chat(user, span_notice("The prison shuttle has been called and will arrive in [(PRISON_MOVETIME/10)] seconds."))
	GLOB.prison_shuttle_moving_to_prison = 1
	GLOB.prison_shuttle_time = world.timeofday + PRISON_MOVETIME
	set_in_flight(TRUE)
	add_fingerprint(user)
	return TRUE

/obj/machinery/computer/prison_shuttle/proc/ui_act_send_to_station(datum/act/op/A)
	var/mob/user = A.actor
	if(!prison_can_move())
		to_chat(user, span_warning("The prison shuttle is unable to leave."))
		return TRUE
	if(GLOB.prison_shuttle_at_station || GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison)
		return TRUE
	post_signal("prison")
	to_chat(user, span_notice("The prison shuttle has been called and will arrive in [(PRISON_MOVETIME/10)] seconds."))
	GLOB.prison_shuttle_moving_to_station = 1
	GLOB.prison_shuttle_time = world.timeofday + PRISON_MOVETIME
	set_in_flight(TRUE)
	add_fingerprint(user)
	return TRUE


/obj/machinery/computer/prison_shuttle/proc/prison_can_move()
	if(GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return 0
	else return 1


/obj/machinery/computer/prison_shuttle/proc/prison_break()
	switch(prison_break)
		if (0)
			if(!GLOB.prison_shuttle_at_station || GLOB.prison_shuttle_moving_to_prison) return

			GLOB.prison_shuttle_moving_to_prison = 1
			GLOB.prison_shuttle_at_station = GLOB.prison_shuttle_at_station

			if (!GLOB.prison_shuttle_moving_to_prison || !GLOB.prison_shuttle_moving_to_station)
				GLOB.prison_shuttle_time = world.timeofday + PRISON_MOVETIME
			set_in_flight(TRUE)
			prison_break = 1
		if(1)
			prison_break = 0


/obj/machinery/computer/prison_shuttle/proc/post_signal(command)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(1311)
	if(!frequency) return
	var/datum/signal/status_signal = new
	rel_set(status_signal, nameof(status_signal.source), src)
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command
	frequency.post_signal(src, status_signal)
	return


/// The prison shuttle in flight: counts down every half second, then arrives.
/obj/machinery/computer/prison_shuttle/proc/prison_process(datum/act/timer/A)
	if(GLOB.prison_shuttle_time - world.timeofday > 0)
		var/ticksleft = GLOB.prison_shuttle_time - world.timeofday

		if(ticksleft > 1e5)
			GLOB.prison_shuttle_time = world.timeofday + 10	// midnight rollover
		GLOB.prison_shuttle_timeleft = (ticksleft / 10)
		return
	set_in_flight(FALSE)
	GLOB.prison_shuttle_moving_to_station = 0
	GLOB.prison_shuttle_moving_to_prison = 0

	switch(GLOB.prison_shuttle_at_station)

		if(0)
			GLOB.prison_shuttle_at_station = 1
			if (GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return

			var/area/start_location = locate(/area/shuttle/prison/prison)
			var/area/end_location = locate(/area/shuttle/prison/station)

			var/list/dstturfs = list()
			var/throwy = world.maxy

			for(var/turf/T in area_contents_of_type(end_location, /turf))
				dstturfs += T
				if(T.y < throwy)
					throwy = T.y
						// hey you, get out of the way!
			for(var/turf/T in dstturfs)
							// find the turf to move things to
				var/turf/D = locate(T.x, throwy - 1, 1)
				for(var/atom/movable/AM as mob|obj in contents_of(T))
					AM.Move(D)
				if(istype(T, /turf/simulated))
					spent(T)
			start_location.move_contents_to(end_location)

		if(1)
			GLOB.prison_shuttle_at_station = 0
			if (GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return

			var/area/start_location = locate(/area/shuttle/prison/station)
			var/area/end_location = locate(/area/shuttle/prison/prison)

			var/list/dstturfs = list()
			var/throwy = world.maxy

			for(var/turf/T in area_contents_of_type(end_location, /turf))
				dstturfs += T
				if(T.y < throwy)
					throwy = T.y

						// hey you, get out of the way!
			for(var/turf/T in dstturfs)
							// find the turf to move things to
				var/turf/D = locate(T.x, throwy - 1, 1)
				for(var/atom/movable/AM as mob|obj in contents_of(T))
					AM.Move(D)
				if(istype(T, /turf/simulated))
					spent(T)

			for(var/mob/living/carbon/bug in area_contents_of_type(end_location, /mob/living/carbon)) // If someone somehow is still in the shuttle's docking area...
				bug.gib()

			for(var/mob/living/simple_mob/pest in area_contents_of_type(end_location, /mob/living/simple_mob)) // And for the other kind of bug...
				pest.gib()

			start_location.move_contents_to(end_location)
	return

/obj/machinery/computer/prison_shuttle/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!hacked)
		hacked = 1
		to_chat(user, span_notice("You disable the lock."))
		return OP_OK
	return OP_DECLINE

#undef PRISON_MOVETIME
#undef PRISON_STATION_AREATYPE
#undef PRISON_DOCK_AREATYPE

/obj/machinery/computer/prison_shuttle/proc/record_window_open(datum/act/op/A)
	A.actor.set_machine(src)
	post_signal("prison")
	return OP_OK
