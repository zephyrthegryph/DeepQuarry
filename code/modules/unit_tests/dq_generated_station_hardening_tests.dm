/datum/unit_test/dq_generated_station_microgrid_failure_recovery

/datum/unit_test/dq_generated_station_microgrid_failure_recovery/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(5150)
	var/datum/generated_station_materializer/materializer = new
	var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, world.maxx - 73, world.maxy - 73)
	TEST_ASSERT_NOTNULL(materialized, "Microgrid test station did not materialize")
	var/datum/generated_station_utility_builder/builder = new
	var/datum/generated_station_utility_topology/topology = builder.build(spec, materialized)
	TEST_ASSERT_NOTNULL(topology, "Microgrid test station did not build physical utilities")
	TEST_ASSERT(topology.power_available(), "Operational generated microgrid did not provide physical power")
	var/list/smes_charges = list()
	var/list/generators = list()
	for(var/obj/machinery/power/smes/SMES in topology.power_objects)
		smes_charges[SMES] = SMES.charge
		SMES.charge = 0
	for(var/obj/machinery/power/generator/generated_station/generator in topology.power_objects)
		generators += generator
		generator.stat |= BROKEN
	TEST_ASSERT(!topology.power_available(), "Generated microgrid remained available after every source was depleted")
	for(var/obj/machinery/power/smes/SMES as anything in smes_charges)
		SMES.charge = smes_charges[SMES]
	for(var/obj/machinery/power/generator/generated_station/generator as anything in generators)
		generator.stat &= ~BROKEN
	TEST_ASSERT(topology.power_available(), "Generated microgrid did not recover after restoring its physical sources")
	qdel(topology)
	qdel(builder)
	qdel(materialized)
	qdel(spec)
	qdel(materializer)
	qdel(planner)

/datum/unit_test/dq_generated_station_repeated_materialization_is_bounded

/datum/unit_test/dq_generated_station_repeated_materialization_is_bounded/Run()
	var/origin_x = world.maxx - 73
	var/origin_y = world.maxy - 73
	for(var/seed in list(101, 101, 101))
		var/datum/generated_station_planner/planner = new
		var/datum/generated_station_spec/spec = planner.plan(seed)
		var/datum/generated_station_materializer/materializer = new
		var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, origin_x, origin_y)
		TEST_ASSERT_NOTNULL(materialized, "Repeated generated-station materialization failed for seed [seed]")
		var/datum/expedition_site/site = new(world.maxz, EXP_DIFF_LOW)
		site.station_spec = spec
		site.station_materialization = materialized
		TEST_ASSERT(site.initialize_generated_station_runtime(), "Repeated station failed runtime initialization for seed [seed]")
		TEST_ASSERT(site.initialize_generated_station_infrastructure(), "Repeated station failed infrastructure initialization for seed [seed]")
		var/atom_count = 0
		var/breathable_floor_count = 0
		for(var/turf/open/T in block(locate(origin_x, origin_y, world.maxz), locate(origin_x + 71, origin_y + 71, world.maxz)))
			for(var/atom/movable/thing in T)
				if(!QDELETED(thing))
					atom_count++
			if(istype(T, /turf/simulated/floor) && istype(get_area(T), /area/generated_station))
				breathable_floor_count++
				TEST_ASSERT(abs(T.air.return_pressure() - ONE_ATMOSPHERE) < 5, "Seed [seed] contains an unpressurized generated floor")
		TEST_ASSERT(breathable_floor_count > 100, "Seed [seed] produced too little habitable station floor")
		TEST_ASSERT(atom_count < 2500, "Seed [seed] exceeded the generated-station atom budget ([atom_count])")
		var/list/owned_atoms = materialized.owned_furnishing_atoms.Copy()
		owned_atoms |= materialized.doors
		owned_atoms |= materialized.infrastructure
		if(materialized.entry)
			owned_atoms |= materialized.entry
		var/station_id = spec.id
		qdel(site)
		stoplag(1)
		TEST_ASSERT_NULL(generated_station_runtime(station_id), "Deleted generated site leaked its runtime registry entry")
		for(var/atom/movable/owned_atom as anything in owned_atoms)
			TEST_ASSERT(QDELETED(owned_atom), "Deleted generated site left owned atom [owned_atom.type] live")
		qdel(materializer)
		qdel(planner)
