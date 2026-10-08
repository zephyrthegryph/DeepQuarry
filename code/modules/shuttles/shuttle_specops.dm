/obj/machinery/computer/shuttle_control/specops
	name = "special operations shuttle console"
	shuttle_tag = "Special Operations"
	req_access = list(ACCESS_CENT_SPECOPS)

CAPABILITIES(/obj/machinery/computer/shuttle_control/specops)
	op("specops_silicon_refuse", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(specops_silicon_refuse)))

/// Old attack_ai: refuse silicons.
/obj/machinery/computer/shuttle_control/specops/proc/specops_silicon_refuse(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_warning("Access Denied."))
	return TRUE

// Formerly /datum/shuttle/ferry/multidock/specops
/datum/shuttle/autodock/ferry/specops
	var/specops_return_delay = 6000		//After moving, the amount of time that must pass before the shuttle may move again
	var/specops_countdown_time = 600	//Length of the countdown when moving the shuttle

	var/obj/item/radio/intercom/announcer = null
	EXPIRY_DECLARE(reset_time) //the world.time at which the shuttle will be ready to move again.
	var/launch_prep = 0
	var/cancel_countdown = 0
	category = /datum/shuttle/autodock/ferry/specops

CAPABILITIES(/datum/shuttle/autodock/ferry/specops)
	owns_one(nameof(announcer), /obj/item/radio/intercom)

/datum/shuttle/autodock/ferry/specops/New()
	..()
	rel_set(src, nameof(announcer), new /obj/item/radio/intercom(null)) //We need a fake AI to announce some stuff below. Otherwise it will be wonky.
	announcer.config(list(CHANNEL_RESPONSE_TEAM = 0))

/datum/shuttle/autodock/ferry/specops/proc/radio_announce(message)
	if(announcer)
		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)


/datum/shuttle/autodock/ferry/specops/launch(user)
	if(countdown_done)
		launch_now(user)
		return ..(user)
	if (!can_launch())
		return

	if (istype(user, /obj/machinery/computer))
		var/obj/machinery/computer/C = user

		if(ELAPSED(src, reset_time, CLOCK_WORLD) <= 0)
			C.visible_message(span_notice("[using_map.boss_name] will not allow the Special Operations shuttle to launch yet."))
			if (((world.time - reset_time)/10) > 60)
				C.visible_message(span_notice("[-((world.time - reset_time)/10)/60] minutes remain!"))
			else
				C.visible_message(span_notice("[-(world.time - reset_time)/10] seconds remain!"))
			return

		C.visible_message(span_notice("The Special Operations shuttle will depart in [(specops_countdown_time/10)] seconds."))

	if (location)	//returning
		radio_announce("THE SPECIAL OPERATIONS SHUTTLE IS PREPARING TO RETURN")
	else
		radio_announce("THE SPECIAL OPERATIONS SHUTTLE IS PREPARING FOR LAUNCH")

	start_launch_countdown(user)
	return

/// The launch, once the countdown (start_launch_countdown()) has run out: launch() again, past it.
/datum/shuttle/autodock/ferry/specops/proc/launch_after_countdown(user)
	countdown_done = TRUE
	launch(user)
	countdown_done = FALSE

/datum/shuttle/autodock/ferry/specops/var/countdown_done = FALSE

/datum/shuttle/autodock/ferry/specops/proc/launch_now(user)
	if (location)
		var/obj/machinery/light/small/readylight/light = locate_within(shuttle_area, /obj/machinery/light/small/readylight)
		if(light) light.set_state(0)

	//launch
	radio_announce("ALERT: INITIATING LAUNCH SEQUENCE")

/datum/shuttle/autodock/ferry/specops/perform_shuttle_move()
	..()

	after(src, 2 SECONDS, PROC_REF(announce_arrival))

/datum/shuttle/autodock/ferry/specops/cancel_launch()
	if (!can_cancel())
		return

	cancel_countdown = 1
	radio_announce("ALERT: LAUNCH SEQUENCE ABORTED")
	if (istype(in_use, /obj/machinery/computer))
		var/obj/machinery/computer/C = in_use
		C.visible_message(span_warning("Launch sequence aborted."))
	..()



/datum/shuttle/autodock/ferry/specops/can_launch()
	if(launch_prep)
		return 0
	return ..()

//should be fine to allow forcing. process_state only becomes WAIT_LAUNCH after the countdown is over.
///datum/shuttle/autodock/ferry/specops/can_force()

/datum/shuttle/autodock/ferry/specops/can_cancel()
	if(launch_prep)
		return 1
	return ..()

/// The countdown: announcements at the marked seconds, then the launch. A cancel stops it.
/datum/shuttle/autodock/ferry/specops/proc/start_launch_countdown(user)
	var/static/list/message_tracker = list(0,1,2,3,5,10,30,45)//The seconds left that are announced.
	cancel_countdown = 0
	launch_prep = 1
	for(var/seconds in message_tracker)
		var/delay = specops_countdown_time - seconds * 10
		if(delay >= 0 && seconds * 10 < specops_countdown_time)
			after(src, delay, PROC_REF(announce_countdown), with = list(seconds))
	after(src, specops_countdown_time, PROC_REF(countdown_ended), with = list(user))

/datum/shuttle/autodock/ferry/specops/proc/announce_countdown(seconds)
	if(cancel_countdown || !launch_prep)
		return
	radio_announce("ALERT: [seconds] SECOND[(seconds!=1)?"S":""] REMAIN")

/datum/shuttle/autodock/ferry/specops/proc/countdown_ended(user)
	if(!launch_prep)
		return
	launch_prep = 0
	if(cancel_countdown)
		return
	launch_after_countdown(user)


/// The launchpad's assault bays, "ASSAULT0" to "ASSAULT3": 1 to 4 seconds apart.
/proc/marauder_bay_delay(id)
	var/static/list/delays = list("ASSAULT0" = 1 SECOND, "ASSAULT1" = 2 SECONDS, "ASSAULT2" = 3 SECONDS, "ASSAULT3" = 4 SECONDS)
	return delays[id]

/// The Marauder launchpad: bay doors open, portals, mass drivers, then the doors close.
/proc/launch_mauraders()
	var/area/centcom/specops/special_ops = locate()//Where is the specops area located?
	for(var/obj/machinery/door/blast/M in area_contents_of_type(special_ops, /obj/machinery/door/blast))
		var/delay = marauder_bay_delay(M.id)
		if(delay)
			after(M, delay, TYPE_PROC_REF(/obj/machinery/door, open))
	after(null, 1 SECOND, GLOBAL_PROC_REF(mauraders_portals), with = list(special_ops))

/proc/mauraders_portals(area/centcom/specops/special_ops)
	var/spawn_marauder[] = new()
	for(var/obj/effect/landmark/L in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(L.name == "Marauder Entry")
			spawn_marauder.Add(L)
	for(var/obj/effect/landmark/L in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(L.name == "Marauder Exit")
			var/obj/effect/portal/P = new(L.loc)
			P.invisibility = INVISIBILITY_ABSTRACT //So it is not seen by anyone.
			P.failchance = 0//So it has no fail chance when teleporting.
			rel_set(P, nameof(P.target), pick(spawn_marauder))//Where the marauder will arrive.
			spawn_marauder.Remove(P.target_ref())
	after(null, 1 SECOND, GLOBAL_PROC_REF(mauraders_drive), with = list(special_ops))

/proc/mauraders_drive(area/centcom/specops/special_ops)
	for(var/obj/machinery/mass_driver/M in special_ops)
		var/delay = marauder_bay_delay(M.id)
		if(delay)
			after(M, delay, TYPE_PROC_REF(/obj/machinery/mass_driver, drive))
	after(null, 5 SECONDS, GLOBAL_PROC_REF(mauraders_close), with = list(special_ops)) //Doors remain open for 5 seconds.

/proc/mauraders_close(area/centcom/specops/special_ops)
	for(var/obj/machinery/door/blast/M in area_contents_of_type(special_ops, /obj/machinery/door/blast))
		if(marauder_bay_delay(M.id)) //Doors close at the same time.
			M.close()
	special_ops?.readyreset()//Reset firealarm after the team launched.

/obj/machinery/light/small/readylight
	brightness_range = 5
	brightness_power = 1
	brightness_color = "#DA0205"
	var/state = 0

/obj/machinery/light/small/readylight/proc/set_state(new_state)
	. = FALSE
	if(state != new_state)
		state = new_state
		tracked_bridged_changed(src, "state")
		. = TRUE
	if(state)
		brightness_color = "00FF00"
	else
		brightness_color = initial(brightness_color)
	refresh_light()

/datum/shuttle/autodock/ferry/specops/proc/announce_arrival()
	if (!location)	//just arrived home
		for(var/turf/T in get_area_turfs(shuttle_area))
			var/mob/M = locate_within(T, /mob)
			to_chat(M, span_danger("You have arrived at [using_map.boss_name]. Operation has ended!"))
	else	//just left for the station
		launch_mauraders()
		for(var/turf/T in get_area_turfs(shuttle_area))
			var/mob/M = locate_within(T, /mob)
			to_chat(M, span_danger("You have arrived at [station_name()]. Commence operation!"))

			var/obj/machinery/light/small/readylight/light = locate_within(T, /obj/machinery/light/small/readylight)
			if(light) light.set_state(1)


SETTER(/obj/machinery/light/small/readylight, state)
