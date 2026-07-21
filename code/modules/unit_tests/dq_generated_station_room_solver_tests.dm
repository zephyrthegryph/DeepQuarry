/datum/unit_test/dq_generated_room_solver_is_deterministic

/datum/unit_test/dq_generated_room_solver_is_deterministic/Run()
	var/origin_x = world.maxx - 14
	var/origin_y = world.maxy - 12
	for(var/x in origin_x to origin_x + 11)
		for(var/y in origin_y to origin_y + 9)
			var/turf/T = locate(x, y, world.maxz)
			T.ChangeTurf(/turf/simulated/floor/plating, tell_universe = FALSE)
	var/datum/generated_station_materializer/materializer = new
	materializer.min_x = origin_x
	materializer.min_y = origin_y
	materializer.z_level = world.maxz
	var/datum/generated_station_module/module = new
	module.id = "test-reception"
	module.department_node_id = "test-command"
	module.role = "operations"
	module.x1 = 2
	module.y1 = 2
	module.x2 = 11
	module.y2 = 9
	var/datum/generated_room_definition/reception/definition = new
	var/datum/generated_room_solver/first_solver = new
	var/datum/generated_room_solution/first = first_solver.solve(materializer, module, definition, 445566, "corporate", "sterile")
	var/datum/generated_room_solver/second_solver = new
	var/datum/generated_room_solution/second = second_solver.solve(materializer, module, definition, 445566, "corporate", "sterile")
	TEST_ASSERT(first?.valid && second?.valid, "Reception room constraint solver rejected a spacious valid shell")
	TEST_ASSERT_EQUAL(length(first.fragments), 1, "Reception room did not select its authored corner fragment")
	TEST_ASSERT_EQUAL(length(first.placements), length(second.placements), "Same room seed produced different feature counts")
	for(var/i in 1 to length(first.placements))
		var/datum/generated_room_placement/a = first.placements[i]
		var/datum/generated_room_placement/b = second.placements[i]
		TEST_ASSERT(a.feature.id == b.feature.id && a.x == b.x && a.y == b.y && a.dir == b.dir, "Same room seed produced a different placement at index [i]")
		TEST_ASSERT(!first.door_circulation[first.tile_key(a.x, a.y)], "Feature '[a.feature.id]' blocks reserved door circulation")
		if(ispath(a.feature.atom_type, /obj/structure/bed/chair))
			var/turf/chair_turf = materializer.world_turf(a.x, a.y)
			TEST_ASSERT(!get_step(chair_turf, a.dir)?.density, "Chair '[a.feature.id]' faces into a wall")
	qdel(first)
	qdel(second)
	qdel(first_solver)
	qdel(second_solver)
	qdel(definition)
	qdel(module)
	qdel(materializer)

/datum/unit_test/dq_generated_room_fragment_materializes_real_content

/datum/unit_test/dq_generated_room_fragment_materializes_real_content/Run()
	var/origin_x = world.maxx - 14
	var/origin_y = world.maxy - 12
	var/turf/origin = locate(origin_x, origin_y, world.maxz)
	for(var/turf/T in block(origin, locate(origin_x + 4, origin_y + 3, world.maxz)))
		for(var/atom/movable/existing in T)
			qdel(existing)
		T.ChangeTurf(/turf/simulated/floor/plating, tell_universe = FALSE)
	stoplag(1)
	var/datum/generated_station_materialization/owner = new
	var/datum/generated_room_fragment/reception_corner/fragment = new
	TEST_ASSERT(fragment.materialize(origin, 0, FALSE, owner), "Reception .dmm fragment did not load any authored atoms")
	TEST_ASSERT(length(owner.furnishings) >= 5, "Reception fragment did not register its counter and seating with station ownership")
	var/chairs = 0
	var/tables = 0
	var/access_doors = 0
	for(var/atom/movable/furnishing in owner.furnishings)
		if(istype(furnishing, /obj/structure/bed/chair))
			chairs++
		else if(istype(furnishing, /obj/structure/table))
			tables++
		else if(istype(furnishing, /obj/machinery/door/window))
			access_doors++
	TEST_ASSERT(chairs >= 1 && tables >= 3 && access_doors >= 1, "Reception fragment did not contain a recognizable staffed counter and access door (chairs [chairs], tables [tables], doors [access_doors])")
	qdel(fragment)
	qdel(owner)

/datum/unit_test/dq_generated_station_content_random_materializations

/datum/unit_test/dq_generated_station_content_random_materializations/Run()
	var/datum/generated_station_prng/seed_stream = new(202607181)
	var/list/gallery = list("<html><body style='background:#111;color:#ddd'><h1>Generated station content gallery</h1><ul>")
	for(var/sample in 1 to 4)
		var/seed = seed_stream.next()
		var/datum/generated_station_planner/planner = new
		var/datum/generated_station_spec/spec = planner.plan(seed, 96, 96)
		TEST_ASSERT_NOTNULL(spec, "Random content sample [sample] produced no Rust station plan")
		var/datum/generated_station_materializer/materializer = new
		var/origin_x = max(1, round((world.maxx - spec.grid_width) / 2))
		var/origin_y = max(1, round((world.maxy - spec.grid_height) / 2))
		var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, origin_x, origin_y)
		TEST_ASSERT_NOTNULL(materialized, "Random content sample [sample] failed DM materialization: [materializer.last_failure_details]")
		var/large_rooms = 0
		var/machinery = 0
		for(var/datum/generated_room_solution/solution in materialized.room_solutions)
			var/list/content_types = list()
			var/list/content_paths = list()
			for(var/datum/generated_room_fragment_placement/fragment_placement in solution.fragments)
				var/datum/generated_room_fragment/activity_motif/motif = fragment_placement.fragment
				if(!istype(motif))
					continue
				for(var/feature_type in motif.feature_types)
					var/datum/generated_room_feature/fragment_feature = new feature_type
					content_types["[fragment_feature.atom_type]"] = TRUE
					content_paths |= fragment_feature.atom_type
					if(ispath(fragment_feature.atom_type, /obj/machinery))
						machinery++
					qdel(fragment_feature)
			for(var/datum/generated_room_placement/placement in solution.placements)
				content_types["[placement.feature.atom_type]"] = TRUE
				content_paths |= placement.feature.atom_type
				if(ispath(placement.feature.atom_type, /obj/machinery))
					machinery++
			var/compact_solution = findtext(solution.definition_id, "-compact")
			if(compact_solution)
				TEST_ASSERT(length(content_types) >= 2, "Compact random room [solution.module_id] collapsed to a token fixture")
			else
				large_rooms++
				TEST_ASSERT(solution.occupied_tiles >= CEILING(solution.floor_tiles * 0.22, 1), "Random room [solution.module_id] is visibly sparse")
				TEST_ASSERT(length(content_types) >= 3, "Random room [solution.module_id] lacks visual diversity")
			var/datum/generated_station_module/module
			for(var/datum/generated_station_module/candidate in materialized.modules)
				if(candidate.id == solution.module_id)
					module = candidate
					break
			var/department_id = materializer.department_id_for_module(module)
			TEST_ASSERT(!findtext(solution.definition_id, "-minimum-"), "Random content sample [sample] room [solution.module_id] degraded to [solution.definition_id]")
			for(var/required_type in generated_room_required_signature(department_id, module?.role, compact_solution))
				var/found_signature = FALSE
				for(var/content_type in content_paths)
					if(ispath(content_type, required_type))
						found_signature = TRUE
						break
				if(!found_signature)
					var/area/generated_station/module_area = materialized.module_areas[module?.id]
					for(var/atom/movable/furnishing in materialized.furnishings)
						if(istype(furnishing, required_type) && get_area(furnishing) == module_area)
							found_signature = TRUE
							break
				TEST_ASSERT(found_signature, "Materialized [department_id]/[module?.role] room [solution.module_id] lost required authored fixture [required_type]")
		TEST_ASSERT(large_rooms > 0, "Random content sample [sample] contained no full-sized rooms")
		TEST_ASSERT(machinery >= length(materialized.room_solutions), "Random content sample [sample] averages fewer than one functional machine per room")
		var/datum/generated_station_validation_result/validation = materialized.validate_architecture(spec)
		var/html = materialized.diagnostic_minimap_html(validation)
		var/normalized_seed = spec.seed
		rustg_file_write(html, "[GLOB.log_directory]/generated-station-content-[normalized_seed].html")
		TEST_ASSERT_EQUAL(validation.count_severity(GENERATED_STATION_ISSUE_ERROR), 0, "Random content sample [sample] contains architecture errors; inspect generated-station-content-[normalized_seed].html")
		gallery += "<li><a href='generated-station-content-[normalized_seed].html'>Sample [sample], seed [normalized_seed]</a>: [length(materialized.room_solutions)] rooms, [length(materialized.furnishings)] registered furnishings, [machinery] functional machines.</li>"
		qdel(validation)
		qdel(materialized)
		qdel(materializer)
		qdel(spec)
		qdel(planner)
	gallery += "</ul></body></html>"
	rustg_file_write(jointext(gallery, ""), "[GLOB.log_directory]/generated-station-content-gallery.html")
	qdel(seed_stream)

/datum/generated_room_feature/test_impossible_dependency
	id = "test-impossible-dependency"
	atom_type = /obj/structure/table/standard

/datum/generated_room_feature/test_impossible_dependency/build_constraints()
	return list(new /datum/generated_room_constraint/near_feature(id, "feature-that-does-not-exist", TRUE, 1))

/datum/generated_room_definition/test_impossible
	id = "test-impossible-room"
	min_width = 1
	min_height = 1
	max_width = 255
	max_height = 255
	allow_narrow_irregular = TRUE

/datum/generated_room_definition/test_impossible/build_required_features()
	return list(/datum/generated_room_feature/test_impossible_dependency)

/datum/generated_station_materializer/test_room_fallback
	strict_room_contracts = FALSE

/datum/generated_station_materializer/test_room_fallback/resolve_room_definition(department_id, role)
	return new /datum/generated_room_definition/test_impossible

/datum/unit_test/dq_generated_station_runtime_room_fallback_cannot_abort_station

/datum/unit_test/dq_generated_station_runtime_room_fallback_cannot_abort_station/Run()
	var/datum/generated_station_prng/seed_stream = new(908172635)
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(seed_stream.next(), 96, 96)
	TEST_ASSERT_NOTNULL(spec, "Fallback behavior test produced no Rust station plan")
	var/datum/generated_station_materializer/test_room_fallback/materializer = new
	var/origin_x = max(1, round((world.maxx - spec.grid_width) / 2))
	var/origin_y = max(1, round((world.maxy - spec.grid_height) / 2))
	var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, origin_x, origin_y)
	TEST_ASSERT_NOTNULL(materialized, "An intentionally impossible room program aborted runtime station materialization: [materializer.last_failure_details]")
	TEST_ASSERT_EQUAL(length(materialized.degradation_events), length(materialized.modules), "Not every impossible authored room recorded its minimum-shell degradation")
	for(var/datum/generated_room_solution/solution in materialized.room_solutions)
		TEST_ASSERT(findtext(solution.definition_id, "-minimum-"), "Impossible room [solution.module_id] did not resolve through the guaranteed minimum shell")
	qdel(materialized)
	qdel(materializer)
	qdel(spec)
	qdel(planner)
	qdel(seed_stream)
