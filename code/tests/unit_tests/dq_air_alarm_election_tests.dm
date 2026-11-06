// A power loss that takes every air alarm of an area down elects once for the area, not once per alarm (each election rewrites every alarm of the area).

/datum/unit_test/dq_air_alarm_election_once_per_area

/datum/unit_test/dq_air_alarm_election_once_per_area/Run()
	var/turf/spot = run_loc_floor_bottom_left
	var/list/alarms = list()
	for(var/i in 1 to 5)
		alarms += allocate(/obj/machinery/alarm, spot)
	test_drain()
	test_time(1 SECOND)
	var/obj/machinery/alarm/first = alarms[1]
	var/area/served = first.alarm_area
	TEST_ASSERT_NOTNULL(served, "the alarms joined an area")
	TEST_ASSERT(served.main_air_alarm_is_operating(), "the area has a working main alarm before the loss")
	var/runs_before = GLOB.air_election_runs
	for(var/obj/machinery/alarm/A as anything in alarms)
		A.set_powered(FALSE)
	test_drain()
	test_time(1 SECOND)
	for(var/obj/machinery/alarm/A as anything in alarms)
		TEST_ASSERT(!A.operable(), "alarm lost power")
	TEST_ASSERT_EQUAL(GLOB.air_election_runs - runs_before, 1, "five alarms lost power: the area elected once, not once per alarm")
	TEST_ASSERT(!GLOB.air_election_pending[served], "no election is left pending")
	TEST_ASSERT(!served.main_air_alarm, "with every alarm down there is no main alarm")
	// Power back: one alarm is elected again.
	for(var/obj/machinery/alarm/A as anything in alarms)
		A.set_powered(TRUE)
	test_drain()
	test_time(1 SECOND)
	TEST_ASSERT(served.main_air_alarm_is_operating(), "power back: the area has a working main alarm again")
