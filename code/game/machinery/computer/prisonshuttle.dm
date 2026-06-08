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

/obj/machinery/computer/prison_shuttle/attack_ai(mob/user as mob)
	return src.attack_hand(user)

/obj/machinery/computer/prison_shuttle/attack_hand(mob/user as mob)
	if(!src.allowed(user) && (!hacked))
		to_chat(user, span_warning("Access Denied."))
		return
	if(prison_break)
		to_chat(user, span_warning("Unable to locate shuttle."))
		return
	if(..())
		return
	user.set_machine(src)
	post_signal("prison")
	tgui_interact(user)

/obj/machinery/computer/prison_shuttle/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PrisonShuttleConsole", "Prison Shuttle")
		ui.open()

/obj/machinery/computer/prison_shuttle/tgui_data(mob/user)
	var/list/data = list()
	data["moving"] = GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison
	data["at_station"] = !!GLOB.prison_shuttle_at_station
	data["time_left"] = GLOB.prison_shuttle_timeleft
	data["can_move"] = prison_can_move() && !prison_break
	return data

/obj/machinery/computer/prison_shuttle/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("send_to_dock")
			if(!prison_can_move())
				to_chat(usr, span_warning("The prison shuttle is unable to leave."))
				return TRUE
			if(!GLOB.prison_shuttle_at_station || GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison)
				return TRUE
			post_signal("prison")
			to_chat(usr, span_notice("The prison shuttle has been called and will arrive in [(PRISON_MOVETIME/10)] seconds."))
			GLOB.prison_shuttle_moving_to_prison = 1
			GLOB.prison_shuttle_time = world.timeofday + PRISON_MOVETIME
			spawn(0)
				prison_process()
			add_fingerprint(usr)
			return TRUE
		if("send_to_station")
			if(!prison_can_move())
				to_chat(usr, span_warning("The prison shuttle is unable to leave."))
				return TRUE
			if(GLOB.prison_shuttle_at_station || GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison)
				return TRUE
			post_signal("prison")
			to_chat(usr, span_notice("The prison shuttle has been called and will arrive in [(PRISON_MOVETIME/10)] seconds."))
			GLOB.prison_shuttle_moving_to_station = 1
			GLOB.prison_shuttle_time = world.timeofday + PRISON_MOVETIME
			spawn(0)
				prison_process()
			add_fingerprint(usr)
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
			spawn(0)
				prison_process()
			prison_break = 1
		if(1)
			prison_break = 0


/obj/machinery/computer/prison_shuttle/proc/post_signal(command)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(1311)
	if(!frequency) return
	var/datum/signal/status_signal = new
	status_signal.source = src
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command
	frequency.post_signal(src, status_signal)
	return


/obj/machinery/computer/prison_shuttle/proc/prison_process()
	while(GLOB.prison_shuttle_time - world.timeofday > 0)
		var/ticksleft = GLOB.prison_shuttle_time - world.timeofday

		if(ticksleft > 1e5)
			GLOB.prison_shuttle_time = world.timeofday + 10	// midnight rollover

		GLOB.prison_shuttle_timeleft = (ticksleft / 10)
		sleep(5)
	GLOB.prison_shuttle_moving_to_station = 0
	GLOB.prison_shuttle_moving_to_prison = 0

	switch(GLOB.prison_shuttle_at_station)

		if(0)
			GLOB.prison_shuttle_at_station = 1
			if (GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return

			if (!prison_can_move())
				to_chat(usr, span_warning("The prison shuttle is unable to leave."))
				return

			var/area/start_location = locate(/area/shuttle/prison/prison)
			var/area/end_location = locate(/area/shuttle/prison/station)

			var/list/dstturfs = list()
			var/throwy = world.maxy

			for(var/turf/T in end_location)
				dstturfs += T
				if(T.y < throwy)
					throwy = T.y
						// hey you, get out of the way!
			for(var/turf/T in dstturfs)
							// find the turf to move things to
				var/turf/D = locate(T.x, throwy - 1, 1)
							//var/turf/E = get_step(D, SOUTH)
				for(var/atom/movable/AM as mob|obj in T)
					AM.Move(D)
				if(istype(T, /turf/simulated))
					qdel(T)
			start_location.move_contents_to(end_location)

		if(1)
			GLOB.prison_shuttle_at_station = 0
			if (GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return

			if (!prison_can_move())
				to_chat(usr, span_warning("The prison shuttle is unable to leave."))
				return

			var/area/start_location = locate(/area/shuttle/prison/station)
			var/area/end_location = locate(/area/shuttle/prison/prison)

			var/list/dstturfs = list()
			var/throwy = world.maxy

			for(var/turf/T in end_location)
				dstturfs += T
				if(T.y < throwy)
					throwy = T.y

						// hey you, get out of the way!
			for(var/turf/T in dstturfs)
							// find the turf to move things to
				var/turf/D = locate(T.x, throwy - 1, 1)
							//var/turf/E = get_step(D, SOUTH)
				for(var/atom/movable/AM as mob|obj in T)
					AM.Move(D)
				if(istype(T, /turf/simulated))
					qdel(T)

			for(var/mob/living/carbon/bug in end_location) // If someone somehow is still in the shuttle's docking area...
				bug.gib()

			for(var/mob/living/simple_mob/pest in end_location) // And for the other kind of bug...
				pest.gib()

			start_location.move_contents_to(end_location)
	return

/obj/machinery/computer/prison_shuttle/emag_act(charges, mob/user)
	if(!hacked)
		hacked = 1
		to_chat(user, span_notice("You disable the lock."))
		return 1

#undef PRISON_MOVETIME
#undef PRISON_STATION_AREATYPE
#undef PRISON_DOCK_AREATYPE
