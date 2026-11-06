// Every air alarm in the world has its thresholds (TLV): the guard that scans each alarm around a test reads them (the full map is where mapped alarms exist: --full-map).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every air alarm that exists holds a threshold table, whether it was mapped or made.
/datum/unit_test/dq_air_alarm_thresholds_exist

/datum/unit_test/dq_air_alarm_thresholds_exist/Run()
	var/checked = 0
	for(var/obj/machinery/alarm/A in world)
		if(QDELETED(A))
			continue
		checked++
		TEST_ASSERT(islist(A.TLV), "[A.type] at [A.x],[A.y],[A.z] in [get_area(A)?.type] has no thresholds (loc [A.loc?.type], area_uid [A.area_uid])")
	log_test("ALARM THRESHOLDS: [checked] air alarm(s) checked")

#endif
