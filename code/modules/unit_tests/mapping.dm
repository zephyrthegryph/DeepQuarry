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

/* Should probably be done as a linter thing instead
/// Checks all machines for legal access numbers
/datum/unit_test/all_access_id_must_have_existing_datums

/datum/unit_test/all_access_id_must_have_existing_datums/Run()
	var/failed = FALSE
	var/list/access_datums = SSaccess.get_all_access_datums_by_id()

	for(var/obj/machinery/thing in world)
		failed += validate_list(thing.req_access, thing, "req_access")
		failed += validate_list(thing.req_one_access, thing, "req_one_access")
	if(failed)
		TEST_FAIL("Machinery had an illegal access id.")

/datum/unit_test/proc/validate_list(list/access_list, obj/machinery/thing, name_list)
	if(!access_list)
		return FALSE // null is legal

	if(!islist(access_list))
		TEST_NOTICE(src, "Access - [thing] ([thing.x].[thing.y].[thing.z]) had a [name_list] that was not a list or null.")
		return TRUE // Was something other than null or a list... illegal

	var/failed = FALSE
	for(var/access in access_list)
		if(!SSaccess.get_access_by_id(access))
			TEST_NOTICE(src, "Access - [thing] ([thing.x].[thing.y].[thing.z]) had a [name_list] with a non-existant id [access].")
			failed = TRUE // has a non-existant id, illegal

	return failed
*/
