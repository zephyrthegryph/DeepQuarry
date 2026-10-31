/// Conveys all log_mapping messages as unit test failures, as they all indicate mapping problems.
/datum/unit_test/log_mapping
	// Happen before all other tests, to make sure we only capture normal mapping logs.
	priority = TEST_PRE

/datum/unit_test/log_mapping/Run()
	var/static/regex/test_areacoord_regex = regex(@"\(-?\d+,-?\d+,(-?\d+)\)")

	// Z-levels we hold to the mapping-log standard: the station plus the mining
	// station/outpost levels. Ruins and other off-station z-levels frequently do
	// intentionally non-standard things, so a mapping log there isn't necessarily a
	// defect — we scope the hard failure to the z-levels we actually author.
	var/list/scoped_zs = list()
	scoped_zs |= using_map.station_levels
	scoped_zs |= using_map.mining_station_z
	scoped_zs |= using_map.mining_outpost_z

	for(var/log_entry in GLOB.unit_test_mapping_logs)
		// Only fail if AREACOORD was conveyed: mapping errors without coords are
		// impossible to diagnose from a unit test, so they can't be acted on here.
		if(!test_areacoord_regex.Find(log_entry))
			continue
		// Scope to authored z-levels. If the map didn't declare any (older map glue),
		// fall back to failing on everything rather than silently passing.
		if(scoped_zs.len)
			var/z = text2num(test_areacoord_regex.group[1])
			if(!(z in scoped_zs))
				continue

		TEST_FAIL(log_entry)

