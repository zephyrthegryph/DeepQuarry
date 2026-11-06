// Docking end to end, the way a player does it, on the map's own shuttles, ports, airlocks and controllers (no fixture
// controllers, no direct initiate_docking() calls): a pilot presses "move" on a mapped ferry console and the shuttle flies,
// arrives and docks at the far port, then flies back and docks at home; a passenger boards the arrivals shuttle and it
// brings them to the station and docks there. Run on Southern Cross with --full-map; on the test map it drives whatever
// ferries that map has.

/// Time a flight may take, warmup and docking included, before the test gives up on it. The test waits on the wall clock: the
/// injected test clock (test_driver_begin()) never runs the live items the map's controllers and shuttles armed at boot, so under
/// it nothing mapped would ever step (doc/testing.md "The kernel clock").
#define DQ_DOCK_E2E_FLIGHT_LIMIT (150 SECONDS)

/// The text state of a docking port and its airlocks' cycles, for a failure message.
/proc/dq_dock_e2e_describe(datum/docking_port/D)
	if(!D)
		return "no controller"
	. = "[D.id_tag]: [D.get_docking_status()] mode [D.control_mode] peer [D.peer?.id_tag || "none"] ready [D.ready_reported]"
	var/obj/machinery/embedded_controller/C = D.console
	if(C)
		. += " step [C.processing_shown ? "on" : "off"] work [work_started(C) ? "started" : "stopped"] operable [C.operable()] area [get_area(C)] at [C.x],[C.y],[C.z]"
	. += " | [dq_docking_diagnostics(D)]"

/// The mapped airlock consoles a docking port docks, found by the map's tags (not through the port's relations): the port's own console
/// when it is an airlock, or the consoles whose master_tag names it.
/proc/dq_dock_e2e_airlocks(datum/docking_port/D)
	. = list()
	if(istype(D.console, /obj/machinery/embedded_controller/radio/airlock))
		. += D.console
	for(var/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/C in world)
		if(C.master_tag && C.master_tag == D.id_tag)
			. += C

/// The mapped doors a docking port opens when it docks (an airlock port's two doors, a simple port's hatch), found by tag.
/proc/dq_dock_e2e_doors(datum/docking_port/D)
	. = list()
	var/list/tags = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in dq_dock_e2e_airlocks(D))
		tags += C.tag_interior_door
		tags += C.tag_exterior_door
	if(istype(D.console, /obj/machinery/embedded_controller/radio/simple_docking_controller))
		var/obj/machinery/embedded_controller/radio/simple_docking_controller/S = D.console
		tags += S.tag_door
	for(var/obj/machinery/door/airlock/door in world)
		if(door.id_tag && (door.id_tag in tags))
			. += door

/datum/unit_test/dq_docking_end_to_end
	abstract_type = /datum/unit_test/dq_docking_end_to_end
	timeout = 300 // real flights and airlock cycles, a few minutes of world time
	/// The pilot or passenger.
	var/mob/living/carbon/human/actor
	/// area -> list(atmosalm, firedoors_closed) when the test began: the station's own air alarms trip on drift while minutes of world time pass.
	var/list/area_alarms

/datum/unit_test/dq_docking_end_to_end/Run()
	// The whole station runs for minutes while the shuttles fly: put back what moves on its own meanwhile (floors, alarms, the latency flag).
	// The ambient snapshot is taken now, before any time passes: taken lazily at the first declared turf (mid-flight), it recorded an alarm
	// the drifting server room had already raised and put that back.
	capture_ambient()
	set_global(nameof(GLOB.latency_slow_logged), GLOB.latency_slow_logged)
	if(baseline?["solids"])
		defer_cleanup(null, GLOBAL_PROC_REF(unit_test_solid_restore), baseline["solids"])
	area_alarms = list()
	for(var/area/A in world)
		area_alarms[A] = list(A.atmosalm, A.firedoors_closed)
	defer_cleanup(src, PROC_REF(put_alarms_back))
	run_flow()

/datum/unit_test/dq_docking_end_to_end/proc/put_alarms_back()
	for(var/area/A as anything in area_alarms)
		var/list/was = area_alarms[A]
		A.set_atmosalm(was[1])
		A.set_firedoors_closed(was[2])

/// The air the flight to `destination` moves: the shuttle's own turfs and the ones it lands on, put back when the test ends.
/datum/unit_test/dq_docking_end_to_end/proc/declare_flight_air(datum/shuttle/S, obj/effect/shuttle_landmark/destination)
	for(var/area/A in S.shuttle_area)
		var/list/moved = get_turf_translation(get_turf(S.current_location()), get_turf(destination), A.contents)
		for(var/turf/T as anything in moved)
			dq_atmos_test_snapshot_air(T)
			dq_atmos_test_snapshot_air(moved[T])

/// Lets `delay` of real time pass, the live kernel stepping everything meanwhile.
/datum/unit_test/dq_docking_end_to_end/proc/wait_real(delay)
	sleep(delay)

/// A flight of the test takes seconds: the shuttle's warmup and transit times are its configuration, not its code path.
/datum/unit_test/dq_docking_end_to_end/proc/hurry(datum/shuttle/autodock/S)
	S.warmup_time = 0
	S.move_time = 5

/datum/unit_test/dq_docking_end_to_end/proc/run_flow()
	return

/// A person with an ID that opens every station and CentCom door, standing at `T`.
/datum/unit_test/dq_docking_end_to_end/proc/make_actor(turf/T)
	// A mob created in place never enters its area; the walk-in that wakes a shuttle waiting for passengers (area/Entered) is a move from outside.
	var/turf/outside = locate(world.maxx, world.maxy, T.z)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, get_area(outside) == get_area(T) ? get_step(T, NORTH) : outside)
	H.forceMove(T)
	H.enable_godmode()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, T)
	I.set_access(SSaccess.get_all_accesses() | SSaccess.get_all_centcom_access())
	H.equip_to_slot_or_del(allocate(/obj/item/clothing/under/color/grey, T), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(I, SLOT_ID_ID)
	return H

/// Lets time pass until `S` has flown, arrived and finished docking at `destination` (or the limit passes). Returns the failure text, or null.
/datum/unit_test/dq_docking_end_to_end/proc/await_docked(datum/shuttle/autodock/S, obj/effect/shuttle_landmark/destination)
	var/waited = 0
	while(waited < DQ_DOCK_E2E_FLIGHT_LIMIT)
		wait_real(2 SECONDS)
		waited += 2 SECONDS
		if(S.current_location() != destination || S.moving_status != SHUTTLE_IDLE || S.process_state != IDLE_STATE)
			continue
		if(S.shuttle_docking_controller?.docked() && S.active_docking_controller()?.docked())
			log_test("[S.name] docked at [destination.name] after [waited / (1 SECOND)] s")
			return null
	return "[S.name] at [S.current_location()?.name] (wanted [destination.name]), moving [S.moving_status], state [S.process_state] after [waited / (1 SECOND)] s; \
		shuttle side {[dq_dock_e2e_describe(S.shuttle_docking_controller)]}; port side {[dq_dock_e2e_describe(S.active_docking_controller())]}"

/// Both ports report docked and every door they opened is open (given the few seconds a door takes to swing).
/datum/unit_test/dq_docking_end_to_end/proc/check_docked(datum/shuttle/autodock/S, where)
	var/list/ports = list(S.shuttle_docking_controller, S.active_docking_controller())
	var/list/doors = list()
	for(var/datum/docking_port/D in ports)
		TEST_ASSERT_EQUAL(D.get_docking_status(), "docked", "[S.name] at [where]: [D.id_tag] finished docking")
		var/list/own = dq_dock_e2e_doors(D)
		TEST_ASSERT(length(own), "[S.name] at [where]: [D.id_tag] drives a mapped door")
		doors += own
	for(var/second in 1 to 10)
		var/closed = FALSE
		for(var/obj/machinery/door/airlock/door as anything in doors)
			if(door.density)
				closed = TRUE
		if(!closed)
			break
		wait_real(1 SECOND)
	for(var/obj/machinery/door/airlock/door as anything in doors)
		TEST_ASSERT(!door.density, "[S.name] at [where]: door [door.id_tag] opened once docked")

// ---- A pilot flies a mapped ferry from its console, there and back (one ferry per test: each is minutes of live world time) ----

/datum/unit_test/dq_docking_end_to_end/ferry_console
	abstract_type = /datum/unit_test/dq_docking_end_to_end/ferry_console
	/// The shuttle's name; a map without it has nothing to fly.
	var/ferry_name

/// A simple hatch at both ends.
/datum/unit_test/dq_docking_end_to_end/ferry_console/merchant
	ferry_name = "Merchant"

/// An airlock docking port at the station end.
/datum/unit_test/dq_docking_end_to_end/ferry_console/administration
	ferry_name = "Administration"

/datum/unit_test/dq_docking_end_to_end/ferry_console/centcom
	ferry_name = "Centcom"

/// The ferries a player can fly from a mapped console, with a docking port at both ends.
/datum/unit_test/dq_docking_end_to_end/ferry_console/proc/console_ferries()
	. = list()
	for(var/obj/machinery/computer/shuttle_control/console in world)
		if(istype(console, /obj/machinery/computer/shuttle_control/web) || console.skip_act)
			continue
		var/datum/shuttle/autodock/ferry/F = shuttles_shuttles()[console.shuttle_tag]
		if(!istype(F) || F.always_process || istype(F, /datum/shuttle/autodock/ferry/escape_pod) || istype(F, /datum/shuttle/autodock/ferry/emergency) || istype(F, /datum/shuttle/autodock/ferry/supply))
			continue
		if(!F.shuttle_docking_controller || !F.landmark_station()?.docking_controller() || !F.landmark_offsite()?.docking_controller())
			continue
		if(!(F in .))
			.[F] = console

/datum/unit_test/dq_docking_end_to_end/ferry_console/run_flow()
	var/list/ferries = console_ferries()
	log_test("[length(ferries)] ferries can be flown from their consoles: [english_list(ferries)]")
	var/datum/shuttle/autodock/ferry/wanted = shuttles_shuttles()[ferry_name]
	if(!wanted)
		log_test("this map has no [ferry_name] shuttle")
		return
	TEST_ASSERT(wanted in ferries, "[ferry_name] has a console and a docking port at both ends")
	for(var/datum/shuttle/autodock/ferry/F as anything in list(wanted))
		var/obj/machinery/computer/shuttle_control/console = ferries[F]
		actor = make_actor(get_turf(console))
		hurry(F)
		var/start_failure = await_docked(F, F.current_location()) // roundstart docking may still be cycling
		TEST_ASSERT(!start_failure, "[F.name] at its start: [start_failure]")
		if(start_failure)
			return
		// Leg 1 launches the moment the start port reports docked, while its doors may still be swinging open: a quick pilot.
		for(var/leg in 1 to 2)
			var/obj/effect/shuttle_landmark/destination = F.next_location()
			declare_flight_air(F, destination)
			var/datum/op_result/pressed = hc_ui(actor, console, "move")
			log_test("[F.name] leg [leg]: move pressed ([pressed?.outcome]), launching to [destination?.name]")
			var/failure = await_docked(F, destination)
			TEST_ASSERT(!failure, "[F.name] leg [leg]: [failure]")
			if(failure)
				return
			check_docked(F, destination.name)
			actor.forceMove(get_turf(console)) // the console flew with the shuttle; stay at it

// ---- A passenger rides the arrivals shuttle to the station ----

/datum/unit_test/dq_docking_end_to_end/arrivals_passenger

/datum/unit_test/dq_docking_end_to_end/arrivals_passenger/run_flow()
	var/datum/shuttle/autodock/ferry/arrivals/S
	for(var/name in shuttles_shuttles())
		S = shuttles_shuttles()[name]
		if(istype(S))
			break
		S = null
	if(!S)
		log_test("this map has no arrivals shuttle")
		return
	TEST_ASSERT(S.location == FERRY_LOCATION_OFFSITE, "the arrivals shuttle starts away from the station")
	var/turf/seat
	for(var/area/A in S.shuttle_area)
		for(var/turf/simulated/floor/T in A)
			seat = T
			break
		if(seat)
			break
	TEST_ASSERT_NOTNULL(seat, "the arrivals shuttle has a floor to stand on")
	hurry(S)
	declare_flight_air(S, S.landmark_station())
	actor = make_actor(seat)
	wait_real(2 SECONDS)
	log_test("arrivals: passenger at [seat.x],[seat.y],[seat.z] in [get_area(seat)]; sees passengers [S.check_for_passengers()], working [S.working], flags [S.shuttle_flags], process [S.process_state], moving [S.moving_status], awaiting passengers [S.awaiting_passengers]")
	var/failure = await_docked(S, S.landmark_station())
	TEST_ASSERT(!failure, "arrivals: [failure]")
	check_docked(S, "the station")
	// The passenger steps off and the empty shuttle undocks and goes back on its own (the shuttle's own automation), as after every arrival.
	actor.forceMove(get_turf(S.active_docking_controller().console))
	var/waited = 0
	while(waited < DQ_DOCK_E2E_FLIGHT_LIMIT && !(S.location == FERRY_LOCATION_OFFSITE && S.moving_status == SHUTTLE_IDLE && S.process_state == IDLE_STATE))
		wait_real(2 SECONDS)
		waited += 2 SECONDS
	TEST_ASSERT(S.location == FERRY_LOCATION_OFFSITE, "the empty arrivals shuttle undocked and went back after [waited / (1 SECOND)] s: \
		shuttle side {[dq_dock_e2e_describe(S.shuttle_docking_controller)]}")

#undef DQ_DOCK_E2E_FLIGHT_LIMIT
