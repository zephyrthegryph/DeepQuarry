/datum/unit_test/dq_generated_station_air_seed_is_breathable

/datum/unit_test/dq_generated_station_air_seed_is_breathable/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(!candidate.density)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "No simulated floor exists for the generated-station atmosphere test")
	TEST_ASSERT(generated_station_seed_air(T), "Generated station refused to initialize a simulated floor atmosphere")
	var/datum/gas_mixture/air = T.return_air()
	TEST_ASSERT(abs(air.return_pressure() - ONE_ATMOSPHERE) < 5, "Generated station floor did not receive approximately one atmosphere")
	TEST_ASSERT(air.get_moles(/datum/gas/oxygen) > 0, "Generated station floor atmosphere contains no oxygen")
	TEST_ASSERT(air.get_moles(/datum/gas/nitrogen) > 0, "Generated station floor atmosphere contains no nitrogen")
