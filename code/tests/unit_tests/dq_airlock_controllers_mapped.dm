// Every mapped airlock controller hears its sensors and drives its doors (a live-map reproduction: the controllers report 0 pressure and refuse
// force-door commands on the live server).

/// The airlock program of a mapped controller (docking ports are airlock controllers too: their sensors and doors must work the same way).
/proc/dq_controller_airlock_program(obj/machinery/embedded_controller/C)
	return C.program

/// The chamber sensor a mapped controller listens to, or null.
/proc/dq_controller_sensor(datum/embedded_program/airlock/program)
	for(var/obj/machinery/airlock_sensor/S in world)
		if(S.id_tag == program.tag_chamber_sensor)
			return S
	return null

/datum/unit_test/dq_mapped_airlock_controllers_read_pressure

/datum/unit_test/dq_mapped_airlock_controllers_read_pressure/Run()
	var/checked = 0
	var/list/bad = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C in world)
		var/datum/embedded_program/airlock/program = dq_controller_airlock_program(C)
		if(!istype(program))
			continue
		if(!C.id_tag)
			continue
		var/obj/machinery/airlock_sensor/S = dq_controller_sensor(program)
		if(!S)
			continue
		checked++
		var/heard = program.memory["chamber_sensor_pressure"]
		var/read = round(S.return_air()?.return_pressure(), 0.1)
		if(abs(heard - read) > 1)
			bad += "[C.id_tag] at [C.x],[C.y],[C.z]: controller [heard], sensor reads [read] (sensor prev [S.previousPressure], on [S.on], conn [!!S.radio_connection()], freq [S.frequency]/[C.frequency])"
	log_test("[checked] mapped controllers with a chamber sensor checked")
	TEST_ASSERT(checked > 0, "no mapped airlock controller has a chamber sensor")
	TEST_ASSERT(!length(bad), "controllers disagree with their sensors: [jointext(bad, "; ")]")

/datum/unit_test/dq_mapped_airlock_controllers_force_doors

/datum/unit_test/dq_mapped_airlock_controllers_force_doors/Run()
	test_driver_begin()
	var/checked = 0
	var/list/bad = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C in world)
		var/datum/embedded_program/airlock/program = dq_controller_airlock_program(C)
		if(!istype(program))
			continue
		if(!C.id_tag)
			continue
		var/obj/machinery/door/airlock/D
		for(var/obj/machinery/door/airlock/candidate in world)
			if(candidate.id_tag == program.tag_interior_door)
				D = candidate
				break
		if(!D || !D.power_systems_on() || D.operating)
			continue
		// A docking port refuses its airlock commands while a ship is docked at it, unless its override is on (by design).
		var/obj/machinery/embedded_controller/radio/airlock/airlock_console = C
		if(airlock_console.dock_locked())
			continue
		checked++
		var/was = D.density
		program.receive_user_command("force_int")
		test_time(5 SECONDS)
		if(D.density == was)
			bad += "[C.id_tag] at [C.x],[C.y],[C.z]: door [D.id_tag] stayed density [was] (status [json_encode(program.memory["interior_status"])], freq door [D.frequency] ctl [C.frequency], door conn [!!D.radio_connection()], cur_command [D.cur_command])"
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
