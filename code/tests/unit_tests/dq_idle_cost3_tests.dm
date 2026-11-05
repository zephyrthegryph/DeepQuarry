// Idle-cost fixes, third set: power monitors, power sensors, igniters, air alarm thermostats and external airlock freeze checks wait for a
// change instead of polling.

/// A power sensor's history fills on a read: every sample due since the last change holds the reading held over it.
/datum/unit_test/dq_power_sensor_history_fills_on_read

/datum/unit_test/dq_power_sensor_history_fills_on_read/Run()
	var/obj/machinery/power/sensor/S = allocate(/obj/machinery/power/sensor, run_loc_floor_bottom_left)
	var/list/supply = S.history["supply"]
	supply.Cut()
	var/list/demand = S.history["demand"]
	demand.Cut()
	S.held_supply = 1000
	S.held_demand = 400
	S.next_record = TIME_NOW(CLOCK_WORLD) - S.record_interval * 2
	var/list/H = S.history_now()
	TEST_ASSERT_EQUAL(length(H["supply"]), 3, "three samples were due")
	TEST_ASSERT_EQUAL(H["demand"][3], 400, "a sample did not hold the held demand")
	S.history_now()
	TEST_ASSERT_EQUAL(length(H["supply"]), 3, "a second read in the same interval added a sample")
	S.next_record = TIME_NOW(CLOCK_WORLD) - S.record_interval * 500
	S.history_now()
	TEST_ASSERT_EQUAL(length(H["supply"]), S.record_size, "a long gap overfilled the history")

/// An igniter steps only while the air on its tile could catch.
/datum/unit_test/dq_igniter_rests_in_plain_air

/datum/unit_test/dq_igniter_rests_in_plain_air/Run()
	var/obj/machinery/igniter/I = allocate(/obj/machinery/igniter, run_loc_floor_bottom_left)
	I.settle_air()
	TEST_ASSERT(!I.air_burnable, "plain air counted as burnable")
	TEST_ASSERT(!igniter_air_burnable(null), "no tile counted as burnable")

/// An external airlock with no outdoor tile beside it parks its freeze check.
/datum/unit_test/dq_external_airlock_freeze_check_parks_indoors

/datum/unit_test/dq_external_airlock_freeze_check_parks_indoors/Run()
	var/obj/machinery/door/airlock/external/door = allocate(/obj/machinery/door/airlock/external, run_loc_floor_bottom_left)
	door.set_freeze_exposed(TRUE)
	door.freeze_watch_arm()
	TEST_ASSERT(!door.freeze_weather, "an indoor door kept its freeze check running")
	TEST_ASSERT(!door.can_freeze(null), "an indoor door can freeze")
	TEST_ASSERT(!length(door.freeze_watches), "an indoor door watches tiles it does not read")

/// An external airlock beside an outdoor tile senses that tile's temperature and starts its freeze check when it falls below the freezing line.
/datum/unit_test/dq_external_airlock_freeze_sensing_hears_the_cold

/datum/unit_test/dq_external_airlock_freeze_sensing_hears_the_cold/Run()
	var/obj/machinery/door/airlock/external/door = allocate(/obj/machinery/door/airlock/external, run_loc_floor_bottom_left)
	var/turf/simulated/floor/ground = get_step(door, EAST)
	TEST_ASSERT(istype(ground), "no floor beside the door")
	var/was_outdoors = ground.outdoors
	var/datum/gas_mixture/air = ground.return_air()
	var/was_temperature = air.return_temperature()
	ground.set_outdoors(OUTDOORS_YES)
	defer_cleanup(ground, TYPE_PROC_REF(/turf/simulated, set_outdoors), was_outdoors)
	defer_cleanup(null, GLOBAL_PROC_REF(heat_set), air, was_temperature, HEAT_SOURCE_OTHER)
	heat_set(air, T0C + 10, HEAT_SOURCE_OTHER)
	door.set_freeze_exposed(TRUE)
	door.freeze_watch_arm()
	dq_sense_test_deliver()
	TEST_ASSERT_EQUAL(length(door.freeze_watches), 1, "the door did not sense the outdoor tile beside it")
	TEST_ASSERT(!door.freeze_weather, "mild weather started the freeze check")
	// The tile's floor is as cold: air in contact with a warm floor would warm back above the line before the next frame read it.
	var/was_solid = vg_heat_turf_temperatures(list(ground))[1]
	defer_cleanup(null, GLOBAL_PROC_REF(heat_set_solid), ground, was_solid)
	heat_set_solid(ground, T0C - 30)
	heat_set(air, T0C - 30, HEAT_SOURCE_OTHER)
	dq_sense_test_deliver()
	TEST_ASSERT(door.freeze_weather, "the cold crossing did not start the freeze check")
	TEST_ASSERT(!length(door.freeze_watches), "the door kept sensing while its freeze check runs")

/// A working thermostat's stop band is in its room signature: reaching the target changes it, so the alarm needs no scan until then.
/datum/unit_test/dq_air_alarm_thermostat_stop_is_a_band

/datum/unit_test/dq_air_alarm_thermostat_stop_is_a_band/Run()
	var/obj/machinery/alarm/alarm = allocate(/obj/machinery/alarm, run_loc_floor_bottom_left)
	var/target = alarm.target_temperature
	alarm.set_regulating_temperature(GAS_HEATER_HEATING)
	var/list/partials = list()
	TEST_ASSERT_NOTEQUAL(alarm.room_signature(ONE_ATMOSPHERE, target - 1, partials), alarm.room_signature(ONE_ATMOSPHERE, target - 0.2, partials), "reaching the target left a heating thermostat's band unchanged")
	alarm.set_regulating_temperature(GAS_HEATER_IDLE)
	TEST_ASSERT_EQUAL(alarm.room_signature(ONE_ATMOSPHERE, target - 1, partials), alarm.room_signature(ONE_ATMOSPHERE, target - 0.2, partials), "an idle thermostat woke within its start band")
