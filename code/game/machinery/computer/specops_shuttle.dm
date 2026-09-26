//Config stuff
#define SPECOPS_MOVETIME 600	//Time to station is milliseconds. 60 seconds, enough time for everyone to be on the shuttle before it leaves.
#define SPECOPS_STATION_AREATYPE "/area/shuttle/specops/station" //Type of the spec ops shuttle area for station
#define SPECOPS_DOCK_AREATYPE "/area/shuttle/specops/centcom"	//Type of the spec ops shuttle area for dock
#define SPECOPS_RETURN_DELAY 600 //Time between the shuttle is capable of moving.

GLOBAL_VAR_INIT(specops_shuttle_moving_to_station, 0)
GLOBAL_VAR_INIT(specops_shuttle_moving_to_centcom, 0)
GLOBAL_VAR_INIT(specops_shuttle_at_station, 0)
GLOBAL_VAR_INIT(specops_shuttle_can_send, 1)
GLOBAL_VAR_INIT(specops_shuttle_time, 0)
GLOBAL_VAR_INIT(specops_shuttle_timeleft, 0)

/obj/machinery/computer/specops_shuttle
	name = "special operations shuttle control console"
	icon_keyboard = "security_key"
	icon_screen = "syndishuttle"
	light_color = "#00ffff"
	req_access = list(ACCESS_CENT_SPECOPS)
//	req_access = list(ACCESS_CENT_SPECOPS)
	var/temp = null
	var/hacked = 0
	var/allowedtocall = 0
	var/specops_shuttle_timereset = 0

/proc/specops_return()
	var/obj/item/radio/intercom/announcer = new /obj/item/radio/intercom(null)//We need a fake AI to announce some stuff below. Otherwise it will be wonky.
	announcer.config(list(CHANNEL_RESPONSE_TEAM = 0))

	var/message_tracker[] = list(0,1,2,3,5,10,30,45)//Create a a list with potential time values.
	var/message = "\"THE SPECIAL OPERATIONS SHUTTLE IS PREPARING TO RETURN\""//Initial message shown.
	if(announcer)
		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)

	specops_countdown_tick(announcer, message_tracker, /proc/specops_return_arrive)

/// The shuttle has arrived: the rest of specops_return() once the countdown ends.
/proc/specops_return_arrive(obj/item/radio/intercom/announcer)

	GLOB.specops_shuttle_moving_to_station = 0
	GLOB.specops_shuttle_moving_to_centcom = 0

	GLOB.specops_shuttle_at_station = 1

	var/area/start_location = locate(/area/shuttle/specops/station)
	var/area/end_location = locate(/area/shuttle/specops/centcom)

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

	for(var/turf/T in get_area_turfs(end_location) )
		var/mob/M = locate(/mob) in T
		to_chat(M, span_notice("You have arrived at [using_map.boss_name]. Operation has ended!"))

	GLOB.specops_shuttle_at_station = 0

	for(var/obj/machinery/computer/specops_shuttle/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		S.specops_shuttle_timereset = world.time + SPECOPS_RETURN_DELAY

	qdel(announcer)

/proc/specops_process()
	var/obj/item/radio/intercom/announcer = new /obj/item/radio/intercom(null)//We need a fake AI to announce some stuff below. Otherwise it will be wonky.
	announcer.config(list(CHANNEL_RESPONSE_TEAM = 0))

	var/message_tracker[] = list(0,1,2,3,5,10,30,45)//Create a a list with potential time values.
	var/message = "\"THE SPECIAL OPERATIONS SHUTTLE IS PREPARING FOR LAUNCH\""//Initial message shown.
	if(announcer)
		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)
//		message = "ARMORED SQUAD TAKE YOUR POSITION ON GRAVITY LAUNCH PAD"
//		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)

	specops_countdown_tick(announcer, message_tracker, /proc/specops_process_arrive)

/// The shuttle has arrived: the rest of specops_process() once the countdown ends.
/proc/specops_process_arrive(obj/item/radio/intercom/announcer)
	var/area/centcom/specops/special_ops = locate()//Where is the specops area located?

	GLOB.specops_shuttle_moving_to_station = 0
	GLOB.specops_shuttle_moving_to_centcom = 0

	GLOB.specops_shuttle_at_station = 1
	if (GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom) return

	if (!specops_can_move())
		to_chat(usr, span_warning("The Special Operations shuttle is unable to leave."))
		return

	//Begin Marauder launchpad.
	specops_marauder_launchpad(special_ops)
	//End Marauder launchpad.

	var/area/start_location = locate(/area/shuttle/specops/centcom)
	var/area/end_location = locate(/area/shuttle/specops/station)

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

	for(var/turf/T in get_area_turfs(end_location) )
		var/mob/M = locate(/mob) in T
		to_chat(M, span_notice("You have arrived to [station_name()]. Commence operation!"))

	for(var/obj/machinery/computer/specops_shuttle/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		S.specops_shuttle_timereset = world.time + SPECOPS_RETURN_DELAY

	qdel(announcer)

/proc/specops_can_move()
	if(GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom)
		return 0
	for(var/obj/machinery/computer/specops_shuttle/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(world.timeofday <= S.specops_shuttle_timereset)
			return 0
	return 1

/obj/machinery/computer/specops_shuttle/emag_act(remaining_charges, mob/user)
	to_chat(user, span_notice("The electronic systems in this console are far too advanced for your primitive hacking peripherals."))

// structured TGUI Specops Shuttle (see
// code/modules/admin/specops_shuttle_panel.dm).

/obj/machinery/computer/specops_shuttle/Topic(href, href_list)
	if(..())
		return 1

	if ((usr.contents.Find(src) || (in_range(src, usr) && istype(loc, /turf))) || (istype(usr, /mob/living/silicon)))
		usr.set_machine(src)

	if (href_list["sendtodock"])
		if(!GLOB.specops_shuttle_at_station|| GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom) return

		if (!specops_can_move())
			to_chat(usr, span_notice("[using_map.boss_name] will not allow the Special Operations shuttle to return yet."))
			if(world.timeofday <= specops_shuttle_timereset)
				if (((world.timeofday - specops_shuttle_timereset)/10) > 60)
					to_chat(usr, span_notice("[-((world.timeofday - specops_shuttle_timereset)/10)/60] minutes remain!"))
				to_chat(usr, span_notice("[-(world.timeofday - specops_shuttle_timereset)/10] seconds remain!"))
			return

		to_chat(usr, span_notice("The Special Operations shuttle will arrive at [using_map.boss_name] in [(SPECOPS_MOVETIME/10)] seconds."))

		temp += "Shuttle departing.<BR><BR><A href='byond://?src=\ref[src];mainmenu=1'>OK</A>"
		updateUsrDialog(usr)

		GLOB.specops_shuttle_moving_to_centcom = 1
		GLOB.specops_shuttle_time = world.timeofday + SPECOPS_MOVETIME
		specops_return()

	else if (href_list["sendtostation"])
		if(GLOB.specops_shuttle_at_station || GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom) return

		if (!specops_can_move())
			to_chat(usr, span_warning("The Special Operations shuttle is unable to leave."))
			return

		to_chat(usr, span_notice("The Special Operations shuttle will arrive on [station_name()] in [(SPECOPS_MOVETIME/10)] seconds."))

		temp += "Shuttle departing.<BR><BR><A href='byond://?src=\ref[src];mainmenu=1'>OK</A>"
		updateUsrDialog(usr)

		var/area/centcom/specops/special_ops = locate()
		if(special_ops)
			special_ops.readyalert()//Trigger alarm for the spec ops area.
		GLOB.specops_shuttle_moving_to_station = 1

		GLOB.specops_shuttle_time = world.timeofday + SPECOPS_MOVETIME
		specops_process()

	else if (href_list["mainmenu"])
		temp = null

	add_fingerprint(usr)
	updateUsrDialog(usr)
	return

#undef SPECOPS_MOVETIME
#undef SPECOPS_STATION_AREATYPE
#undef SPECOPS_DOCK_AREATYPE
#undef SPECOPS_RETURN_DELAY

/// Assault pod launch order: door and driver ASSAULTn goes (n+1) seconds into its phase.
GLOBAL_LIST_INIT(specops_assault_stagger, list("ASSAULT0" = 1 SECOND, "ASSAULT1" = 2 SECONDS, "ASSAULT2" = 3 SECONDS, "ASSAULT3" = 4 SECONDS))

/// The Marauder launchpad, on the special ops area's clock: doors open one by one, the exit
/// portals appear, the mass drivers fire one by one, and five seconds later the doors close.
/proc/specops_marauder_launchpad(area/special_ops)
	var/list/stagger = GLOB.specops_assault_stagger
	for(var/obj/machinery/door/blast/M in special_ops)
		if(M.id && stagger[M.id])
			om_after(M, stagger[M.id], TYPE_PROC_REF(/obj/machinery/door, open))
	om_after(special_ops, 1 SECOND, /proc/specops_marauder_portals)
	for(var/obj/machinery/mass_driver/M in special_ops)
		if(M.id && stagger[M.id])
			om_after(M, 2 SECONDS + stagger[M.id], TYPE_PROC_REF(/obj/machinery/mass_driver, drive))
	om_after(special_ops, 7 SECONDS, /proc/specops_marauder_launched, special_ops) //Doors remain open for 5 seconds.

/proc/specops_marauder_portals()
	var/spawn_marauder[] = new()
	for(var/obj/effect/landmark/L in GLOB.landmarks_list)
		if(L.name == "Marauder Entry")
			spawn_marauder.Add(L)
	for(var/obj/effect/landmark/L in GLOB.landmarks_list)
		if(L.name == "Marauder Exit")
			var/obj/effect/portal/P = new(L.loc)
			P.invisibility = INVISIBILITY_ABSTRACT//So it is not seen by anyone.
			P.failchance = 0//So it has no fail chance when teleporting.
			P.target = pick(spawn_marauder)//Where the marauder will arrive.
			spawn_marauder.Remove(P.target)

/proc/specops_marauder_launched(area/centcom/specops/special_ops)
	for(var/obj/machinery/door/blast/M in special_ops)
		if(M.id && GLOB.specops_assault_stagger[M.id]) //Doors close at the same time.
			M.close()
	special_ops.readyreset()//Reset firealarm after the team launched.

/// The special ops shuttle's countdown, every half second on the global owner (a round
/// event: no entity owns the shuttle): announces the remaining time at the marks in
/// `message_tracker`, then calls `on_arrival` with the announcer.
/proc/specops_countdown_tick(obj/item/radio/intercom/announcer, list/message_tracker, on_arrival)
	if(GLOB.specops_shuttle_time - world.timeofday <= 0)
		call(on_arrival)(announcer)
		return
	var/ticksleft = GLOB.specops_shuttle_time - world.timeofday

	if(ticksleft > 1e5)
		GLOB.specops_shuttle_time = world.timeofday + 10	// midnight rollover
	GLOB.specops_shuttle_timeleft = (ticksleft / 10)

	//All this does is announce the time before launch.
	if(announcer)
		var/rounded_time_left = round(GLOB.specops_shuttle_timeleft)//Round time so that it will report only once, not in fractions.
		if(rounded_time_left in message_tracker)//If that time is in the list for message announce.
			var/message = "\"ALERT: [rounded_time_left] SECOND[(rounded_time_left!=1)?"S":""] REMAIN\""
			if(rounded_time_left==0)
				message = "\"ALERT: TAKEOFF\""
			announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)
			message_tracker -= rounded_time_left//Remove the number from the list so it won't be called again next cycle.

	om_after(null, 5, /proc/specops_countdown_tick, announcer, message_tracker, on_arrival)
