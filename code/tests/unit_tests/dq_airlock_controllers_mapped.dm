// Every mapped airlock controller hears its sensors and drives its doors (a live-map reproduction: the controllers report 0 pressure and refuse
// force-door commands on the live server).

/// The chamber sensor a mapped controller's tag names, found by tag (not through the controller's relation), or null.
/proc/dq_controller_sensor(obj/machinery/embedded_controller/radio/airlock/C)
	for(var/obj/machinery/airlock_sensor/S in world)
		if(S.id_tag == C.tag_chamber_sensor)
			return S
	return null

/// Every mapped airlock controller holds the chamber sensor its tag names (the map's tags resolved to relations) and reads its chamber.
/datum/unit_test/dq_mapped_airlock_controllers_read_pressure

/datum/unit_test/dq_mapped_airlock_controllers_read_pressure/Run()
	var/checked = 0
	var/list/bad = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C in world)
		if(!C.id_tag)
			continue
		var/obj/machinery/airlock_sensor/S = dq_controller_sensor(C)
		if(!S)
			continue
		checked++
		if(C.chamber_sensor != S)
			bad += "[C.id_tag] at [C.x],[C.y],[C.z]: holds sensor [C.chamber_sensor?.id_tag || "none"], its tag names [S.id_tag]"
			continue
		var/heard = C.chamber_pressure()
		var/read = round(S.return_air()?.return_pressure(), 0.1)
		if(abs(heard - read) > 5)
			bad += "[C.id_tag] at [C.x],[C.y],[C.z]: chamber region [heard], sensor tile reads [read] (region [length(C.chamber_region())] turfs)"
	log_test("[checked] mapped controllers with a chamber sensor checked")
	TEST_ASSERT(checked > 0, "no mapped airlock controller has a chamber sensor")
	TEST_ASSERT(!length(bad), "controllers disagree with their sensors: [jointext(bad, "; ")]")

/datum/unit_test/dq_mapped_airlock_controllers_force_doors

/datum/unit_test/dq_mapped_airlock_controllers_force_doors/Run()
	test_driver_begin()
	var/checked = 0
	var/list/bad = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C in world)
		if(!C.id_tag || !isturf(C.loc)) // mapped controllers only: another test's fixtures wait in nullspace for their cleanup
			continue
		var/obj/machinery/door/airlock/D
		for(var/obj/machinery/door/airlock/candidate in world)
			if(candidate.id_tag == C.tag_interior_door)
				D = candidate
				break
		if(!D || !D.power_systems_on() || D.operating)
			continue
		// A docking port refuses its airlock commands while a ship is docked at it, unless its override is on (by design).
		if(C.dock_locked())
			continue
		checked++
		var/datum/scheduler_record/trec = D.sched_rec
		log_test("force_doors: [D.id_tag] operating [D.operating] rec_sched_is_current [trec ? (trec.sched == time_scheduler()) : "no rec"] pending_timers [trec ? length(trec.timers) / SCHED_TIMER_STRIDE : 0] timer_soonest [trec?.timer_soonest] timer_local [trec ? timer_local(trec) : "n/a"] sched_now [time_scheduler().now()] world.time [world.time]")
		var/was = D.density
		C.user_command("force_int")
		test_time(5 SECONDS)
		if(D.density == was)
			bad += "[C.id_tag] at [C.x],[C.y],[C.z]: door [D.id_tag] stayed density [was] (status [json_encode(C.interior_status())], held [D in C.interior_doors], cur_command [D.cur_command])"
		if(checked >= 12)
			break
	test_driver_end()
	TEST_ASSERT(checked > 0, "no mapped controller with a powered interior door")
	TEST_ASSERT(!length(bad), "force_int did not move the door: [jointext(bad, "; ")]")

/// A mapped gas sensor has sent what it reads now (its map-load broadcast came before the air existed).
/datum/unit_test/dq_mapped_air_sensors_report_current_air

/datum/unit_test/dq_mapped_air_sensors_report_current_air/Run()
	var/checked = 0
	var/list/bad = list()
	for(var/obj/machinery/air_sensor/S in world)
		if(!S.on || !S.radio_connection())
			continue
		checked++
		if(S.last_broadcast != S.current_reading_signature())
			bad += "[S.id_tag] at [S.x],[S.y],[S.z]: sent [S.last_broadcast], reads [S.current_reading_signature()]"
	log_test("[checked] mapped air sensors checked")
	TEST_ASSERT(!length(bad), "air sensors report stale readings: [jointext(bad, "; ")]")

/// A dual-port vent takes a siphon direction and a vacuum bound, from its airlock and from the radio: zero is a value, not "unset".
/datum/unit_test/dq_dp_vent_takes_zero_settings

/datum/unit_test/dq_dp_vent_takes_zero_settings/Run()
	var/obj/machinery/atmospherics/binary/dp_vent_pump/V = allocate(/obj/machinery/atmospherics/binary/dp_vent_pump, test_floor())
	V.id = "dq_dp_zero"
	V.airlock_pump(1, 0, 0)
	TEST_ASSERT_EQUAL(V.pump_direction, 0, "the airlock's siphon command set direction 0")
	TEST_ASSERT_EQUAL(V.get_external_pressure_bound(), 0, "the airlock's vacuum bound set 0 kPa")
	V.airlock_pump(1, 1, 50)
	var/datum/signal/S = new
	S.data = list("tag" = "dq_dp_zero", "sigtype" = "command", "direction" = 0, "set_external_pressure" = 0)
	V.receive_signal(S)
	TEST_ASSERT_EQUAL(V.pump_direction, 0, "a radio direction of 0 siphons")
	TEST_ASSERT_EQUAL(V.get_external_pressure_bound(), 0, "a radio bound of 0 is set")
	qdel(S)
