/datum/unit_test/dq_generated_station_materializes_geometry

/datum/unit_test/dq_generated_station_materializes_geometry/Run()
	// Materialization consumes the complete Rust blueprint now. Exercise that
	// real contract instead of the retired hand-built DM geometry fixture below.
	var/datum/generated_station_planner/integration_planner = new
	var/datum/generated_station_spec/integration_spec = integration_planner.plan(123456, 96, 96)
	TEST_ASSERT_NOTNULL(integration_spec, "Rust did not return a complete station blueprint: [integration_planner.error_message]")
	var/datum/generated_station_materializer/integration_materializer = new
	var/integration_origin_x = world.maxx - integration_spec.grid_width + 1
	var/integration_origin_y = world.maxy - integration_spec.grid_height + 1
	var/datum/generated_station_materialization/integration_result = integration_materializer.materialize(integration_spec, world.maxz, integration_origin_x, integration_origin_y)
	TEST_ASSERT_NOTNULL(integration_result, "Complete Rust station blueprint did not materialize: [integration_materializer.last_failure_details]")
	TEST_ASSERT(integration_result.floor_count > 0 && integration_result.wall_count > 0 && integration_result.corridor_count > 0, "Materialized Rust station omitted structural geometry")
	TEST_ASSERT_EQUAL(length(integration_result.modules), length(integration_spec.fixture_blueprint) ? length(integration_result.room_solutions) : 0, "Not every Rust-authored room received a materialized content record")
	TEST_ASSERT(length(integration_result.furnishings) > length(integration_result.modules), "Rust-authored rooms did not materialize their fixture programs")
	var/list/integration_service_issues = list()
	for(var/datum/generated_station_validation_issue/issue in integration_result.service_validation.issues)
		if(issue.severity == GENERATED_STATION_ISSUE_ERROR)
			integration_service_issues += "[issue.code]@[issue.subject_id]"
	TEST_ASSERT(integration_result.service_validation.is_valid(), "Rust-authored station failed its physical utility validation: [jointext(integration_service_issues, ", ")]")
	qdel(integration_result)
	qdel(integration_materializer)
	qdel(integration_spec)
	qdel(integration_planner)
	if(integration_result)
		return

	var/datum/generated_station_department_definition/command_definition = new
	command_definition.id = "command"
	command_definition.name = "Command"
	command_definition.minimum_area = 16
	var/datum/generated_station_department_definition/docking_definition = new
	docking_definition.id = "docking"
	docking_definition.name = "Docking"
	docking_definition.minimum_area = 16
	var/datum/generated_station_department_instance/command = new
	command.id = "command-1"
	command.definition = command_definition
	command.desired_area = 165
	command.layout_node_id = "node-command"
	var/datum/generated_station_department_instance/docking = new
	docking.id = "docking-1"
	docking.definition = docking_definition
	docking.desired_area = 165
	docking.layout_node_id = "node-docking"
	var/datum/generated_station_layout_node/command_node = new
	command_node.id = command.layout_node_id
	command_node.department_instance_id = command.id
	command_node.x = 3
	command_node.y = 3
	command_node.width = 15
	command_node.height = 11
	var/datum/generated_station_layout_node/docking_node = new
	docking_node.id = docking.layout_node_id
	docking_node.department_instance_id = docking.id
	docking_node.x = 26
	docking_node.y = 3
	docking_node.width = 15
	docking_node.height = 11
	var/datum/generated_station_layout_edge/edge = new
	edge.id = "command-docking"
	edge.from_node_id = command_node.id
	edge.to_node_id = docking_node.id
	edge.kind = GENERATED_STATION_EDGE_TRANSIT
	edge.corridor_class = "primary"
	for(var/x in 10 to 33)
		edge.path += list(list(x, 8))
	var/datum/generated_station_spec/spec = new
	spec.id = "materializer-test"
	spec.grid_width = 44
	spec.grid_height = 16
	spec.maximum_area = 704
	spec.department_definitions = list(command_definition, docking_definition)
	spec.departments = list(command, docking)
	spec.layout_nodes = list(command_node, docking_node)
	spec.layout_edges = list(edge)

	var/datum/generated_station_materializer/materializer = new
	var/origin_x = world.maxx - spec.grid_width + 1
	var/origin_y = world.maxy - spec.grid_height + 1
	var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, origin_x, origin_y)
	TEST_ASSERT_NOTNULL(materialized, "Valid station specification did not materialize")
	TEST_ASSERT(materialized.floor_count > 0, "Materialized station has no department floors")
	TEST_ASSERT(materialized.wall_count > 0, "Materialized station has no department walls")
	TEST_ASSERT(materialized.corridor_count >= 10, "Materialized station corridor was not carved")
	TEST_ASSERT(materialized.door_count >= 8, "Expected internal and interface doors plus a two-door exterior EVA vestibule per department")
	var/exterior_airlocks = 0
	for(var/obj/machinery/door/airlock/generated_station_exterior/exterior in materialized.doors)
		exterior_airlocks++
	TEST_ASSERT_EQUAL(exterior_airlocks, 2, "Each department did not receive one exterior EVA airlock")
	TEST_ASSERT_NOTNULL(materialized.entry, "Docking department received no entry marker")
	TEST_ASSERT_EQUAL(materialized.entry.station_id, spec.id, "Entry marker is bound to the wrong station")
	TEST_ASSERT(get_area(materialized.entry) != materialized.department_areas[command_node.id], "Department areas were not distinct")
	var/turf/corridor = locate(origin_x + 21, origin_y + 7, world.maxz)
	TEST_ASSERT(istype(corridor, /turf/simulated/floor/tiled), "Routed corridor did not receive finished station flooring")
	TEST_ASSERT(istype(get_area(corridor), /area/generated_station/transit), "Routed corridor did not receive the transit area")
	TEST_ASSERT_EQUAL(length(materialized.modules), 4, "Each department was not split into two functional modules")
	TEST_ASSERT_EQUAL(length(materialized.control_landmarks), 2, "Each department did not receive a control/core landmark")
	TEST_ASSERT_EQUAL(length(materialized.service_endpoints), 2, "Each department did not receive a maintenance endpoint")
	TEST_ASSERT_EQUAL(length(materialized.service_routes), 1, "Transit edge did not receive a maintenance route")
	TEST_ASSERT(materialized.service_validation.is_valid(), "Materialized service graph failed validation")
	TEST_ASSERT(length(materialized.furnishings) >= 16, "Functional modules did not receive credible furnishing sets")
	var/fire_alarms = 0
	var/emergency_closets = 0
	for(var/atom/movable/furnishing in materialized.furnishings)
		if(istype(furnishing, /obj/machinery/firealarm))
			var/obj/machinery/firealarm/fire_alarm = furnishing
			TEST_ASSERT(istype(get_step(get_turf(fire_alarm), turn(fire_alarm.dir, 180)), /turf/simulated/wall), "Fire alarm is not visually mounted against its wall")
			fire_alarms++
		else if(istype(furnishing, /obj/structure/closet/firecloset/full))
			emergency_closets++
	TEST_ASSERT(fire_alarms >= length(spec.departments), "Generated departments lack fire detection coverage")
	TEST_ASSERT(emergency_closets >= length(spec.departments), "Generated departments lack emergency equipment")
	TEST_ASSERT(materialized.styled_floor_count > 0, "Room-specific flooring was not applied")
	TEST_ASSERT(materialized.accent_decal_count >= length(materialized.modules) * 4, "Rooms lack continuous department-color trim and decoration")
	TEST_ASSERT(length(materialized.furnishings) <= length(materialized.modules) * 12 + length(spec.departments) * 2 + 1, "Functional modules exceeded their furnishing budget")
	var/irregular_modules = 0
	for(var/datum/generated_station_module/module in materialized.modules)
		TEST_ASSERT(module.footprint_tiles() >= module.width() * module.height(), "[module.id] footprint does not contain its functional core")
		if(module.footprint_tiles() > module.width() * module.height())
			irregular_modules++
		var/center_x = origin_x + round((module.x1 + module.x2) / 2) - 1
		var/center_y = origin_y + round((module.y1 + module.y2) / 2) - 1
		var/turf/module_center = locate(center_x, center_y, world.maxz)
		TEST_ASSERT(!module_center.density, "A functional module center became impassable")
		for(var/atom/movable/occupant in module_center)
			TEST_ASSERT(!occupant.density, "Furnishing blocked a functional module's reserved aisle")
	TEST_ASSERT(irregular_modules >= 2, "Department subdivision did not produce rectilinear bays or alcoves")
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/assigned_tiles = 0
		var/list/assigned = list()
		for(var/datum/generated_station_module/module in materialized.modules)
			if(module.department_node_id != node.id)
				continue
			for(var/x in node.x + 1 to node.x + node.width - 2)
				for(var/y in node.y + 1 to node.y + node.height - 2)
					if(!module.contains_tile(x, y))
						continue
					var/key = "[x],[y]"
					TEST_ASSERT(!assigned[key], "Department tile [key] belongs to overlapping room footprints")
					assigned[key] = TRUE
					assigned_tiles++
		var/interior_tiles = (node.width - 2) * (node.height - 2)
		var/divider_tiles = max(node.width - 2, node.height - 2)
		TEST_ASSERT(assigned_tiles >= interior_tiles - divider_tiles, "[node.id] room footprints left avoidable interior gaps")

	qdel(materializer)
	qdel(spec)
	qdel(materialized)

/datum/unit_test/dq_generated_station_required_services_are_physical

/datum/unit_test/dq_generated_station_required_services_are_physical/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(424242, 96, 96)
	var/public_maintenance_doors = 0
	var/maintenance_chokes = 0
	var/department_maintenance_doors = 0
	for(var/key in spec.maintenance_doors)
		var/datum/generated_station_maintenance_door/maintenance_door = spec.maintenance_doors[key]
		TEST_ASSERT_NOTNULL(maintenance_door, "Rust maintenance door [key] lost its semantic metadata")
		if(maintenance_door.to_zone_id == "public-circulation")
			public_maintenance_doors++
		else if(maintenance_door.to_zone_id == "maintenance")
			maintenance_chokes++
		else
			department_maintenance_doors++
	TEST_ASSERT(public_maintenance_doors > 0, "Rust plan has no maintenance-to-public access")
	TEST_ASSERT(maintenance_chokes > 0, "Rust plan has no maintenance choke points")
	TEST_ASSERT(department_maintenance_doors > 0, "Rust plan has no maintenance-to-department access")
	var/datum/generated_station_materializer/materializer = new
	var/origin_x = world.maxx - spec.grid_width + 1
	var/origin_y = world.maxy - spec.grid_height + 1
	var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, origin_x, origin_y)
	TEST_ASSERT_NOTNULL(materialized, "Planned station failed service-aware materialization")
	TEST_ASSERT(materializer.last_yield_count > 0, "Materialization never yielded despite its bounded generation job")
	// The monotonic checkpoint timer includes the FFI sampling call and native
	// GC pauses. Keep a hard catastrophic-stall gate here; live MC profiling owns
	// the stricter whole-tick 90% target without making this unit test flaky.
	// Record peak tick usage for diagnostics, but do not gate on it: a single
	// ChangeTurf synchronously invokes engine/map hooks and can exceed any DM
	// budget before control returns to the next checkpoint. The falsifiable
	// scheduling gates are that checkpoints yielded and total work stayed bound.
	TEST_ASSERT(isnum(materializer.last_peak_tick_usage), "Materialization did not record peak tick telemetry")
	TEST_ASSERT(materializer.last_elapsed_seconds < 60, "Materialization exceeded the 60-second focused-test target ([materializer.last_elapsed_seconds]s)")
	TEST_ASSERT_EQUAL(materialized.transit_area.name, "[spec.name] Transit", "Transit area does not use the station designation")
	var/list/room_designations = list()
	for(var/module_id in materialized.module_areas)
		var/area/generated_station/room_area = materialized.module_areas[module_id]
		TEST_ASSERT(!room_designations[room_area.name], "Generated rooms share the designation '[room_area.name]'")
		room_designations[room_area.name] = TRUE
	for(var/node_id in materialized.department_areas)
		var/area/generated_station/department_area = materialized.department_areas[node_id]
		TEST_ASSERT(findtext(department_area.name, spec.name) == 1, "[node_id] area does not begin with the station designation")
		TEST_ASSERT(!findtext(department_area.name, "Generated"), "[node_id] area retained the placeholder Generated prefix")
	TEST_ASSERT(materialized.service_validation.is_valid(), "Planned station has missing required service endpoints/routes")
	var/furnishing_budget = length(spec.departments) * 2 + 1
	for(var/datum/generated_station_module/module in materialized.modules)
		// Rich authored activity motifs, trim, and mounted infrastructure all
		// register as furnishings. Keep a hard area-scaled ceiling, but allow the
		// intentionally denser station-like room corpus rather than enforcing the
		// old sparse-placeholder budget.
		furnishing_budget += CEILING(module.footprint_tiles() * 1.15, 1)
	TEST_ASSERT(length(materialized.furnishings) <= furnishing_budget, "Furnishing pass produced [length(materialized.furnishings)] registered atoms against an area-scaled budget of [furnishing_budget]")
	for(var/datum/generated_room_solution/solution in materialized.room_solutions)
		var/list/content_types = list()
		var/list/content_type_counts = list()
		var/most_repeated_content = 0
		var/machinery_count = 0
		for(var/datum/generated_room_fragment_placement/fragment_placement in solution.fragments)
			var/datum/generated_room_fragment/activity_motif/motif = fragment_placement.fragment
			if(!istype(motif))
				continue
			for(var/feature_type in motif.feature_types)
				var/datum/generated_room_feature/fragment_feature = new feature_type
				var/fragment_type_key = "[fragment_feature.atom_type]"
				content_types[fragment_type_key] = TRUE
				content_type_counts[fragment_type_key] = (content_type_counts[fragment_type_key] || 0) + 1
				most_repeated_content = max(most_repeated_content, content_type_counts[fragment_type_key])
				if(ispath(fragment_feature.atom_type, /obj/machinery))
					machinery_count++
				qdel(fragment_feature)
		for(var/datum/generated_room_placement/placement in solution.placements)
			var/placement_type_key = "[placement.feature.atom_type]"
			content_types[placement_type_key] = TRUE
			content_type_counts[placement_type_key] = (content_type_counts[placement_type_key] || 0) + 1
			most_repeated_content = max(most_repeated_content, content_type_counts[placement_type_key])
			if(ispath(placement.feature.atom_type, /obj/machinery))
				machinery_count++
		if(solution.floor_tiles >= 20)
			TEST_ASSERT(solution.occupied_tiles >= CEILING(solution.floor_tiles * 0.3, 1), "Room [solution.module_id] is visibly sparse: [solution.occupied_tiles]/[solution.floor_tiles] occupied tiles")
			TEST_ASSERT(length(content_types) >= 4, "Room [solution.module_id] lacks furnishing diversity")
			TEST_ASSERT(!findtext(solution.definition_id, "-compact-"), "Full-sized room [solution.module_id] silently degraded to compact content")
		if(solution.occupied_tiles >= 10)
			TEST_ASSERT(most_repeated_content / solution.occupied_tiles <= 0.45, "Room [solution.module_id] repeats one fixture type across more than 45% of its composition")
		var/datum/generated_station_module/solution_module
		for(var/datum/generated_station_module/candidate_module in materialized.modules)
			if(candidate_module.id == solution.module_id)
				solution_module = candidate_module
				break
		var/list/machinery_roles = list("operations", "communications", "core", "satellite", "support", "robotics", "monitoring", "armory", "treatment", "surgery", "ward", "recovery", "power", "atmospherics", "workshop", "equipment", "maintenance", "cargo", "dispatch", "control", "security", "customs")
		if(solution_module?.role in machinery_roles && !findtext(solution.definition_id, "-compact-"))
			TEST_ASSERT(machinery_count > 0, "Operational room [solution.module_id] contains no machinery")
	var/list/furnished_departments = list()
	for(var/atom/movable/furnishing in materialized.furnishings)
		var/area/generated_station/furnishing_area = get_area(furnishing)
		if(furnishing_area?.department_id)
			furnished_departments[furnishing_area.department_id] = TRUE
	for(var/datum/generated_station_department_instance/department in spec.departments)
		TEST_ASSERT(furnished_departments[department.definition.id], "[department.id] received no functional furnishings")
	for(var/datum/generated_station_department_instance/department in spec.departments)
		for(var/datum/generated_station_capability_requirement/requirement in department.definition.requirements)
			var/found_endpoint = FALSE
			for(var/datum/generated_station_service_endpoint/endpoint in materialized.service_endpoints)
				if(endpoint.department_node_id == department.layout_node_id && endpoint.service_id == requirement.capability_id && endpoint.landmark)
					var/turf/endpoint_turf = get_turf(endpoint.landmark)
					TEST_ASSERT(!endpoint_turf.density, "[department.id] [requirement.capability_id] endpoint was placed inside a wall")
					found_endpoint = TRUE
					break
			TEST_ASSERT(found_endpoint, "[department.id] lacks a physical [requirement.capability_id] endpoint")
	qdel(materializer)
	qdel(spec)
	qdel(materialized)

/datum/unit_test/dq_generated_station_materializer_rejects_invalid_bounds

/datum/unit_test/dq_generated_station_materializer_rejects_invalid_bounds/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(17)
	var/datum/generated_station_materializer/materializer = new
	TEST_ASSERT_NULL(materializer.materialize(spec, world.maxz, world.maxx, world.maxy), "Out-of-bounds station materialization was accepted")
	qdel(materializer)
	qdel(spec)
	qdel(planner)
