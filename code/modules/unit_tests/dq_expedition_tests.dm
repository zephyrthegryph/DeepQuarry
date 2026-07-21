// DQ expedition generator tests.
// Exercises the on-demand z-level generator (SSexpedition) end-to-end. This is
// a genuine integration test: generate_site() allocates a real z-level, runs
// the verdigris cave-gen FFI to carve it, and scatters content. If verdigris
// failed to load, the carve would no-op (every cell stays a dense wall),
// populate_site() would find no walkable floor, and generate_site() returns
// null — so a non-null site with a walkable landing turf proves the whole
// chain (z-allocation + Rust cave gen + content scatter) works.

// Directly exercises the verdigris cave-gen FFI the expedition carver depends on.
// Cheap (one small grid, no z-allocation) so it runs even under slow emulation.
// If verdigris isn't loaded/working, verdigris_generate_automata() returns null
// or a degenerate uniform grid.
/datum/unit_test/dq_verdigris_cavegen_ffi

/datum/unit_test/dq_verdigris_cavegen_ffi/Run()
	var/list/grid = verdigris_generate_automata(48, 48, 4, 45)
	TEST_ASSERT_NOTNULL(grid, "verdigris_generate_automata() returned null — cave-gen FFI not loaded/working")
	TEST_ASSERT_EQUAL(length(grid), 48 * 48, "automata grid has [length(grid)] cells, expected [48 * 48]")
	// A real carve yields a MIX of cell states; a uniform grid means the FFI
	// produced nothing meaningful. Cell values are numbers, so key the set by
	// their string form — list[number] would be positional indexing, not a set.
	var/list/distinct = list()
	for(var/cell in grid)
		distinct["[cell]"] = TRUE
	TEST_ASSERT(length(distinct) >= 2, "automata grid is uniform (states: [json_encode(distinct)]) — no cave structure carved")
	log_test("verdigris cave-gen FFI OK: [length(grid)] cells across [length(distinct)] distinct states")


/datum/unit_test/dq_expedition_generates_site

/datum/unit_test/dq_expedition_generates_site/Run()
	TEST_ASSERT_NOTNULL(SSexpedition, "SSexpedition is null — subsystem failed to initialize")

	var/pre_maxz = world.maxz
	var/datum/expedition_mission/mission = new /datum/expedition_mission/survey(EXP_DIFF_MED)
	var/datum/expedition_site/site = SSexpedition.generate_site(mission, EXP_DIFF_MED)

	TEST_ASSERT_NOTNULL(site, "generate_site() returned null — z-alloc, verdigris carve, or content scatter failed")
	TEST_ASSERT(world.maxz > pre_maxz, "world.maxz did not grow: [pre_maxz] -> [world.maxz]; load_new_z() allocated nothing")
	TEST_ASSERT_EQUAL(site.z_level, world.maxz, "site z-level [site.z_level] is not the newly-allocated top z [world.maxz]")

	// A walkable landing turf only exists if the carver actually opened floors.
	TEST_ASSERT_NOTNULL(site.landing, "site has no landing turf — carve produced no walkable floor (verdigris likely not loaded)")
	TEST_ASSERT(!site.landing.density, "landing turf is dense — not actually walkable")
	TEST_ASSERT_EQUAL(site.landing.z, site.z_level, "landing turf z [site.landing.z] != site z [site.z_level]")
	TEST_ASSERT_NULL(site.overmap_sector, "planet-bound site created a legacy space-sector marker")
	TEST_ASSERT(site.generation_seed > 0, "generated station did not retain a reproducible planner seed")
	TEST_ASSERT_NOTNULL(site.station_spec, "site did not retain its generated station specification")
	TEST_ASSERT_NOTNULL(site.station_materialization, "site did not retain its station materialization")
	TEST_ASSERT_EQUAL(site.landing, get_turf(site.station_materialization.entry), "landing does not use the generated docking entry")
	var/mining_spawners = 0
	for(var/turf/scan_turf in block(locate(1, 1, site.z_level), locate(world.maxx, world.maxy, site.z_level)))
		if(locate(/obj/structure/mob_spawner/scanner/mining_animals) in scan_turf)
			mining_spawners++
	TEST_ASSERT_EQUAL(mining_spawners, 0, "generated station inherited legacy cave mining-fauna spawners")
	TEST_ASSERT_NOTNULL(site.landing_waypoint, "generated site has no physical shuttle landing waypoint")
	TEST_ASSERT(site.mission.has_viable_objectives(), "generated site mission has no viable spawned objective content")

	// The site must be registered for later lookup.
	TEST_ASSERT(SSexpedition.sites["[site.z_level]"] == site, "site was not registered in SSexpedition.sites")

	// Count carved floors as a sanity signal on the cave gen.
	var/floor_count = 0
	for(var/turf/floor_turf in block(locate(1, 1, site.z_level), locate(world.maxx, world.maxy, site.z_level)))
		if(expedition_is_walkable(floor_turf))
			floor_count++
	TEST_ASSERT(floor_count > 50, "only [floor_count] walkable floors on the generated site — cave gen produced almost no open space")
	log_test("Expedition site generated on z[site.z_level] with [floor_count] walkable floor turfs.")


	SSexpedition.release_site(site, "expedition integration unit test")


/datum/unit_test/dq_debug_station_initializes_complete_runtime

/datum/unit_test/dq_debug_station_initializes_complete_runtime/Run()
	var/list/diagnostics = list()
	var/datum/generated_station_prng/seed_stream = new(20260721)
	var/seed = ((seed_stream.next() + 1) % 2147483646) + 1
	var/datum/expedition_site/site = SSexpedition.generate_debug_station(seed, diagnostics)
	TEST_ASSERT_NOTNULL(site, "Pseudo-random debug station seed [seed] failed: [jointext(diagnostics, "; ")]")
	qdel(seed_stream)
	TEST_ASSERT_NOTNULL(site.station_spec, "Debug station discarded its authoritative specification")
	TEST_ASSERT_EQUAL(site.station_spec.grid_width, 112, "Debug station did not use the expanded interactive generation footprint")
	TEST_ASSERT_EQUAL(site.station_spec.grid_height, 112, "Debug station did not use the expanded interactive generation footprint")
	var/list/modules_by_node = list()
	for(var/datum/generated_station_module/module in site.station_materialization.modules)
		modules_by_node[module.department_node_id] = (modules_by_node[module.department_node_id] || 0) + 1
		var/datum/generated_station_layout_node/module_node
		for(var/datum/generated_station_layout_node/candidate_node in site.station_spec.layout_nodes)
			if(candidate_node.id == module.department_node_id)
				module_node = candidate_node
				break
		var/datum/generated_station_department_instance/module_department
		for(var/datum/generated_station_department_instance/candidate_department in site.station_spec.departments)
			if(candidate_department.layout_node_id == module_node?.id)
				module_department = candidate_department
				break
		var/datum/generated_room_definition/module_definition = generated_room_definition_for(module_department?.definition?.id, module.role)
		TEST_ASSERT(module.satisfies(module_definition), "Expanded debug module [module.id] violates its [module_definition?.id] room contract at [module.width()]x[module.height()]")
		qdel(module_definition)
	for(var/datum/generated_station_layout_node/node in site.station_spec.layout_nodes)
		TEST_ASSERT_EQUAL(modules_by_node[node.id], 4, "Expanded debug department [node.id] did not generate four content-sized rooms")
	TEST_ASSERT_NOTNULL(site.station_simulation, "Debug station did not initialize dependency simulation")
	TEST_ASSERT_NOTNULL(site.station_director, "Debug station did not initialize its director")
	TEST_ASSERT_NOTNULL(site.station_defense, "Debug station did not initialize defenders")
	TEST_ASSERT(length(site.station_controls) >= 7, "Debug station did not create every department control")
	TEST_ASSERT_NOTNULL(site.landing, "Debug station has no teleport destination")
	var/datum/gas_mixture/landing_air = site.landing.return_air()
	TEST_ASSERT(landing_air?.return_pressure() > 80, "Debug station landing is not pressurized")
	var/mineral_exterior_count = 0
	for(var/turf/simulated/mineral/mineral_turf in block(locate(1, 1, site.z_level), locate(world.maxx, world.maxy, site.z_level)))
		mineral_exterior_count++
	TEST_ASSERT_EQUAL(mineral_exterior_count, 0, "Debug station z-level retained [mineral_exterior_count] mineral turfs around its hull")
	TEST_ASSERT(istype(locate(1, 1, site.z_level), /turf/space), "Debug station northwest map boundary is not vacuum")
	TEST_ASSERT(istype(locate(world.maxx, world.maxy, site.z_level), /turf/space), "Debug station southeast map boundary is not vacuum")
	var/datum/generated_station_validation_result/architecture = site.station_materialization.validate_architecture(site.station_spec)
	for(var/datum/generated_station_validation_issue/issue in architecture.issues)
		if(issue.severity == GENERATED_STATION_ISSUE_ERROR)
			TEST_FAIL("Post-runtime station architecture failed: [issue.code] at [issue.subject_id]: [issue.message]")
	TEST_ASSERT(architecture.is_valid(), "Debug station became architecturally invalid after runtime controls and defenders initialized")
	rustg_file_write(site.station_materialization.diagnostic_minimap_html(architecture), "[GLOB.log_directory]/generated-station-large-[seed].html")
	qdel(architecture)
	SSexpedition.release_site(site, "debug station unit test")


/// Models exterior vacuum against live turf and atom density. The result remains
/// inspectable so the negative fixture can prove that opening a hull door fails.
/datum/unit_test/dq_generated_station_physical_regressions/proc/vacuum_findings(datum/expedition_site/site)
	var/list/findings = list("reached_floor" = null, "enclosed_space" = null)
	var/list/exterior = list()
	var/list/frontier = list()
	for(var/x in 1 to world.maxx)
		frontier |= locate(x, 1, site.z_level)
		frontier |= locate(x, world.maxy, site.z_level)
	for(var/y in 1 to world.maxy)
		frontier |= locate(1, y, site.z_level)
		frontier |= locate(world.maxx, y, site.z_level)
	while(length(frontier))
		var/turf/current = frontier[length(frontier)]
		frontier.len--
		if(exterior[current] || current.density)
			continue
		var/blocked = FALSE
		for(var/atom/movable/blocker in current)
			if(blocker.density)
				blocked = TRUE
				break
		if(blocked)
			continue
		exterior[current] = TRUE
		if(istype(get_area(current), /area/generated_station) && istype(current, /turf/simulated/floor))
			findings["reached_floor"] = current
			return findings
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(current, direction)
			if(neighbor && !exterior[neighbor])
				frontier += neighbor
	for(var/turf/space/space_turf in block(locate(1, 1, site.z_level), locate(world.maxx, world.maxy, site.z_level)))
		if(!exterior[space_turf])
			findings["enclosed_space"] = space_turf
			return findings
	return findings

/datum/unit_test/dq_generated_station_physical_regressions/proc/assert_vacuum_seal(datum/expedition_site/site, seed)
	var/list/findings = vacuum_findings(site)
	var/turf/reached_floor = findings["reached_floor"]
	var/turf/enclosed_space = findings["enclosed_space"]
	TEST_ASSERT_NULL(reached_floor, "Seed [seed] hull admits exterior vacuum to generated floor [reached_floor ? generated_station_coordinate(reached_floor) : "none"]")
	TEST_ASSERT_NULL(enclosed_space, "Seed [seed] contains enclosed, unclassified space at [enclosed_space ? generated_station_coordinate(enclosed_space) : "none"]")

/datum/unit_test/dq_generated_station_physical_regressions/proc/assert_structure(datum/expedition_site/site, seed)
	var/list/owned_modules = list()
	for(var/datum/generated_station_module/module in site.station_materialization.modules)
		for(var/x in module.x1 to module.x2)
			for(var/y in module.y1 to module.y2)
				if(!module.contains_tile(x, y))
					continue
				var/key = "[x],[y]"
				TEST_ASSERT(!owned_modules[key], "Seed [seed] has overlapping room ownership at [key]")
				owned_modules[key] = "[module.department_node_id]/[module.id]"
	var/list/structural_areas = list(site.station_materialization.transit_area)
	for(var/node_id in site.station_materialization.department_areas)
		structural_areas += site.station_materialization.department_areas[node_id]
	for(var/area/generated_station/station_area in structural_areas)
		for(var/turf/simulated/wall/wall in station_area)
			var/adjacent_floor = FALSE
			var/cardinal_walls = 0
			var/surrounding_walls = 0
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor = get_step(wall, direction)
				if(istype(neighbor, /turf/simulated/floor))
					adjacent_floor = TRUE
				else if(istype(neighbor, /turf/simulated/wall))
					cardinal_walls++
			for(var/turf/simulated/wall/nearby_wall in orange(1, wall))
				surrounding_walls++
			TEST_ASSERT(surrounding_walls < 8, "Seed [seed] has a buried 3x3 wall center at [generated_station_coordinate(wall)]")
			TEST_ASSERT(adjacent_floor || cardinal_walls, "Seed [seed] has an orphan wall at [generated_station_coordinate(wall)]")
	for(var/obj/machinery/door/door in site.station_materialization.doors)
		var/turf/door_turf = get_turf(door)
		TEST_ASSERT(istype(door_turf, /turf/simulated/floor), "Seed [seed] door occupies non-floor [generated_station_coordinate(door)]")
		for(var/atom/movable/occupant in door_turf)
			if(occupant != door)
				TEST_ASSERT(!occupant.density && !istype(occupant, /obj/machinery/power/apc) && !istype(occupant, /obj/machinery/alarm), "Seed [seed] door shares its tile with [occupant.type] at [generated_station_coordinate(door)]")

/datum/unit_test/dq_generated_station_physical_regressions/proc/assert_utilities(datum/expedition_site/site, seed)
	var/datum/generated_station_utility_topology/topology = site.station_utilities
	TEST_ASSERT_NOTNULL(topology, "Seed [seed] has no physical utility topology")
	TEST_ASSERT(topology.power_network_is_global(), "Seed [seed] APCs do not share the station power grid")
	TEST_ASSERT(topology.atmosphere_networks_are_global(), "Seed [seed] atmos devices do not share station mains: [topology.atmosphere_network_break_summary()]")
	for(var/module_id in site.station_materialization.module_areas)
		var/area/generated_station/station_area = site.station_materialization.module_areas[module_id]
		var/apcs = 0
		var/vents = 0
		var/scrubbers = 0
		var/alarms = 0
		var/lights = 0
		var/floors = 0
		for(var/turf/simulated/floor/floor in station_area)
			floors++
			for(var/obj/machinery/power/apc/APC in floor)
				apcs++
				TEST_ASSERT_NOTNULL(APC.terminal?.powernet, "Seed [seed] [module_id] APC lacks a live terminal powernet")
			for(var/obj/machinery/atmospherics/unary/vent_pump/vent in floor)
				vents++
				TEST_ASSERT_NOTNULL(vent.network, "Seed [seed] [module_id] vent lacks a pipenet")
			for(var/obj/machinery/atmospherics/unary/vent_scrubber/scrubber in floor)
				scrubbers++
				TEST_ASSERT_NOTNULL(scrubber.network, "Seed [seed] [module_id] scrubber lacks a pipenet")
			for(var/obj/machinery/alarm/alarm in floor)
				alarms++
			for(var/obj/machinery/light/light in floor)
				lights++
		station_area.power_change()
		TEST_ASSERT_EQUAL(apcs, 1, "Seed [seed] [module_id] has [apcs] APCs instead of one")
		TEST_ASSERT(vents >= 1, "Seed [seed] [module_id] has no supply vent")
		TEST_ASSERT(scrubbers >= 1, "Seed [seed] [module_id] has no scrubber")
		TEST_ASSERT(alarms >= 1, "Seed [seed] [module_id] has no air alarm")
		TEST_ASSERT(lights >= max(1, round(floors / 80)), "Seed [seed] [module_id] has only [lights] lights for [floors] floors")
		TEST_ASSERT(station_area.powered(LIGHT), "Seed [seed] [module_id] lighting circuit is unpowered")

/datum/unit_test/dq_generated_station_physical_regressions/proc/pressure_context(turf/simulated/floor)
	var/list/parts = list("area=[get_area(floor)?.type]")
	for(var/atom/movable/occupant in floor)
		parts += "occupant=[occupant.type]/dense=[occupant.density]"
	for(var/direction in GLOB.cardinal)
		var/turf/neighbor = get_step(floor, direction)
		parts += "dir=[direction]:[neighbor?.type]/dense=[neighbor?.density]/pressure=[neighbor?.return_air()?.return_pressure()]"
	return jointext(parts, ", ")

/datum/unit_test/dq_generated_station_physical_regressions

/datum/unit_test/dq_generated_station_physical_regressions/Run()
	var/datum/generated_station_prng/seed_stream = new(20260722)
	for(var/sample in 1 to 8)
		var/seed = ((seed_stream.next() + sample) % 2147483646) + 1
		var/list/diagnostics = list()
		var/datum/expedition_site/site = SSexpedition.generate_debug_station(seed, diagnostics)
		TEST_ASSERT_NOTNULL(site, "Pseudo-random runtime sample [sample] seed [seed] failed: [jointext(diagnostics, "; ")]")
		TEST_ASSERT_EQUAL(length(site.station_materialization.degradation_events), 0, "Seed [seed] required materialization degradation: [jointext(site.station_materialization.degradation_events, "; ")]")
		for(var/datum/generated_room_solution/solution in site.station_materialization.room_solutions)
			TEST_ASSERT(!findtext(solution.definition_id, "-minimum-"), "Seed [seed] room [solution.module_id] fell back to [solution.definition_id]")
			var/authored_fixture_count = length(solution.placements)
			for(var/datum/generated_room_fragment_placement/fragment_placement in solution.fragments)
				var/datum/generated_room_fragment/activity_motif/motif = fragment_placement.fragment
				if(istype(motif))
					authored_fixture_count += length(motif.feature_types)
			TEST_ASSERT(authored_fixture_count >= 2, "Seed [seed] room [solution.module_id] has fewer than two authored fixtures")
			TEST_ASSERT(solution.occupied_tiles >= max(2, FLOOR(solution.floor_tiles * 0.12, 1)), "Seed [seed] room [solution.module_id] leaves nearly all [solution.floor_tiles] floor tiles empty")
		assert_structure(site, seed)
		assert_vacuum_seal(site, seed)
		assert_utilities(site, seed)
		var/list/initial_pressures = list()
		for(var/node_id in site.station_materialization.department_areas)
			var/area/generated_station/station_area = site.station_materialization.department_areas[node_id]
			for(var/turf/simulated/floor/floor in station_area)
				var/initial_pressure = floor.return_air()?.return_pressure()
				TEST_ASSERT(isnum(initial_pressure) && initial_pressure > 80, "Seed [seed] floor [generated_station_coordinate(floor)] starts unpressurized")
				initial_pressures[floor] = initial_pressure
		stoplag(20)
		for(var/turf/simulated/floor/floor as anything in initial_pressures)
			var/initial_pressure = initial_pressures[floor]
			var/final_pressure = floor.return_air()?.return_pressure()
			TEST_ASSERT(isnum(final_pressure) && final_pressure > 80, "Seed [seed] floor [generated_station_coordinate(floor)] became unpressurized: [pressure_context(floor)]")
			TEST_ASSERT(abs(final_pressure - initial_pressure) < 5, "Seed [seed] floor [generated_station_coordinate(floor)] changed pressure by [abs(final_pressure - initial_pressure)] kPa at rest")
		var/obj/machinery/door/airlock/generated_station_exterior/test_door = locate(/obj/machinery/door/airlock/generated_station_exterior) in site.station_materialization.doors
		TEST_ASSERT_NOTNULL(test_door, "Seed [seed] lacks an exterior airlock for seal falsifiability")
		var/original_density = test_door.density
		test_door.density = FALSE
		var/list/open_door_findings = vacuum_findings(site)
		TEST_ASSERT_NOTNULL(open_door_findings["reached_floor"], "Seed [seed] vacuum audit accepted a deliberately opened exterior airlock")
		test_door.density = original_density
		SSexpedition.release_site(site, "generated station physical regression unit test")
	qdel(seed_stream)


/datum/unit_test/dq_expedition_threat_band_values

/datum/unit_test/dq_expedition_threat_band_values/Run()
	var/list/threat_bands = expedition_threat_bands()
	for(var/label in threat_bands)
		var/difficulty = threat_bands[label]
		TEST_ASSERT(isnum(difficulty), "Threat band '[label]' resolved to non-numeric value '[difficulty]'")
		var/datum/expedition_mission/mission = new /datum/expedition_mission(difficulty)
		TEST_ASSERT_EQUAL(mission.difficulty, difficulty, "Threat band '[label]' was not passed numerically to the mission")
		qdel(mission)


/datum/unit_test/dq_expedition_assignment_prevents_ready_expiry

/datum/unit_test/dq_expedition_assignment_prevents_ready_expiry/Run()
	var/datum/expedition_site/site = new(world.maxz + 1, EXP_DIFF_LOW)
	var/obj/machinery/computer/shuttle_control/explore/console = new(null)
	site.origin_console = console
	console.active_expedition = site
	TEST_ASSERT(site.has_active_assignment(), "A site owned by its origin console was not recognized as actively assigned")
	site.status = EXP_STATUS_ACTIVE
	site.deployed_at = world.time - EXP_DEPLOY_GRACE - 1
	site.last_occupied = world.time - EXP_AUTO_RELEASE_GRACE - 1
	SSexpedition.sites["assignment-lifecycle-test"] = site
	SSexpedition.fire()
	TEST_ASSERT(SSexpedition.sites["assignment-lifecycle-test"] == site, "An empty active site was released while its incomplete assignment was still held by the shuttle console")
	SSexpedition.sites -= "assignment-lifecycle-test"

	console.active_expedition = null
	TEST_ASSERT(!site.has_active_assignment(), "A site remained actively assigned after its console released it")
	qdel(console)
	qdel(site)
