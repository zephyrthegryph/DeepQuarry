/// A station alert console's screen follows the alarms it watches through its look: an alarm raised or cleared marks the change, so the
/// refresh sweep never finds its drawn screen behind (REFRESH DRIFT: /obj/machinery/computer/station_alert/all draw()).
/datum/unit_test/dq_station_alert_screen_follows_alarms

/datum/unit_test/dq_station_alert_screen_follows_alarms/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/computer/station_alert/all/C = allocate(/obj/machinery/computer/station_alert/all, T)
	C.set_grid_power(TRUE)
	C.set_broken_condition(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.look_key, refresh_look(C, apply = FALSE), "a quiet console is drawn as it is")
	var/obj/machinery/firealarm/source = allocate(/obj/machinery/firealarm, T)
	GLOB.fire_alarm.triggerAlarm(T, source)
	refresh_flush()
	TEST_ASSERT(length(C.alarm_monitor.major_alarms()), "the console sees the fire alarm")
	TEST_ASSERT_EQUAL(C.look_key, refresh_look(C, apply = FALSE), "the raised alarm left the console's screen undrawn")
	GLOB.fire_alarm.clearAlarm(T, source)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.look_key, refresh_look(C, apply = FALSE), "the cleared alarm left the console's screen undrawn")
