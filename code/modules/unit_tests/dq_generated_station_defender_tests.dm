/datum/unit_test/dq_generated_station_defender_spawn_is_walkable

/datum/unit_test/dq_generated_station_defender_spawn_is_walkable/Run()
	var/turf/core_turf
	for(var/turf/candidate in world)
		if(!is_blocked_turf(candidate))
			core_turf = candidate
			break
	TEST_ASSERT_NOTNULL(core_turf, "No walkable turf exists for the defender spawn test")
	var/obj/structure/core_blocker = new(core_turf)
	core_blocker.density = TRUE
	var/turf/spawn_turf = generated_station_defender_spawn_turf(core_turf)
	TEST_ASSERT_NOTNULL(spawn_turf, "A dense department core had no adjacent defender spawn")
	TEST_ASSERT(spawn_turf != core_turf, "Defender spawn selected the dense department core")
	TEST_ASSERT(!is_blocked_turf(spawn_turf), "Defender spawn selected a blocked adjacent turf")
	qdel(core_blocker)

/datum/unit_test/dq_generated_station_defense_has_no_idle_loop

/datum/unit_test/dq_generated_station_defense_has_no_idle_loop/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(424242)
	var/datum/generated_station_simulation/simulation = new(spec)
	var/datum/generated_station_director/director = new(simulation)
	var/datum/expedition_site/site = new
	site.station_spec = spec
	site.station_simulation = simulation
	site.station_director = director
	var/datum/generated_station_defense_runtime/runtime = new(site, director)
	TEST_ASSERT_EQUAL(length(runtime.active_patrols), 0, "Fresh defense runtime scheduled idle patrol work")
	TEST_ASSERT_EQUAL(length(runtime.agents), 0, "Defense runtime spawned agents before explicit roster creation")
	TEST_ASSERT(director.defense_runtime == runtime, "Director was not bound to its event-driven defense runtime")
	qdel(runtime)
	site.station_director = null
	site.station_simulation = null
	site.station_spec = null
	qdel(site)
	qdel(director)
	qdel(simulation)
	qdel(spec)
	qdel(planner)
