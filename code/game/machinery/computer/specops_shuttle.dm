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
	var/temp = null
	var/hacked = 0
	var/allowedtocall = 0
	EXPIRY_DECLARE(specops_shuttle_timereset)

/proc/specops_release_announcer(obj/item/radio/intercom/announcer)
	if(!SSshuttles.release_specops_announcer(announcer))
		spent(announcer)

/proc/specops_return(mob/user)
	var/obj/item/radio/intercom/announcer = SSshuttles.hold_specops_announcer(new /obj/item/radio/intercom(null)) // The countdown radio speaks as A.L.I.C.E.
	announcer.config(list(CHANNEL_RESPONSE_TEAM = 0))

	var/message_tracker[] = list(0,1,2,3,5,10,30,45)//Create a a list with potential time values.
	var/message = "\"THE SPECIAL OPERATIONS SHUTTLE IS PREPARING TO RETURN\""//Initial message shown.
	if(announcer)
		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)

	specops_countdown(message_tracker, announcer, GLOBAL_PROC_REF(specops_return_arrive), user)

/// Arrival half of the countdown (runs when it hits zero).
/proc/specops_return_arrive(obj/item/radio/intercom/announcer, mob/user)
	GLOB.specops_shuttle_moving_to_station = 0
	GLOB.specops_shuttle_moving_to_centcom = 0

	GLOB.specops_shuttle_at_station = 1

	var/area/start_location = locate(/area/shuttle/specops/station)
	var/area/end_location = locate(/area/shuttle/specops/centcom)

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
			spent(T, user)

	for(var/mob/living/carbon/bug in area_contents_of_type(end_location, /mob/living/carbon)) // If someone somehow is still in the shuttle's docking area...
		bug.gib()

	for(var/mob/living/simple_mob/pest in area_contents_of_type(end_location, /mob/living/simple_mob)) // And for the other kind of bug...
		pest.gib()

	start_location.move_contents_to(end_location)

	for(var/turf/T in get_area_turfs(end_location) )
		var/mob/M = locate_within(T, /mob)
		to_chat(M, span_notice("You have arrived at [using_map.boss_name]. Operation has ended!"))

	GLOB.specops_shuttle_at_station = 0

	for(var/obj/machinery/computer/specops_shuttle/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		EXPIRY_SET(S, specops_shuttle_timereset, SPECOPS_RETURN_DELAY, CLOCK_WORLD)

	specops_release_announcer(announcer)

/proc/specops_process(mob/user)
	var/obj/item/radio/intercom/announcer = SSshuttles.hold_specops_announcer(new /obj/item/radio/intercom(null)) // The countdown radio speaks as A.L.I.C.E.
	announcer.config(list(CHANNEL_RESPONSE_TEAM = 0))

	var/message_tracker[] = list(0,1,2,3,5,10,30,45)//Create a a list with potential time values.
	var/message = "\"THE SPECIAL OPERATIONS SHUTTLE IS PREPARING FOR LAUNCH\""//Initial message shown.
	if(announcer)
		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)
//		message = "ARMORED SQUAD TAKE YOUR POSITION ON GRAVITY LAUNCH PAD"
//		announcer.autosay(message, "A.L.I.C.E.", CHANNEL_RESPONSE_TEAM)

	specops_countdown(message_tracker, announcer, GLOBAL_PROC_REF(specops_launch), user)

/// Arrival half of the countdown (runs when it hits zero).
/proc/specops_launch(obj/item/radio/intercom/announcer, mob/user)
	GLOB.specops_shuttle_moving_to_station = 0
	GLOB.specops_shuttle_moving_to_centcom = 0

	GLOB.specops_shuttle_at_station = 1
	if (GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom) return

	if (!specops_can_move())
		to_chat(user, span_warning("The Special Operations shuttle is unable to leave."))
		specops_release_announcer(announcer)
		return

	launch_mauraders() // the Marauder launchpad (shuttle_specops.dm)

	var/area/start_location = locate(/area/shuttle/specops/centcom)
	var/area/end_location = locate(/area/shuttle/specops/station)

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
			spent(T, user)

	start_location.move_contents_to(end_location)

	for(var/turf/T in get_area_turfs(end_location) )
		var/mob/M = locate_within(T, /mob)
		to_chat(M, span_notice("You have arrived to [station_name()]. Commence operation!"))

	for(var/obj/machinery/computer/specops_shuttle/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		EXPIRY_SET(S, specops_shuttle_timereset, SPECOPS_RETURN_DELAY, CLOCK_WORLD)

	specops_release_announcer(announcer)

/// Counts the shuttle timer down in half-second steps, announcing on the way,
/// then calls `done_proc(announcer, user)`.
/proc/specops_countdown(list/message_tracker, obj/item/radio/intercom/announcer, done_proc, mob/user)
	var/ticksleft = GLOB.specops_shuttle_time - world.timeofday
	if(ticksleft <= 0)
		call(done_proc)(announcer, user)
		return
	if(ticksleft > 1e5)
		GLOB.specops_shuttle_time = world.timeofday + 1 SECOND	// midnight rollover
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
	after(null, 0.5 SECONDS, GLOBAL_PROC_REF(specops_countdown), with = list(message_tracker, announcer, done_proc, user))

/proc/specops_can_move()
	if(GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom)
		return 0
	for(var/obj/machinery/computer/specops_shuttle/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(world.timeofday <= S.specops_shuttle_timereset)
			return 0
	return 1

/obj/machinery/computer/specops_shuttle/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("The electronic systems in this console are far too advanced for your primitive hacking peripherals."))
	return OP_DECLINE

// structured TGUI Specops Shuttle (see
// code/modules/admin/specops_shuttle_panel.dm).

/obj/machinery/computer/specops_shuttle/proc/specops_send_to_dock(mob/user)
	if(!GLOB.specops_shuttle_at_station|| GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom)
		return

	if (!specops_can_move())
		to_chat(user, span_notice("[using_map.boss_name] will not allow the Special Operations shuttle to return yet."))
		if(world.timeofday <= specops_shuttle_timereset)
			if (((world.timeofday - specops_shuttle_timereset)/10) > 60)
				to_chat(user, span_notice("[-((world.timeofday - specops_shuttle_timereset)/10)/60] minutes remain!"))
			to_chat(user, span_notice("[-(world.timeofday - specops_shuttle_timereset)/10] seconds remain!"))
		return

	to_chat(user, span_notice("The Special Operations shuttle will arrive at [using_map.boss_name] in [(SPECOPS_MOVETIME/10)] seconds."))

	temp += "Shuttle departing.<BR><BR>"
	add_fingerprint(user)
	updateUsrDialog(user)

	GLOB.specops_shuttle_moving_to_centcom = 1
	GLOB.specops_shuttle_time = world.timeofday + SPECOPS_MOVETIME
	specops_return(user)

/obj/machinery/computer/specops_shuttle/proc/specops_send_to_station(mob/user)
	if(GLOB.specops_shuttle_at_station || GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom)
		return

	if (!specops_can_move())
		to_chat(user, span_warning("The Special Operations shuttle is unable to leave."))
		return

	to_chat(user, span_notice("The Special Operations shuttle will arrive on [station_name()] in [(SPECOPS_MOVETIME/10)] seconds."))

	temp += "Shuttle departing.<BR><BR>"
	add_fingerprint(user)
	updateUsrDialog(user)

	var/area/centcom/specops/special_ops = locate()
	if(special_ops)
		special_ops.readyalert()//Trigger alarm for the spec ops area.
	GLOB.specops_shuttle_moving_to_station = 1

	GLOB.specops_shuttle_time = world.timeofday + SPECOPS_MOVETIME
	specops_process(user)

#undef SPECOPS_MOVETIME
#undef SPECOPS_STATION_AREATYPE
#undef SPECOPS_DOCK_AREATYPE
#undef SPECOPS_RETURN_DELAY

/// Assault pod launch order: door and driver ASSAULTn goes (n+1) seconds into its phase.
GLOBAL_LIST_INIT(specops_assault_stagger, list("ASSAULT0" = 1 SECOND, "ASSAULT1" = 2 SECONDS, "ASSAULT2" = 3 SECONDS, "ASSAULT3" = 4 SECONDS))
