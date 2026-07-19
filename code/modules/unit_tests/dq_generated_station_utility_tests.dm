/datum/unit_test/dq_generated_station_physical_utilities

/datum/unit_test/dq_generated_station_physical_utilities/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(7717)
	var/datum/generated_station_materializer/materializer = new
	var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, world.maxx - spec.grid_width + 1, world.maxy - spec.grid_height + 1)
	TEST_ASSERT_NOTNULL(materialized, "Physical utility test station did not materialize: [materializer.last_failure_details]")
	var/datum/generated_station_utility_builder/builder = new
	var/datum/generated_station_utility_topology/topology = builder.build(spec, materialized)
	TEST_ASSERT_NOTNULL(topology, "Physical utility topology builder failed")
	var/room_count = length(materialized.modules)
	TEST_ASSERT_EQUAL(length(topology.apcs), room_count, "Generated station did not receive one real APC per room")
	TEST_ASSERT_EQUAL(length(topology.supply_vents), room_count, "Generated station did not receive one real supply vent per room")
	TEST_ASSERT_EQUAL(length(topology.scrubbers), room_count, "Generated station did not receive one real scrubber per room")
	TEST_ASSERT_EQUAL(length(topology.alarms), room_count, "Generated station did not receive one real air alarm per room")
	TEST_ASSERT(topology.power_available(), "Generated station physical power capability is unavailable")
	TEST_ASSERT(topology.atmosphere_available(), "Generated station physical atmosphere capability is unavailable")
	TEST_ASSERT(topology.power_network_is_global(), "Generated APCs are not connected to one station-wide power grid")
	TEST_ASSERT(topology.atmosphere_networks_are_global(), "Generated vents and scrubbers are not connected to shared station mains")
	for(var/obj/machinery/power/apc/APC in topology.apcs)
		var/apc_wall_direction = generated_station_adjacent_wall_direction(get_turf(APC))
		TEST_ASSERT(apc_wall_direction, "Generated APC is not mounted against a wall")
		TEST_ASSERT_EQUAL(APC.dir, apc_wall_direction, "Generated APC does not face into its supporting wall")
		TEST_ASSERT_NOTNULL(APC.terminal, "Generated APC has no physical terminal")
		TEST_ASSERT_NOTNULL(APC.cell, "Generated APC has no physical cell")
		TEST_ASSERT_NOTNULL(APC.terminal.powernet, "Generated APC terminal is not attached to a powernet")
		var/area/generated_station/powered_area = get_area(APC)
		powered_area.power_change()
		TEST_ASSERT(powered_area.powered(EQUIP), "Generated area is not powered by its physical APC")
	var/list/source_smeses = list()
	var/list/stored_charges = list()
	var/list/source_generators = list()
	for(var/obj/machinery/power/smes/candidate_smes in topology.power_objects)
		source_smeses += candidate_smes
		stored_charges += candidate_smes.charge
		candidate_smes.charge = 0
	for(var/obj/machinery/power/generator/generated_station/candidate_generator in topology.power_objects)
		source_generators += candidate_generator
		candidate_generator.stat |= BROKEN
	TEST_ASSERT(length(source_smeses), "Generated station has no physical SMES source")
	TEST_ASSERT(length(source_generators), "Generated station has no physical continuous generator")
	TEST_ASSERT(!topology.power_available(), "Physical power capability stayed available after source depletion")
	for(var/i in 1 to length(source_smeses))
		var/obj/machinery/power/smes/source_smes = source_smeses[i]
		source_smes.charge = stored_charges[i]
	for(var/obj/machinery/power/generator/generated_station/source_generator in source_generators)
		source_generator.stat &= ~BROKEN
	TEST_ASSERT(topology.power_available(), "Physical power capability did not recover after source restoration")
	for(var/obj/machinery/atmospherics/pipe/tank/air/full/generated_station/tank in topology.atmos_objects)
		TEST_ASSERT_NOTNULL(tank.parent, "Generated air reservoir is not part of a pipeline")
		TEST_ASSERT(tank.parent.air?.return_pressure() > ONE_ATMOSPHERE, "Generated air reservoir pipeline pressure is [tank.parent.air?.return_pressure()] Pa")
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in topology.supply_vents)
		TEST_ASSERT_NOTNULL(vent.node, "Generated supply vent is not connected to its LINDA pipenet")
		TEST_ASSERT_NOTNULL(vent.network, "Generated supply vent has no built LINDA pipe network")
		TEST_ASSERT(vent.air_contents?.return_pressure() > ONE_ATMOSPHERE, "Generated vent mixture pressure is [vent.air_contents?.return_pressure()] Pa")
	for(var/obj/machinery/atmospherics/unary/vent_scrubber/scrubber in topology.scrubbers)
		TEST_ASSERT_NOTNULL(scrubber.node, "Generated scrubber is not connected to its LINDA pipenet")
		TEST_ASSERT_NOTNULL(scrubber.network, "Generated scrubber has no built LINDA pipe network")
	for(var/obj/machinery/alarm/alarm in topology.alarms)
		TEST_ASSERT(generated_station_adjacent_wall_direction(get_turf(alarm)), "Generated air alarm is not mounted against a wall")
	for(var/datum/generated_station_module/module in materialized.modules)
		var/area/generated_station/room_area = materialized.module_areas[module.id]
		TEST_ASSERT_NOTNULL(room_area, "Generated room [module.id] has no independent area")
		var/apc_count = 0
		var/air_alarm_count = 0
		var/fire_alarm_count = 0
		var/vent_count = 0
		var/scrubber_count = 0
		for(var/obj/machinery/power/apc/room_apc in room_area) apc_count++
		for(var/obj/machinery/alarm/room_alarm in room_area) air_alarm_count++
		for(var/obj/machinery/firealarm/room_fire_alarm in room_area) fire_alarm_count++
		for(var/obj/machinery/atmospherics/unary/vent_pump/room_vent in room_area) vent_count++
		for(var/obj/machinery/atmospherics/unary/vent_scrubber/room_scrubber in room_area) scrubber_count++
		TEST_ASSERT_EQUAL(apc_count, 1, "Generated room [module.id] does not have exactly one APC")
		TEST_ASSERT_EQUAL(air_alarm_count, 1, "Generated room [module.id] does not have exactly one air alarm")
		TEST_ASSERT_EQUAL(fire_alarm_count, 1, "Generated room [module.id] does not have exactly one fire alarm")
		TEST_ASSERT_EQUAL(vent_count, 1, "Generated room [module.id] does not have exactly one supply vent")
		TEST_ASSERT_EQUAL(scrubber_count, 1, "Generated room [module.id] does not have exactly one scrubber")
		var/room_lights = 0
		for(var/obj/machinery/light/light in room_area)
			room_lights++
			var/light_wall_direction = generated_station_adjacent_wall_direction(get_turf(light))
			TEST_ASSERT(light_wall_direction, "Generated room [module.id] has a light not attached to a wall")
			TEST_ASSERT_EQUAL(light.dir, light_wall_direction, "Generated room [module.id] has a light facing away from its supporting wall")
			TEST_ASSERT(light.pixel_x || light.pixel_y, "Generated room [module.id] has an unshifted wall light")
		TEST_ASSERT(room_lights, "Generated room [module.id] has no wall lights")
		for(var/turf/open/room_turf in room_area)
			TEST_ASSERT(room_turf.air?.return_pressure() >= 0.9 * ONE_ATMOSPHERE, "Generated room [module.id] has an airless starting tile at [generated_station_coordinate(room_turf)]")
			TEST_ASSERT(!locate(/obj/effect/floor_decal/corner) in room_turf, "Generated room [module.id] has a random center-floor color decal")
			TEST_ASSERT(!(locate(/obj/structure/table) in room_turf) || !(locate(/obj/structure/bed/chair) in room_turf), "Generated room [module.id] has a chair stacked on a table at [generated_station_coordinate(room_turf)]")
	// Immediate pressure assertions can pass before Rust publishes rebuilt turf
	// adjacency. Exercise normal subsystem scheduling and prove the sealed station
	// remains pressurized after publication and diffusion.
	for(var/i in 1 to 20)
		stoplag(1)
	for(var/module_id in materialized.module_areas)
		var/area/generated_station/stable_room_area = materialized.module_areas[module_id]
		for(var/turf/open/stable_turf in stable_room_area)
			TEST_ASSERT(stable_turf.air?.return_pressure() >= 0.85 * ONE_ATMOSPHERE, "Generated room [module_id] lost pressure after atmos publication at [generated_station_coordinate(stable_turf)]")
	qdel(topology)
	qdel(builder)
	qdel(materialized)
	qdel(spec)
	qdel(materializer)
	qdel(planner)
