/datum/unit_test/dq_generated_station_architecture_many_seeds

/datum/unit_test/dq_generated_station_architecture_many_seeds/proc/layer_count(html, attribute)
	var/needle = "data-[attribute]='"
	var/start = findtext(html, needle)
	if(!start)
		return null
	start += length(needle)
	var/finish = findtext(html, "'", start)
	return finish ? text2num(copytext(html, start, finish)) : null

/datum/unit_test/dq_generated_station_architecture_many_seeds/Run()
	var/list/structural_signatures = list()
	var/list/gallery = list("<html><body><h1>Generated station seed gallery</h1><p>Each artifact includes its topology, repetition metrics, findings, and complete materialized minimap.</p><ul>")
	var/datum/generated_station_prng/seed_stream = new(20260718)
	// Full DM materialization is intentionally expensive; broad geometry fuzzing
	// lives in Rust, while four independently styled seeds exercise the complete
	// BYOND turf, furnishing, utility, and validation pipeline here.
	for(var/sample in 1 to 4)
		var/seed = ((seed_stream.next() + sample) % 2147483646) + 1
		var/datum/generated_station_planner/planner = new
		var/datum/generated_station_spec/spec = planner.plan(seed, 96, 96)
		var/config = "sample=[sample] seed=[seed] size=[spec?.grid_width]x[spec?.grid_height] style=[spec?.architecture_style] faction=[spec?.faction_id] security=[spec?.security_tier]"
		TEST_ASSERT_NOTNULL(spec, "Pseudo-random station sample produced no plan ([config])")
		var/datum/generated_station_materializer/materializer = new
		var/origin_x = max(1, round((world.maxx - spec.grid_width) / 2))
		var/origin_y = max(1, round((world.maxy - spec.grid_height) / 2))
		var/datum/generated_station_materialization/materialized = materializer.materialize(spec, world.maxz, origin_x, origin_y)
		if(!materialized && materializer.last_architecture_validation)
			for(var/datum/generated_station_validation_issue/issue in materializer.last_architecture_validation.issues)
				if(issue.severity == GENERATED_STATION_ISSUE_ERROR)
					TEST_FAIL("Materialization rejected ([config]): [issue.code] at [issue.subject_id]: [issue.message]")
		TEST_ASSERT_NOTNULL(materialized, "Pseudo-random station failed materialization ([config])")
		var/datum/generated_station_validation_result/validation = materialized.validate_architecture(spec)
		for(var/datum/generated_station_validation_issue/issue in validation.issues)
			if(issue.severity == GENERATED_STATION_ISSUE_ERROR)
				TEST_FAIL("Architecture validation failed ([config]): [issue.code] at [issue.subject_id]: [issue.message]")
		TEST_ASSERT(validation.is_valid(), "Pseudo-random station failed materialized architecture validation ([config])")
		var/minimap = materialized.diagnostic_minimap_html(validation)
		TEST_ASSERT(findtext(minimap, "Legend:"), "Diagnostic minimap was not rendered ([config])")
		TEST_ASSERT(findtext(minimap, "Architectural metrics:"), "Diagnostic omitted quantitative aesthetic metrics ([config])")
		for(var/layer_id in list("intent", "actual", "ownership", "lighting", "content", "structure", "mismatch"))
			TEST_ASSERT(findtext(minimap, "id='layer-[layer_id]'"), "Diagnostic omitted [layer_id] layer data ([config])")
		var/plan_cells = spec.grid_width * spec.grid_height
		TEST_ASSERT_EQUAL(layer_count(minimap, "intent-cells"), plan_cells, "Intent layer does not contain exactly one datum per planned coordinate ([config])")
		TEST_ASSERT_EQUAL(layer_count(minimap, "actual-cells"), plan_cells, "Actual layer does not contain exactly one datum per planned coordinate ([config])")
		TEST_ASSERT(layer_count(minimap, "light-cells") > 0, "Lighting layer has no physical coverage data ([config])")
		TEST_ASSERT(layer_count(minimap, "content-cells") > 0, "Content layer has no physical furnishing data ([config])")
		TEST_ASSERT(layer_count(minimap, "maintenance-public-department-cells") > 0, "Ownership layer has no maintenance/public/department data ([config])")
		TEST_ASSERT(layer_count(minimap, "structure-cells") > 0, "Structure layer has no wall/door data ([config])")
		TEST_ASSERT_EQUAL(layer_count(minimap, "mismatches"), 0, "Diagnostic found plan/materialization mismatches in a validated station ([config])")
		var/datum/generated_station_architecture_metrics/metrics = materialized.architecture_metrics()
		structural_signatures[metrics.structural_signature] = TRUE
		gallery += "<li><a href='generated-station-[seed].html'>Seed [seed]</a>: [metrics.summary()]</li>"
		rustg_file_write(minimap, "[GLOB.log_directory]/generated-station-[seed].html")
		qdel(metrics)
		qdel(validation)
		qdel(materialized)
		qdel(materializer)
		qdel(spec)
		qdel(planner)
	gallery += "</ul></body></html>"
	rustg_file_write(jointext(gallery, ""), "[GLOB.log_directory]/generated-station-gallery.html")
	TEST_ASSERT(length(structural_signatures) >= 2, "Four pseudo-random materializations produced only [length(structural_signatures)] distinct architectural signatures")
	qdel(seed_stream)

/datum/unit_test/dq_generated_station_semantic_layout_many_seeds

/datum/unit_test/dq_generated_station_semantic_layout_many_seeds/proc/normalized_shape(list/tiles)
	if(!length(tiles))
		return "empty"
	var/min_x = 1.0e31
	var/min_y = 1.0e31
	var/max_x = 0
	var/max_y = 0
	for(var/key in tiles)
		var/list/parts = splittext(key, ",")
		var/x = text2num(parts[1])
		var/y = text2num(parts[2])
		min_x = min(min_x, x)
		min_y = min(min_y, y)
		max_x = max(max_x, x)
		max_y = max(max_y, y)
	var/list/rows = list()
	for(var/y in min_y to max_y)
		var/row = ""
		for(var/x in min_x to max_x)
			row += tiles["[x],[y]"] ? "#" : "."
		rows += row
	return "[max_x - min_x + 1]x[max_y - min_y + 1]:[jointext(rows, "/")]"

/datum/unit_test/dq_generated_station_semantic_layout_many_seeds/proc/circulation_signature(datum/generated_station_spec/spec)
	var/list/degrees = list(0, 0, 0, 0, 0)
	for(var/key in spec.circulation_tiles)
		var/list/parts = splittext(key, ",")
		var/x = text2num(parts[1])
		var/y = text2num(parts[2])
		var/degree = 0
		for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
			if(spec.circulation_tiles["[x + offset[1]],[y + offset[2]]"])
				degree++
		degrees[degree + 1]++
	return jointext(degrees, ",")

/datum/unit_test/dq_generated_station_semantic_layout_many_seeds/proc/layout_raster(datum/generated_station_spec/spec, seed)
	var/list/cells = list()
	for(var/key in spec.circulation_tiles)
		cells[key] = "+"
	for(var/key in spec.maintenance_tiles)
		cells[key] = "m"
	for(var/key in spec.structural_tiles)
		cells[key] = "#"
	var/index = 0
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		index++
		var/mark = copytext("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ((index - 1) % 26) + 1, ((index - 1) % 26) + 2)
		for(var/key in node.territory)
			cells[key] = mark
	var/list/lines = list("seed [seed] [spec.grid_width]x[spec.grid_height]")
	for(var/y in spec.grid_height to 1 step -1)
		var/line = ""
		for(var/x in 1 to spec.grid_width)
			line += cells["[x],[y]"] || " "
		lines += line
	return jointext(lines, "\n")

/// Finds vacuum-like cells enclosed by the planned station footprint.
/datum/unit_test/dq_generated_station_semantic_layout_many_seeds/proc/enclosed_gap(datum/generated_station_spec/spec)
	var/list/occupied = spec.circulation_tiles.Copy()
	for(var/key in spec.maintenance_tiles)
		occupied[key] = TRUE
	for(var/key in spec.structural_tiles)
		occupied[key] = TRUE
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		for(var/key in node.territory)
			occupied[key] = TRUE
	var/list/exterior = list()
	var/list/open = list()
	for(var/x in 1 to spec.grid_width)
		open += list(list(x, 1), list(x, spec.grid_height))
	for(var/y in 1 to spec.grid_height)
		open += list(list(1, y), list(spec.grid_width, y))
	while(length(open))
		var/list/current = open[length(open)]
		open.len--
		var/key = "[current[1]],[current[2]]"
		if(exterior[key] || occupied[key])
			continue
		exterior[key] = TRUE
		for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
			var/nx = current[1] + offset[1]
			var/ny = current[2] + offset[2]
			if(nx >= 1 && nx <= spec.grid_width && ny >= 1 && ny <= spec.grid_height)
				open += list(list(nx, ny))
	for(var/x in 1 to spec.grid_width)
		for(var/y in 1 to spec.grid_height)
			var/key = "[x],[y]"
			if(!occupied[key] && !exterior[key])
				return key
	return null

/datum/unit_test/dq_generated_station_semantic_layout_many_seeds/Run()
	var/datum/generated_station_prng/seed_stream = new(20260719)
	var/list/circulation_topologies = list()
	var/list/adjacency_topologies = list()
	var/list/station_territory_signatures = list()
	var/list/room_count_signatures = list()
	var/list/room_shape_signatures = list()
	var/list/room_silhouettes = list()
	var/list/layout_gallery = list()
	for(var/sample in 1 to 256)
		var/seed = ((seed_stream.next() + sample) % 2147483646) + 1
		var/datum/generated_station_planner/planner = new
		var/width = 72 + ((sample * 7) % 4) * 8
		var/height = 72 + ((sample * 11) % 4) * 8
		var/datum/generated_station_spec/spec = planner.plan(seed, width, height)
		var/config = "sample=[sample] seed=[seed] size=[width]x[height] style=[spec?.architecture_style] faction=[spec?.faction_id] security=[spec?.security_tier]"
		for(var/key in spec.maintenance_tiles)
			TEST_ASSERT(!spec.circulation_tiles[key] && !spec.structural_tiles[key], "Maintenance tile [key] overlaps another macro class ([config])")
		for(var/key in spec.structural_tiles)
			TEST_ASSERT(!spec.circulation_tiles[key] && !spec.maintenance_tiles[key], "Structural tile [key] overlaps circulation ([config])")
		for(var/datum/generated_station_layout_node/classification_node in spec.layout_nodes)
			for(var/key in classification_node.territory)
				TEST_ASSERT(!spec.circulation_tiles[key] && !spec.maintenance_tiles[key] && !spec.structural_tiles[key], "Department tile [key] overlaps a macro class ([config])")
		var/gap = enclosed_gap(spec)
		TEST_ASSERT_NULL(gap, "Plan contains enclosed unallocated interior at [gap] ([config])")
		var/minimum_x = spec.grid_width
		var/minimum_y = spec.grid_height
		var/maximum_x = 1
		var/maximum_y = 1
		var/department_area = 0
		var/list/transit_tiles = list()
		var/list/station_shapes = list()
		var/list/station_room_counts = list()
		var/list/station_room_shapes = list()
		for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
			minimum_x = min(minimum_x, node.x)
			minimum_y = min(minimum_y, node.y)
			maximum_x = max(maximum_x, node.x + node.width - 1)
			maximum_y = max(maximum_y, node.y + node.height - 1)
			department_area += node.width * node.height
			var/list/classified = list()
			for(var/key in node.local_circulation)
				classified[key] = TRUE
			for(var/key in node.partition_walls)
				classified[key] = TRUE
			for(var/datum/generated_station_eva_vestibule/vestibule in node.eva_vestibules)
				for(var/key in vestibule.tiles)
					classified[key] = TRUE
			var/list/node_room_shapes = list()
			for(var/datum/generated_station_room_allocation/room in node.room_program)
				var/shape = normalized_shape(room.tiles)
				node_room_shapes += shape
				room_silhouettes[shape] = TRUE
				for(var/datum/generated_station_door_socket/socket in room.door_sockets)
					classified["[socket.x],[socket.y]"] = TRUE
				for(var/key in room.tiles)
					TEST_ASSERT(node.territory[key], "Room [room.id] escapes department territory ([config])")
					classified[key] = TRUE
			for(var/datum/generated_station_door_socket/socket in node.frontage_sockets)
				classified["[socket.x],[socket.y]"] = TRUE
			for(var/key in node.territory)
				TEST_ASSERT(classified[key], "Unallocated interior tile [key] remains in [node.id] ([config])")
			station_shapes += "[node.id]=[normalized_shape(node.territory)]"
			station_room_counts += "[node.id]=[length(node.room_program)]"
			station_room_shapes += "[node.id]=[jointext(node_room_shapes, ",")]"
		station_territory_signatures[jointext(station_shapes, "|")] = TRUE
		room_count_signatures[jointext(station_room_counts, "|")] = TRUE
		room_shape_signatures[jointext(station_room_shapes, "|")] = TRUE
		circulation_topologies[circulation_signature(spec)] = TRUE
		var/list/adjacencies = list()
		for(var/datum/generated_station_layout_edge/edge in spec.layout_edges)
			adjacencies += "[edge.from_node_id]>[edge.to_node_id]:[edge.kind]"
			if(edge.kind != GENERATED_STATION_EDGE_TRANSIT)
				continue
			for(var/list/coordinate in edge.path)
				transit_tiles["[coordinate[1]],[coordinate[2]]"] = TRUE
		adjacency_topologies[jointext(adjacencies, "|")] = TRUE
		var/bounding_area = (maximum_x - minimum_x + 1) * (maximum_y - minimum_y + 1)
		TEST_ASSERT(bounding_area / max(1, department_area) <= 1.85, "Sparse department footprint ([config]; [bounding_area] bounding tiles for [department_area] department tiles)")
		TEST_ASSERT(length(transit_tiles) / max(1, department_area) <= 0.28, "Excessive connector hallway footprint ([config])")
		if(sample <= 8)
			layout_gallery += layout_raster(spec, seed)
		qdel(spec)
		qdel(planner)
	rustg_file_write(jointext(layout_gallery, "\n\n"), "[GLOB.log_directory]/generated-station-random-layouts.txt")
	TEST_ASSERT(length(circulation_topologies) >= 4, "Random sweep produced only [length(circulation_topologies)] macro circulation topologies")
	TEST_ASSERT(length(adjacency_topologies) >= 8, "Random sweep produced only [length(adjacency_topologies)] department adjacency topologies")
	TEST_ASSERT(length(station_territory_signatures) >= 16, "Random sweep repeats fixed department territory slots ([length(station_territory_signatures)] station silhouettes)")
	TEST_ASSERT(length(room_count_signatures) >= 8, "Random sweep repeats a fixed room-count grammar ([length(room_count_signatures)] signatures)")
	TEST_ASSERT(length(room_shape_signatures) >= 16, "Random sweep repeats a fixed room-shape grammar ([length(room_shape_signatures)] station signatures)")
	TEST_ASSERT(length(room_silhouettes) >= 24, "Random sweep produced only [length(room_silhouettes)] room silhouettes")
	qdel(seed_stream)

/datum/unit_test/dq_generated_station_candidate_selection_is_deterministic

/datum/unit_test/dq_generated_station_candidate_selection_is_deterministic/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_prng/seed_stream = new(20260720)
	var/seed = ((seed_stream.next() + 1) % 2147483646) + 1
	var/datum/generated_station_spec/first = planner.plan(seed, 80, 88)
	var/datum/generated_station_spec/second = planner.plan(seed, 80, 88)
	var/list/first_signature = list(first.architecture_style, first.grid_width, first.grid_height)
	var/list/second_signature = list(second.architecture_style, second.grid_width, second.grid_height)
	for(var/datum/generated_station_layout_node/node in first.layout_nodes)
		first_signature += "N:[node.id]:[node.x],[node.y],[node.width],[node.height]"
	for(var/datum/generated_station_layout_edge/edge in first.layout_edges)
		first_signature += "E:[edge.id]:[edge.from_node_id]>[edge.to_node_id]:[json_encode(edge.path)]"
	for(var/datum/generated_station_layout_node/second_node in second.layout_nodes)
		second_signature += "N:[second_node.id]:[second_node.x],[second_node.y],[second_node.width],[second_node.height]"
	for(var/datum/generated_station_layout_edge/second_edge in second.layout_edges)
		second_signature += "E:[second_edge.id]:[second_edge.from_node_id]>[second_edge.to_node_id]:[json_encode(second_edge.path)]"
	TEST_ASSERT_EQUAL(jointext(first_signature, "|"), jointext(second_signature, "|"), "Candidate scoring changed the complete layout selected for an identical seed")
	qdel(first)
	qdel(seed_stream)
	qdel(second)
	qdel(planner)

/datum/unit_test/dq_generated_station_architecture_validator_is_falsifiable

/datum/unit_test/dq_generated_station_architecture_validator_is_falsifiable/Run()
	var/datum/generated_station_materialization/materialized = new
	materialized.station_id = "invalid-architecture-fixture"
	materialized.z_level = world.maxz
	var/area/generated_station/transit/transit = new
	transit.station_id = materialized.station_id
	materialized.transit_area = transit
	var/turf/T = locate(world.maxx, world.maxy, world.maxz)
	T.ChangeTurf(/turf/simulated/floor/plating, tell_universe = FALSE)
	ChangeArea(T, transit)
	var/obj/machinery/door/airlock/door = new(T)
	materialized.doors += door
	var/datum/generated_station_validation_result/validation = materialized.validate_architecture()
	TEST_ASSERT(!validation.is_valid(), "Architecture validator accepted a door and hallway terminating at the map boundary")
	var/found_door_error = FALSE
	var/found_hall_error = FALSE
	for(var/datum/generated_station_validation_issue/issue in validation.issues)
		if(issue.code == "door-nowhere")
			found_door_error = TRUE
		if(issue.code == "hallway-dead-end" || issue.code == "hallway-open-to-space")
			found_hall_error = TRUE
	TEST_ASSERT(found_door_error, "Falsifiability fixture did not detect its invalid door")
	TEST_ASSERT(found_hall_error, "Falsifiability fixture did not detect its invalid hallway")
	qdel(validation)
	qdel(materialized)

/datum/unit_test/dq_generated_station_plan_parity_is_falsifiable

/datum/unit_test/dq_generated_station_plan_parity_is_falsifiable/Run()
	var/datum/generated_station_materialization/materialized = new
	materialized.station_id = "plan-parity-falsification"
	materialized.z_level = world.maxz
	materialized.origin_x = 1
	materialized.origin_y = 1
	materialized.transit_area = new
	materialized.tile_plan = new(1, 1)
	var/turf/actual = locate(1, 1, world.maxz)
	var/expected_kind = istype(actual, /turf/simulated/floor) ? GENERATED_STATION_TILE_HULL : GENERATED_STATION_TILE_FLOOR
	materialized.tile_plan.claim(1, 1, "falsified-owner", "falsified-zone", expected_kind, /turf/simulated/floor/tiled)
	var/datum/generated_station_validation_result/validation = materialized.validate_architecture()
	var/found_mismatch = FALSE
	for(var/datum/generated_station_validation_issue/issue in validation.issues)
		if(issue.code == "plan-floor-mismatch" || issue.code == "plan-wall-mismatch")
			found_mismatch = TRUE
			break
	TEST_ASSERT(found_mismatch, "Architecture validation accepted a deliberately falsified tile-plan/materialization mismatch")
	qdel(validation)
	qdel(materialized)

/datum/unit_test/dq_generated_station_diagnostic_layers_are_machine_checkable

/datum/unit_test/dq_generated_station_diagnostic_layers_are_machine_checkable/Run()
	var/datum/generated_station_materialization/materialized = new
	materialized.station_id = "diagnostic-layer-fixture"
	materialized.z_level = world.maxz
	materialized.origin_x = 1
	materialized.origin_y = 1
	materialized.transit_area = new
	materialized.tile_plan = new(1, 1)
	var/turf/actual = locate(1, 1, world.maxz)
	var/expected_kind = GENERATED_STATION_TILE_EXTERIOR
	if(istype(actual, /turf/simulated/floor))
		expected_kind = GENERATED_STATION_TILE_FLOOR
	else if(istype(actual, /turf/simulated/wall))
		expected_kind = GENERATED_STATION_TILE_HULL
	materialized.tile_plan.claim(1, 1, "fixture", "fixture", expected_kind, /turf/simulated/floor/tiled)
	var/datum/generated_station_validation_result/validation = new
	var/html = materialized.diagnostic_minimap_html(validation)
	for(var/layer_id in list("intent", "actual", "ownership", "lighting", "content", "structure", "mismatch"))
		TEST_ASSERT(findtext(html, "id='layer-[layer_id]'"), "Diagnostic fixture omitted [layer_id] payload")
	TEST_ASSERT(findtext(html, "data-intent-cells='1'"), "Intent layer count does not reconcile with its one-cell plan")
	TEST_ASSERT(findtext(html, "data-actual-cells='1'"), "Actual layer count does not reconcile with its one-cell extent")
	TEST_ASSERT(findtext(html, "data-mismatches='0'"), "Matching diagnostic fixture reported a plan mismatch")
	qdel(validation)
	qdel(materialized)

/datum/unit_test/dq_generated_station_aesthetic_validator_is_falsifiable

/datum/unit_test/dq_generated_station_aesthetic_validator_is_falsifiable/Run()
	var/datum/generated_station_architecture_metrics/metrics = new
	metrics.module_count = 12
	metrics.unique_room_shapes = 1
	metrics.largest_identical_room_shape_count = 12
	metrics.identical_room_shape_ratio = 1
	metrics.longest_straight_hall = 80
	metrics.circulation_junction_count = 0
	metrics.direct_main_hall_room_ratio = 1
	metrics.aligned_door_pair_count = 12
	metrics.repeated_door_interval_ratio = 1
	var/datum/generated_station_validation_result/validation = new
	generated_station_validate_aesthetic_metrics(metrics, validation, "deliberately-monotonous-plan")
	var/list/found_codes = list()
	for(var/datum/generated_station_validation_issue/issue in validation.issues)
		found_codes[issue.code] = TRUE
	TEST_ASSERT(found_codes["repeated-room-shapes"], "Aesthetic validator accepted twelve identical room footprints")
	TEST_ASSERT(found_codes["monolithic-straight-hall"], "Aesthetic validator accepted an eighty-tile uninterrupted hallway")
	TEST_ASSERT(found_codes["insufficient-circulation-junctions"], "Aesthetic validator accepted circulation without a junction")
	TEST_ASSERT(found_codes["rooms-front-main-hall"], "Aesthetic validator accepted every room opening onto the main hallway")
	TEST_ASSERT(found_codes["repeated-door-rhythm"], "Aesthetic validator accepted a completely repeated door interval")
	TEST_ASSERT(!validation.is_valid(), "Aesthetic validator did not reject its deliberately monotonous fixture")
	qdel(validation)
	qdel(metrics)
