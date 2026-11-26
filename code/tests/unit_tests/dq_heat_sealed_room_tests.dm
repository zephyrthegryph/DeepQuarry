// A sealed room with no heat source keeps its temperature (the idle heat drift that cycled the air alarms' heat pumps).

/// The temperatures around a sealed test floor, for the log: its air, its floor solid and each walled neighbour.
/proc/dq_heat_room_report(turf/simulated/floor/T)
	var/list/parts = list("air [round(T.turf_air().return_temperature(), 0.001)]", "floor [round(T.get_temperature(), 0.001)]")
	for(var/dir in GLOB.cardinals_multiz)
		var/turf/N = get_step_multiz(T, dir)
		if(N)
			parts += "[dir2text(dir)] [N.type] [round(N.get_temperature(), 0.001)]"
	return jointext(parts, ", ")

/// One sealed floor of standard air at 20 C, walled on every side, run for a simulated minute: its air stays within 0.2 K.
/datum/unit_test/dq_heat_sealed_room_holds_its_temperature

/datum/unit_test/dq_heat_sealed_room_holds_its_temperature/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for the sealed room")
	var/turf/simulated/floor/T = pair[1]
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	dq_atmos_test_fill_standard_air(T)
	T.air_update_turf(TRUE, FALSE)
	var/start = T.turf_air().return_temperature()
	log_test("SEALED ROOM t=0: [dq_heat_room_report(T)]")
	for(var/i in 1 to 6)
		SSair.run_gas_frames(10)
		log_test("SEALED ROOM t=[i * 10]: [dq_heat_room_report(T)]")
	var/drift = T.turf_air().return_temperature() - start
	TEST_ASSERT(abs(drift) < 0.2, "a sealed room drifted [round(drift, 0.01)] K in a minute ([dq_heat_room_report(T)])")

