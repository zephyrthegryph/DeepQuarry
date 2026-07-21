#define GENERATED_STATION_COMPACTNESS_LIMIT 1.9
#define GENERATED_STATION_MAX_TRANSIT_FLOOR_RATIO 0.3
#define GENERATED_STATION_MIN_DEPARTMENT_FRONTAGE 1
#define GENERATED_STATION_MIN_PRIMARY_TRANSIT_COVERAGE 0.85
#define GENERATED_STATION_MAX_IDENTICAL_ROOM_SHAPE_RATIO 0.55
#define GENERATED_STATION_MAX_STRAIGHT_HALL_LENGTH 32
#define GENERATED_STATION_HALL_RASTER_APRON 2
#define GENERATED_STATION_MIN_CIRCULATION_JUNCTIONS 2
#define GENERATED_STATION_MAX_DIRECT_MAIN_HALL_RATIO 0.8
#define GENERATED_STATION_MAX_REPEATED_DOOR_INTERVAL_RATIO 0.7

/// Quantitative architectural qualities used by candidate diagnostics and the
/// publication gate. Values describe the materialized map players actually see.
/datum/generated_station_architecture_metrics
	var/module_count = 0
	var/unique_room_shapes = 0
	var/largest_identical_room_shape_count = 0
	var/identical_room_shape_ratio = 0
	var/longest_straight_hall = 0
	var/circulation_junction_count = 0
	var/circulation_loop_rank = 0
	var/direct_main_hall_room_ratio = 0
	var/aligned_door_pair_count = 0
	var/repeated_door_interval_ratio = 0
	var/structural_signature

/datum/generated_station_architecture_metrics/proc/summary()
	return "room shapes [unique_room_shapes]/[module_count] unique (largest family [round(identical_room_shape_ratio * 100, 0.1)]%); longest hall [longest_straight_hall]; junctions [circulation_junction_count]; loop rank [circulation_loop_rank]; direct frontage [round(direct_main_hall_room_ratio * 100, 0.1)]%; repeated door interval [round(repeated_door_interval_ratio * 100, 0.1)]%"

/// Computes topology and repetition metrics without deciding their severity.
/datum/generated_station_materialization/proc/architecture_metrics()
	var/datum/generated_station_architecture_metrics/metrics = new
	var/list/shape_counts = list()
	var/list/shape_signature = list()
	for(var/datum/generated_station_module/module in modules)
		var/room_width = module.width()
		var/room_height = module.height()
		var/shape_key = "[min(room_width, room_height)]x[max(room_width, room_height)]:[module.footprint_tiles() || room_width * room_height]"
		shape_counts[shape_key] = (shape_counts[shape_key] || 0) + 1
		metrics.module_count++
	for(var/shape_key in shape_counts)
		metrics.unique_room_shapes++
		metrics.largest_identical_room_shape_count = max(metrics.largest_identical_room_shape_count, shape_counts[shape_key])
		shape_signature += "[shape_key]=[shape_counts[shape_key]]"
	metrics.identical_room_shape_ratio = metrics.largest_identical_room_shape_count / max(1, metrics.module_count)

	var/list/transit_floors = list()
	for(var/turf/simulated/floor/T in transit_area)
		transit_floors[T] = TRUE
	var/edge_count = 0
	for(var/turf/simulated/floor/T as anything in transit_floors)
		var/cardinal_neighbors = 0
		var/horizontal_run = 1
		var/vertical_run = 1
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(T, direction)
			if(transit_floors[neighbor])
				cardinal_neighbors++
				if(direction == EAST || direction == NORTH)
					edge_count++
		if(cardinal_neighbors >= 3)
			metrics.circulation_junction_count++
		var/turf/cursor = get_step(T, EAST)
		while(transit_floors[cursor])
			horizontal_run++
			var/horizontal_degree = 0
			for(var/direction in GLOB.cardinal)
				if(transit_floors[get_step(cursor, direction)])
					horizontal_degree++
			if(horizontal_degree >= 3)
				break
			cursor = get_step(cursor, EAST)
		cursor = get_step(T, NORTH)
		while(transit_floors[cursor])
			vertical_run++
			var/vertical_degree = 0
			for(var/direction in GLOB.cardinal)
				if(transit_floors[get_step(cursor, direction)])
					vertical_degree++
			if(vertical_degree >= 3)
				break
			cursor = get_step(cursor, NORTH)
		metrics.longest_straight_hall = max(metrics.longest_straight_hall, horizontal_run, vertical_run)
	metrics.circulation_loop_rank = max(0, edge_count - length(transit_floors) + (length(transit_floors) ? 1 : 0))

	var/direct_room_count = 0
	for(var/datum/generated_station_module/module in modules)
		var/area/generated_station/module_area = department_areas[module.department_node_id]
		if(!module_area)
			continue
		var/direct_frontage = FALSE
		for(var/local_x in module.x1 to module.x2)
			for(var/local_y in module.y1 to module.y2)
				if(local_x != module.x1 && local_x != module.x2 && local_y != module.y1 && local_y != module.y2)
					continue
				var/turf/module_turf = world_turf(local_x, local_y)
				for(var/direction in GLOB.cardinal)
					var/turf/neighbor = get_step(module_turf, direction)
					if(istype(neighbor, /turf/simulated/floor) && istype(get_area(neighbor), /area/generated_station/transit))
						direct_frontage = TRUE
						break
				if(direct_frontage)
					break
			if(direct_frontage)
				break
		if(direct_frontage)
			direct_room_count++
	var/list/aligned_interval_counts = list()
	var/aligned_door_pairs = 0
	for(var/i in 1 to length(doors))
		var/obj/machinery/door/first_door = doors[i]
		var/turf/first_turf = get_turf(first_door)
		for(var/j in i + 1 to length(doors))
			var/turf/second_turf = get_turf(doors[j])
			var/interval
			if(first_turf.x == second_turf.x)
				interval = abs(first_turf.y - second_turf.y)
			else if(first_turf.y == second_turf.y)
				interval = abs(first_turf.x - second_turf.x)
			if(interval)
				aligned_door_pairs++
				aligned_interval_counts["[interval]"] = (aligned_interval_counts["[interval]"] || 0) + 1
	var/dominant_interval_count = 0
	for(var/interval_key in aligned_interval_counts)
		dominant_interval_count = max(dominant_interval_count, aligned_interval_counts[interval_key])
	metrics.direct_main_hall_room_ratio = direct_room_count / max(1, metrics.module_count)
	metrics.aligned_door_pair_count = aligned_door_pairs
	metrics.repeated_door_interval_ratio = dominant_interval_count / max(1, aligned_door_pairs)
	metrics.structural_signature = "[jointext(shape_signature, ";")]|hall=[metrics.longest_straight_hall]|junctions=[metrics.circulation_junction_count]|loops=[metrics.circulation_loop_rank]"
	return metrics

/// Applies deliberately falsifiable aesthetic limits after metrics are computed.
/proc/generated_station_validate_aesthetic_metrics(datum/generated_station_architecture_metrics/metrics, datum/generated_station_validation_result/validation, subject_id)
	if(metrics.module_count >= 8 && metrics.identical_room_shape_ratio > GENERATED_STATION_MAX_IDENTICAL_ROOM_SHAPE_RATIO)
		validation.add(GENERATED_STATION_ISSUE_ERROR, "repeated-room-shapes", "[round(metrics.identical_room_shape_ratio * 100, 0.1)]% of rooms share one footprint; no more than [GENERATED_STATION_MAX_IDENTICAL_ROOM_SHAPE_RATIO * 100]% may be identical.", subject_id)
	// A three-tile-wide turn contributes its two side tiles to the continuous
	// raster row even though the route centerline has already changed direction.
	// Preserve the centerline limit without rejecting that corner apron.
	if(metrics.longest_straight_hall > GENERATED_STATION_MAX_STRAIGHT_HALL_LENGTH + GENERATED_STATION_HALL_RASTER_APRON)
		validation.add(GENERATED_STATION_ISSUE_ERROR, "monolithic-straight-hall", "A straight hallway raster runs [metrics.longest_straight_hall] tiles without an architectural break; the centerline limit is [GENERATED_STATION_MAX_STRAIGHT_HALL_LENGTH].", subject_id)
	if(metrics.module_count >= 8 && metrics.circulation_junction_count < GENERATED_STATION_MIN_CIRCULATION_JUNCTIONS)
		validation.add(GENERATED_STATION_ISSUE_ERROR, "insufficient-circulation-junctions", "Primary circulation contains only [metrics.circulation_junction_count] junction tiles; at least [GENERATED_STATION_MIN_CIRCULATION_JUNCTIONS] are required.", subject_id)
	if(metrics.module_count >= 8 && metrics.direct_main_hall_room_ratio > GENERATED_STATION_MAX_DIRECT_MAIN_HALL_RATIO)
		validation.add(GENERATED_STATION_ISSUE_ERROR, "rooms-front-main-hall", "[round(metrics.direct_main_hall_room_ratio * 100, 0.1)]% of rooms front directly onto primary circulation; departments need internal circulation.", subject_id)
	if(metrics.aligned_door_pair_count >= 6 && metrics.repeated_door_interval_ratio > GENERATED_STATION_MAX_REPEATED_DOOR_INTERVAL_RATIO)
		validation.add(GENERATED_STATION_ISSUE_WARNING, "repeated-door-rhythm", "[round(metrics.repeated_door_interval_ratio * 100, 0.1)]% of aligned door pairs repeat one interval.", subject_id)

/// Returns whether a player-sized route can use this turf after doors are opened.
/proc/generated_station_architectural_passable(turf/T)
	if(!T || T.density || !istype(T, /turf/simulated/floor))
		return FALSE
	for(var/atom/movable/occupant in T)
		if(occupant.density && !istype(occupant, /obj/machinery/door))
			return FALSE
	return TRUE

/proc/generated_station_coordinate(atom/A)
	return A ? "[A.x],[A.y],[A.z]" : "unknown"

/proc/generated_station_neighbor_summary(turf/T)
	var/list/parts = list()
	for(var/direction in GLOB.cardinal)
		var/turf/neighbor = get_step(T, direction)
		var/list/occupants = list()
		if(neighbor)
			for(var/atom/movable/occupant in neighbor)
				if(occupant.density || istype(occupant, /obj/machinery/door))
					occupants += "[occupant.type]"
		parts += "[dir2text(direction)]=[neighbor?.type || "boundary"] passable=[generated_station_architectural_passable(neighbor)] occupants=[jointext(occupants, ",")]"
	return jointext(parts, "; ")

/// Measures a one-tile dead-end branch until it reaches a junction. Very short
/// branches are the harmless edge cells of widened corners and entrance aprons.
/proc/generated_station_dead_end_branch_length(turf/start, list/transit_floors, limit = 3)
	var/turf/current = start
	var/turf/previous
	var/branch_length = 1
	while(branch_length <= limit)
		var/list/forward = list()
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(current, direction)
			if(neighbor != previous && (neighbor in transit_floors) && generated_station_architectural_passable(neighbor))
				forward += neighbor
		if(length(forward) != 1)
			return branch_length
		previous = current
		current = forward[1]
		branch_length++
	return branch_length

/// Audits the materialized geometry rather than trusting the abstract plan. Every
/// error here represents a station that must be discarded before publication.
/datum/generated_station_materialization/proc/validate_architecture(datum/generated_station_spec/spec)
	var/datum/generated_station_validation_result/validation = new
	var/list/station_turfs = list()
	var/list/transit_floors = list()
	var/list/circulation_floors = list()
	var/list/department_frontage = list()
	var/minimum_x = world.maxx
	var/minimum_y = world.maxy
	var/maximum_x = 1
	var/maximum_y = 1
	if(spec)
		var/list/centerline = list()
		// circulation_tiles is the authoritative graph. edge.path may contain a
		// complete set-valued network snapshot and therefore has no list ordering.
		for(var/key in spec.circulation_tiles)
			var/list/parts = splittext(key, ",")
			centerline[key] = list(text2num(parts[1]), text2num(parts[2]))
		var/centerline_edges = 0
		var/centerline_junctions = 0
		var/centerline_longest_run = 0
		for(var/key in centerline)
			var/list/point = centerline[key]
			var/degree = 0
			var/horizontal_run = 1
			var/vertical_run = 1
			for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
				if(centerline["[point[1] + offset[1]],[point[2] + offset[2]]"])
					degree++
			if(centerline["[point[1] + 1],[point[2]]"])
				centerline_edges++
			if(centerline["[point[1]],[point[2] + 1]"])
				centerline_edges++
			if(degree >= 3)
				centerline_junctions++
			var/x = point[1] + 1
			while(centerline["[x],[point[2]]"])
				horizontal_run++
				var/horizontal_centerline_degree = 0
				for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
					if(centerline["[x + offset[1]],[point[2] + offset[2]]"])
						horizontal_centerline_degree++
				if(horizontal_centerline_degree >= 3)
					break
				x++
			var/y = point[2] + 1
			while(centerline["[point[1]],[y]"])
				vertical_run++
				var/vertical_centerline_degree = 0
				for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
					if(centerline["[point[1] + offset[1]],[y + offset[2]]"])
						vertical_centerline_degree++
				if(vertical_centerline_degree >= 3)
					break
				y++
			centerline_longest_run = max(centerline_longest_run, horizontal_run, vertical_run)
		var/centerline_loop_rank = max(0, centerline_edges - length(centerline) + (length(centerline) ? 1 : 0))
		if(length(modules) >= 8 && centerline_junctions < GENERATED_STATION_MIN_CIRCULATION_JUNCTIONS)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "insufficient-centerline-junctions", "Corridor centerlines contain only [centerline_junctions] real junctions.", station_id)
		if(centerline_longest_run > GENERATED_STATION_MAX_STRAIGHT_HALL_LENGTH)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "monolithic-centerline-hall", "Corridor centerline runs [centerline_longest_run] tiles without an architectural break.", station_id)
		if(length(modules) >= 8 && !centerline_loop_rank)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "centerline-without-loop", "Primary corridor centerline has no alternate circulation loop.", station_id)

	// The tile plan is the structural contract. Area enumeration alone cannot
	// detect a planned wall that was accidentally replaced with space, because
	// that turf also disappears from the generated area.
	for(var/key in tile_plan?.tiles)
		var/datum/generated_station_tile_intent/intent = tile_plan.tiles[key]
		var/turf/planned_turf = world_turf(intent.local_x, intent.local_y)
		if(intent.structure_kind == GENERATED_STATION_TILE_FLOOR && !istype(planned_turf, /turf/simulated/floor))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "plan-floor-mismatch", "Planned floor materialized as [planned_turf?.type || "null"].", "[intent.local_x],[intent.local_y]")
		else if(intent.structure_kind == GENERATED_STATION_TILE_FLOOR && !istype(planned_turf.loc, /area/generated_station))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "plan-floor-area-mismatch", "Planned floor belongs to [planned_turf.loc?.type || "null"] instead of a generated-station area.", "[intent.local_x],[intent.local_y]")
		else if(intent.structure_kind == GENERATED_STATION_TILE_HULL && !istype(planned_turf, /turf/simulated/wall))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "plan-wall-mismatch", "Planned structural wall materialized as [planned_turf?.type || "null"].", "[intent.local_x],[intent.local_y]")
		else if(intent.structure_kind == GENERATED_STATION_TILE_EXTERIOR && !istype(planned_turf, /turf/space))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "plan-exterior-mismatch", "Planned exterior materialized as [planned_turf?.type || "null"].", "[intent.local_x],[intent.local_y]")
		if(intent.door_type && !(locate(/obj/machinery/door) in planned_turf))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "plan-door-missing", "Declared door socket has no physical door.", "[intent.local_x],[intent.local_y]")
		if(intent.structure_kind == GENERATED_STATION_TILE_HULL && istype(planned_turf, /turf/simulated/wall))
			var/wall_neighbors = 0
			var/door_neighbors = 0
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor_turf = get_step(planned_turf, direction)
				if(istype(neighbor_turf, /turf/simulated/wall))
					wall_neighbors++
				else if(locate(/obj/machinery/door) in neighbor_turf)
					door_neighbors++
			if(!wall_neighbors && !door_neighbors)
				validation.add(GENERATED_STATION_ISSUE_ERROR, "isolated-wall", "Structural wall is disconnected from every cardinal wall.", "[intent.local_x],[intent.local_y]")
			else if(wall_neighbors == 4 && intent.owner_id != "station-structure")
				validation.add(GENERATED_STATION_ISSUE_WARNING, "buried-wall", "Hull corner closure creates a fully enclosed wall cell.", "[intent.local_x],[intent.local_y]")
			var/turf/simulated/wall/physical_wall = planned_turf
			var/connections_before = json_encode(physical_wall.wall_connections)
			physical_wall.update_connections()
			if(connections_before != json_encode(physical_wall.wall_connections))
				validation.add(GENERATED_STATION_ISSUE_ERROR, "stale-wall-adjacency", "Wall adjacency state did not match its materialized neighbors.", "[intent.local_x],[intent.local_y]")

	// Intentional enclosed structural fill may contain buried cells, but it must
	// never become a giant solid substitute for spatial planning.
	var/list/unvisited_structure = list()
	for(var/key in tile_plan?.tiles)
		var/datum/generated_station_tile_intent/intent = tile_plan.tiles[key]
		if(intent.owner_id == "station-structure" && intent.structure_kind == GENERATED_STATION_TILE_HULL)
			unvisited_structure[key] = intent
	while(length(unvisited_structure))
		var/start_key = unvisited_structure[1]
		var/list/frontier = list(unvisited_structure[start_key])
		var/component_size = 0
		var/buried_core = 0
		while(length(frontier))
			var/datum/generated_station_tile_intent/current = frontier[length(frontier)]
			frontier.len--
			var/current_key = tile_plan.coordinate_key(current.local_x, current.local_y)
			if(!unvisited_structure[current_key])
				continue
			unvisited_structure -= current_key
			component_size++
			var/structural_neighbors = 0
			for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
				var/datum/generated_station_tile_intent/neighbor = tile_plan.tile(current.local_x + offset[1], current.local_y + offset[2])
				if(neighbor?.owner_id == "station-structure" && neighbor.structure_kind == GENERATED_STATION_TILE_HULL)
					structural_neighbors++
					var/neighbor_key = tile_plan.coordinate_key(neighbor.local_x, neighbor.local_y)
					if(unvisited_structure[neighbor_key])
						frontier += neighbor
			if(structural_neighbors == 4)
				buried_core++
		var/max_component_area = max(48, round(length(tile_plan.tiles) * 0.02))
		if(buried_core > max(4, round(component_size * 0.25)) || (component_size > max_component_area && buried_core > round(component_size * 0.1)))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "excessive-structural-mass", "Structural fill component has [component_size] tiles and [buried_core] fully buried core tiles; limits are [max_component_area] tiles and [max(4, round(component_size * 0.25))] core tiles.", start_key)

	// Every room edge must resolve to its own floor, a structural wall, or a
	// declared doorway. This detects missing internal partitions without relying
	// on hull pressure checks.
	for(var/datum/generated_station_module/module in modules)
		for(var/x in module.footprint_x1 to module.footprint_x2)
			for(var/y in module.footprint_y1 to module.footprint_y2)
				if(!module.contains_tile(x, y))
					continue
				for(var/direction in GLOB.cardinal)
					var/nx = x + (direction == EAST) - (direction == WEST)
					var/ny = y + (direction == NORTH) - (direction == SOUTH)
					if(module.contains_tile(nx, ny))
						continue
					var/datum/generated_station_tile_intent/boundary = tile_plan?.tile(nx, ny)
					if(!boundary || boundary.owner_id != module.department_node_id)
						continue
					var/turf/boundary_turf = world_turf(nx, ny)
					if(boundary.structure_kind != GENERATED_STATION_TILE_HULL && !(boundary.door_type && locate(/obj/machinery/door) in boundary_turf))
						validation.add(GENERATED_STATION_ISSUE_ERROR, "room-boundary-open", "Room boundary opens directly into [boundary.zone_id] without a wall or declared door.", module.id)

	for(var/node_id in department_areas)
		var/area/generated_station/department_area = department_areas[node_id]
		for(var/turf/T in department_area)
			station_turfs |= T
	for(var/turf/T in transit_area)
		station_turfs |= T
		if(istype(T, /turf/simulated/floor))
			transit_floors |= T
			circulation_floors |= T
	for(var/turf/T in maintenance_area)
		station_turfs |= T
		if(istype(T, /turf/simulated/floor))
			circulation_floors |= T

	for(var/turf/T as anything in station_turfs)
		minimum_x = min(minimum_x, T.x)
		minimum_y = min(minimum_y, T.y)
		maximum_x = max(maximum_x, T.x)
		maximum_y = max(maximum_y, T.y)
		if(!istype(T, /turf/simulated/floor) && !istype(T, /turf/simulated/wall))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "missing-floor-or-hull", "Station-owned turf is neither flooring nor hull.", generated_station_coordinate(T))
		if(istype(get_area(T), /area/generated_station) && !istype(get_area(T), /area/generated_station/transit))
			var/area/generated_station/turf_department = get_area(T)
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor = get_step(T, direction)
				if(istype(get_area(neighbor), /area/generated_station/transit) && istype(neighbor, /turf/simulated/floor))
					department_frontage[turf_department.department_id] = (department_frontage[turf_department.department_id] || 0) + 1
					break

	for(var/node_id in department_areas)
		var/area/generated_station/node_department = department_areas[node_id]
		var/frontage = department_frontage[node_department.department_id] || 0
		if(frontage < GENERATED_STATION_MIN_DEPARTMENT_FRONTAGE)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "department-without-frontage", "Department has no airlock frontage on primary circulation.", node_department.department_id)

	for(var/datum/generated_station_module/module in modules)
		var/datum/generated_room_solution/solution
		for(var/datum/generated_room_solution/candidate in room_solutions)
			if(candidate.module_id == module.id)
				solution = candidate
				break
		if(!solution)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "room-without-solution", "Functional room has no inspectable content solution.", module.id)
			continue
		var/module_department_id
		for(var/datum/generated_station_layout_node/layout_node in spec?.layout_nodes)
			if(layout_node.id != module.department_node_id)
				continue
			for(var/datum/generated_station_department_instance/department in spec.departments)
				if(department.id == layout_node.department_instance_id)
					module_department_id = department.definition?.id
					break
			break
		var/datum/generated_room_definition/definition = generated_room_definition_for(module_department_id, module.role)
		if(!definition)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "unknown-room-definition", "Functional room references an unknown definition.", module.id)
			continue
		if(findtext(solution.definition_id, "-compact"))
			qdel(definition)
			definition = generated_compact_room_definition_for(module_department_id, module.role)
		var/minimum_usable_tiles = min(definition.min_width * definition.min_height, 21)
		if(module.footprint_tiles() < minimum_usable_tiles)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "room-below-minimum-size", "[definition.name] has [module.footprint_tiles()] usable tiles, below its [minimum_usable_tiles]-tile content contract.", module.id)
		qdel(definition)

	for(var/obj/machinery/door/door in doors)
		var/turf/door_turf = get_turf(door)
		if(!istype(door_turf, /turf/simulated/floor))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "door-in-wall", "Door is not installed on flooring.", generated_station_coordinate(door))
			continue
		var/turf/north = get_step(door_turf, NORTH)
		var/turf/south = get_step(door_turf, SOUTH)
		var/turf/east = get_step(door_turf, EAST)
		var/turf/west = get_step(door_turf, WEST)
		var/north_south = istype(north, /turf/simulated/floor) && istype(south, /turf/simulated/floor) && !north.density && !south.density
		var/east_west = istype(east, /turf/simulated/floor) && istype(west, /turf/simulated/floor) && !east.density && !west.density
		var/valid_exterior = FALSE
		if(istype(door, /obj/machinery/door/airlock/generated_station_exterior))
			for(var/direction in GLOB.cardinal)
				if(istype(get_step(door_turf, direction), /turf/space) && generated_station_architectural_passable(get_step(door_turf, turn(direction, 180))))
					valid_exterior = TRUE
					break
		if(!north_south && !east_west && !valid_exterior)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "door-nowhere", "Door lacks two opposite, clear walking sides: [generated_station_neighbor_summary(door_turf)].", generated_station_coordinate(door))
		else if(!valid_exterior)
			var/list/door_sides = north_south ? list(north, south) : list(east, west)
			for(var/turf/side_turf in door_sides)
				for(var/atom/movable/blocker in side_turf)
					if(blocker.density && !istype(blocker, /obj/machinery/door))
						validation.add(GENERATED_STATION_ISSUE_ERROR, "blocked-door", "[blocker.type] blocks the approach to [door.type] at [generated_station_coordinate(door)].", generated_station_coordinate(blocker))
		for(var/atom/movable/occupant in door_turf)
			if(occupant != door && (occupant.density || istype(occupant, /obj/machinery/power/apc) || istype(occupant, /obj/machinery/alarm)))
				validation.add(GENERATED_STATION_ISSUE_ERROR, "fixture-on-door", "A fixture or blocking object occupies a door tile.", generated_station_coordinate(occupant))

	for(var/turf/T as anything in station_turfs)
		var/terminal_count = 0
		var/apc_count = 0
		var/machinery_count = 0
		var/list/machinery_types = list()
		for(var/obj/machinery/machine in T)
			if(!istype(machine, /obj/machinery/door) && !istype(machine, /obj/machinery/power/terminal) && !istype(machine, /obj/machinery/atmospherics/pipe))
				machinery_count++
				machinery_types += "[machine.type]"
		for(var/obj/machinery/power/terminal/terminal in T)
			terminal_count++
		for(var/obj/machinery/power/apc/apc in T)
			apc_count++
		if(terminal_count > 1)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "stacked-terminals", "Multiple power terminals occupy one tile.", generated_station_coordinate(T))
		if(apc_count > 1)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "stacked-apcs", "Multiple APCs occupy one tile.", generated_station_coordinate(T))
		if(machinery_count > 1)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "stacked-machinery", "Multiple machines occupy one tile: [jointext(machinery_types, ", ")].", generated_station_coordinate(T))
		for(var/obj/structure/bed/chair/chair in T)
			var/turf/facing = get_step(T, chair.dir)
			if(!facing || facing.density)
				validation.add(GENERATED_STATION_ISSUE_ERROR, "chair-faces-wall", "Chair faces into a wall or the map boundary.", generated_station_coordinate(chair))

	for(var/turf/simulated/floor/hall in transit_floors)
		var/open_sides = 0
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(hall, direction)
			if(generated_station_architectural_passable(neighbor))
				open_sides++
			else if(istype(neighbor, /turf/space))
				validation.add(GENERATED_STATION_ISSUE_ERROR, "hallway-open-to-space", "Transit flooring has no enclosing hull.", generated_station_coordinate(hall))
		var/entrance_apron = FALSE
		if(open_sides < 2)
			for(var/obj/machinery/door/nearby_door in range(2, hall))
				if(istype(get_area(nearby_door), /area/generated_station) && !istype(get_area(nearby_door), /area/generated_station/transit))
					entrance_apron = TRUE
					break
		if(locate(/obj/structure/bed/chair) in hall)
			entrance_apron = TRUE
		var/branch_length = open_sides < 2 ? generated_station_dead_end_branch_length(hall, transit_floors) : 0
		if(open_sides < 2 && !entrance_apron && branch_length > 3)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "hallway-dead-end", "Hallway terminates after [branch_length] tiles without a meaningful connection.", generated_station_coordinate(hall))

	if(length(transit_floors))
		var/list/reached_transit = list()
		var/list/largest_transit = list()
		for(var/turf/transit_start as anything in transit_floors)
			if(reached_transit[transit_start])
				continue
			var/list/component = list()
			var/list/transit_frontier = list(transit_start)
			while(length(transit_frontier))
				var/turf/current_transit = transit_frontier[1]
				transit_frontier.Cut(1, 2)
				if(reached_transit[current_transit])
					continue
				reached_transit[current_transit] = TRUE
				if(current_transit in transit_floors)
					component += current_transit
				for(var/direction in GLOB.cardinal)
					var/turf/neighbor = get_step(current_transit, direction)
					if((neighbor in circulation_floors) && !reached_transit[neighbor])
						transit_frontier += neighbor
			if(length(component) > length(largest_transit))
				largest_transit = component
		var/primary_coverage = length(largest_transit) / length(transit_floors)
		if(primary_coverage < GENERATED_STATION_MIN_PRIMARY_TRANSIT_COVERAGE)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "fragmented-primary-circulation", "The largest continuous circulation structure contains only [round(primary_coverage * 100, 0.1)]% of transit flooring.", station_id)

	var/list/walkable_station = list()
	for(var/turf/T as anything in station_turfs)
		if(generated_station_architectural_passable(T))
			walkable_station |= T
	if(length(walkable_station))
		var/turf/start = get_turf(entry)
		if(!(start in walkable_station))
			start = walkable_station[1]
		var/list/reached_station = list()
		var/list/frontier = list(start)
		while(length(frontier))
			var/turf/current = frontier[1]
			frontier.Cut(1, 2)
			if(reached_station[current])
				continue
			reached_station[current] = TRUE
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor = get_step(current, direction)
				if((neighbor in walkable_station) && !reached_station[neighbor])
					frontier += neighbor
		if(length(reached_station) != length(walkable_station))
			var/disconnected_count = length(walkable_station) - length(reached_station)
			var/turf/first_unreached
			var/largest_disconnected_component = 0
			var/list/disconnected_visited = list()
			for(var/turf/candidate as anything in walkable_station)
				if(reached_station[candidate] || disconnected_visited[candidate])
					continue
				if(!first_unreached)
					first_unreached = candidate
				var/component_size = 0
				var/list/component_frontier = list(candidate)
				while(length(component_frontier))
					var/turf/component_turf = component_frontier[1]
					component_frontier.Cut(1, 2)
					if(disconnected_visited[component_turf])
						continue
					disconnected_visited[component_turf] = TRUE
					component_size++
					for(var/direction in GLOB.cardinal)
						var/turf/neighbor = get_step(component_turf, direction)
						if((neighbor in walkable_station) && !reached_station[neighbor] && !disconnected_visited[neighbor])
							component_frontier += neighbor
				largest_disconnected_component = max(largest_disconnected_component, component_size)
			var/severity = largest_disconnected_component > 2 ? GENERATED_STATION_ISSUE_ERROR : GENERATED_STATION_ISSUE_WARNING
			var/code = largest_disconnected_component > 2 ? "unreachable-room-space" : "enclosed-floor-pocket"
			validation.add(severity, code, "[disconnected_count] of [length(walkable_station)] clear station tiles are disconnected; the largest pocket is [largest_disconnected_component] tiles and the first starts at [generated_station_coordinate(first_unreached)] in [get_area(first_unreached)]. Neighbors: [generated_station_neighbor_summary(first_unreached)]", station_id)

	if(length(station_turfs))
		var/bounding_area = (maximum_x - minimum_x + 1) * (maximum_y - minimum_y + 1)
		var/compactness = bounding_area / length(station_turfs)
		if(compactness > GENERATED_STATION_COMPACTNESS_LIMIT)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "station-sprawl", "Station bounding-area ratio [round(compactness, 0.01)] exceeds the clustered-layout limit [GENERATED_STATION_COMPACTNESS_LIMIT].", station_id)
		var/floor_count = 0
		for(var/turf/T as anything in station_turfs)
			if(istype(T, /turf/simulated/floor))
				floor_count++
		var/transit_ratio = length(transit_floors) / max(1, floor_count)
		if(transit_ratio > GENERATED_STATION_MAX_TRANSIT_FLOOR_RATIO)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "excessive-hallway-area", "Transit consumes [round(transit_ratio * 100, 0.1)]% of usable flooring; the architectural limit is [GENERATED_STATION_MAX_TRANSIT_FLOOR_RATIO * 100]%.", station_id)
	else
		validation.add(GENERATED_STATION_ISSUE_ERROR, "empty-station", "Materialization produced no station geometry.", station_id)
	var/datum/generated_station_architecture_metrics/metrics = architecture_metrics()
	generated_station_validate_aesthetic_metrics(metrics, validation, station_id)
	qdel(metrics)
	return validation

/// Produces a self-contained diagnostic map suitable for an admin browser or log artifact.
/// Renders one machine-checkable diagnostic layer and accumulates its nonblank cells.
/datum/generated_station_materialization/proc/diagnostic_layer(layer_id, minimum_x, minimum_y, maximum_x, maximum_y, list/counts)
	var/list/rows = list()
	var/nonblank = 0
	var/mismatches = 0
	var/fixtures = 0
	for(var/y in maximum_y to minimum_y step -1)
		var/row = ""
		for(var/x in minimum_x to maximum_x)
			var/turf/T = locate(x, y, z_level)
			var/local_x = x - origin_x + 1
			var/local_y = y - origin_y + 1
			var/datum/generated_station_tile_intent/intent = tile_plan?.tile(local_x, local_y)
			var/mark = " "
			switch(layer_id)
				if("intent")
					if(intent?.structure_kind == GENERATED_STATION_TILE_HULL)
						mark = "#"
					else if(intent?.structure_kind == GENERATED_STATION_TILE_FLOOR)
						mark = intent.owner_id == "transit" ? "+" : (intent.owner_id == "maintenance" ? "m" : "d")
					else if(intent)
						mark = "~"
					if(intent?.door_type)
						mark = "@"
				if("actual")
					if(istype(T, /turf/simulated/wall))
						mark = "#"
					else if(istype(T, /turf/simulated/floor))
						mark = "."
					else if(istype(T, /turf/space))
						mark = "~"
					if(locate(/obj/machinery/door) in T)
						mark = "@"
				if("ownership")
					if(istype(get_area(T), /area/generated_station/maintenance))
						mark = "m"
					else if(istype(get_area(T), /area/generated_station/transit))
						mark = "+"
					else if(istype(get_area(T), /area/generated_station))
						mark = "d"
				if("lighting")
					if(istype(T, /turf/simulated/floor))
						mark = "!"
						for(var/obj/machinery/light/light in range(7, T))
							if(light.status == LIGHT_OK && light.on && light.powered(LIGHT))
								mark = "."
								break
					if(locate(/obj/machinery/light) in T)
						mark = "L"
				if("content")
					if(istype(T, /turf/simulated/floor))
						mark = "."
					if(locate(/obj/machinery) in T)
						mark = "M"
					if(locate(/obj/structure/table) in T)
						mark = "t"
					if(locate(/obj/structure/closet) in T || locate(/obj/structure/filingcabinet) in T)
						mark = "s"
					if(locate(/obj/structure/bed) in T)
						mark = "b"
					if(locate(/obj/structure/bed/chair) in T)
						mark = "c"
				if("structure")
					if(istype(T, /turf/simulated/wall))
						var/turf/simulated/wall/wall = T
						mark = length(wall.wall_connections) == 4 ? "W" : "?"
					else if(locate(/obj/machinery/door) in T)
						mark = "@"
					else if(istype(T, /turf/simulated/floor))
						mark = "."
				if("mismatch")
					if(intent?.structure_kind == GENERATED_STATION_TILE_FLOOR && !istype(T, /turf/simulated/floor))
						mark = "X"
					else if(intent?.structure_kind == GENERATED_STATION_TILE_HULL && !istype(T, /turf/simulated/wall))
						mark = "X"
					else if(intent?.structure_kind == GENERATED_STATION_TILE_EXTERIOR && !istype(T, /turf/space))
						mark = "X"
					else if(intent?.door_type && !(locate(/obj/machinery/door) in T))
						mark = "X"
					else if(intent)
						mark = "."
					if(mark == "X")
						mismatches++
			if(mark != " ")
				nonblank++
			if(layer_id == "content" && mark != "." && mark != " ")
				fixtures++
			row += mark
		rows += row
	counts["[layer_id]-cells"] = nonblank
	if(layer_id == "content")
		counts["content-fixtures"] = fixtures
	if(layer_id == "mismatch")
		counts["mismatches"] = mismatches
	return jointext(rows, "\n")

/datum/generated_station_materialization/proc/diagnostic_minimap_html(datum/generated_station_validation_result/validation)
	var/minimum_x = world.maxx
	var/minimum_y = world.maxy
	var/maximum_x = 1
	var/maximum_y = 1
	var/station_turf_count = 0
	var/station_floor_count = 0
	var/transit_floor_count = 0
	var/list/frontage_by_department = list()
	for(var/x in 1 to world.maxx)
		for(var/y in 1 to world.maxy)
			var/turf/T = locate(x, y, z_level)
			if(!istype(get_area(T), /area/generated_station))
				continue
			minimum_x = min(minimum_x, x)
			minimum_y = min(minimum_y, y)
			maximum_x = max(maximum_x, x)
			maximum_y = max(maximum_y, y)
			station_turf_count++
			if(istype(T, /turf/simulated/floor))
				station_floor_count++
				if(istype(get_area(T), /area/generated_station/transit))
					transit_floor_count++
			if(!istype(get_area(T), /area/generated_station/transit))
				var/area/generated_station/department = get_area(T)
				for(var/direction in GLOB.cardinal)
					var/turf/neighbor = get_step(T, direction)
					if(istype(get_area(neighbor), /area/generated_station/transit) && istype(neighbor, /turf/simulated/floor))
						frontage_by_department[department.department_id] = (frontage_by_department[department.department_id] || 0) + 1
						break
	var/map_width = maximum_x - minimum_x + 1
	var/map_height = maximum_y - minimum_y + 1
	var/bounding_area = max(1, map_width * map_height)
	var/occupancy_percent = round(100 * station_turf_count / bounding_area, 0.1)
	var/transit_percent = round(100 * transit_floor_count / max(1, station_floor_count), 0.1)
	var/list/frontage_parts = list()
	for(var/department_id in frontage_by_department)
		frontage_parts += "[department_id]=[frontage_by_department[department_id]]"
	var/datum/generated_station_architecture_metrics/metrics = architecture_metrics()
	if(tile_plan)
		minimum_x = origin_x
		minimum_y = origin_y
		maximum_x = origin_x + tile_plan.grid_width - 1
		maximum_y = origin_y + tile_plan.grid_height - 1
		map_width = tile_plan.grid_width
		map_height = tile_plan.grid_height
	var/list/layer_counts = list()
	var/intent_layer = diagnostic_layer("intent", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/actual_layer = diagnostic_layer("actual", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/ownership_layer = diagnostic_layer("ownership", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/lighting_layer = diagnostic_layer("lighting", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/content_layer = diagnostic_layer("content", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/structure_layer = diagnostic_layer("structure", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/mismatch_layer = diagnostic_layer("mismatch", minimum_x, minimum_y, maximum_x, maximum_y, layer_counts)
	var/list/body = list("<html><body style='background:#111;color:#ddd;font-family:monospace'><h2>[station_id]</h2><div id='layer-summary' data-width='[map_width]' data-height='[map_height]' data-intent-cells='[layer_counts["intent-cells"] || 0]' data-actual-cells='[layer_counts["actual-cells"] || 0]' data-light-cells='[layer_counts["lighting-cells"] || 0]' data-content-cells='[layer_counts["content-cells"] || 0]' data-content-fixtures='[layer_counts["content-fixtures"] || 0]' data-maintenance-public-department-cells='[layer_counts["ownership-cells"] || 0]' data-structure-cells='[layer_counts["structure-cells"] || 0]' data-mismatches='[layer_counts["mismatches"] || 0]'>[map_width]x[map_height] bounding box; [station_turf_count] station turfs; [occupancy_percent]% occupied; [layer_counts["content-fixtures"] || 0] furniture/machinery fixtures; transit [transit_percent]% of flooring; [validation?.count_severity(GENERATED_STATION_ISSUE_ERROR) || 0] errors; plan mismatches [layer_counts["mismatches"] || 0].</div><p><b>Architectural metrics:</b> [metrics.summary()].</p><p><b>Structural signature:</b> [metrics.structural_signature]</p><p>Primary-circulation frontage: [jointext(frontage_parts, ", ")].</p><h3>Composite gameplay layer</h3><pre style='font-size:10px;line-height:10px'>")
	var/list/problem_coordinates = list()
	for(var/datum/generated_station_validation_issue/issue in validation?.issues)
		problem_coordinates[issue.subject_id] = TRUE
	for(var/y in maximum_y to minimum_y step -1)
		var/list/row = list()
		for(var/x in minimum_x to maximum_x)
			var/turf/T = locate(x, y, z_level)
			var/area/A = get_area(T)
			var/mark = " "
			if(istype(A, /area/generated_station/transit))
				mark = istype(T, /turf/simulated/floor) ? "+" : "#"
			else if(istype(A, /area/generated_station))
				var/area/generated_station/generated_area = A
				if(!istype(T, /turf/simulated/floor))
					mark = "#"
				else if(findtext(generated_area.department_id, "command"))
					mark = "C"
				else if(findtext(generated_area.department_id, "security"))
					mark = "S"
				else if(findtext(generated_area.department_id, "medical"))
					mark = "M"
				else if(findtext(generated_area.department_id, "engineering"))
					mark = "E"
				else if(findtext(generated_area.department_id, "logistics"))
					mark = "L"
				else if(findtext(generated_area.department_id, "docking"))
					mark = "D"
				else if(findtext(generated_area.department_id, "ai"))
					mark = "I"
				else
					mark = "."
			if(locate(/obj/structure/bed/chair) in T)
				mark = "c"
			if(locate(/obj/structure/table) in T)
				mark = "t"
			if(locate(/obj/structure/closet) in T || locate(/obj/structure/filingcabinet) in T)
				mark = "s"
			if(locate(/obj/machinery) in T)
				mark = "M"
			if(locate(/obj/machinery/power/apc) in T)
				mark = "A"
			if(locate(/obj/machinery/door) in T)
				mark = "@"
			if(problem_coordinates["[x],[y],[z_level]"])
				mark = "!"
			row += mark
		body += "[jointext(row, "")]\n"
	body += "</pre><h3>Findings</h3><ul>"
	for(var/datum/generated_station_validation_issue/issue in validation?.issues)
		body += "<li>[issue.code] ([issue.subject_id]): [issue.message]</li>"
	body += "</ul><p>Legend: # hull, + hallway, @ door, A APC, M machinery, t table, s storage, c chair, ! finding; C command, I AI, S security, E engineering, L logistics, D docking.</p>"
	body += "<details open><summary>Planned intent</summary><pre id='layer-intent'>[intent_layer]</pre></details>"
	body += "<details><summary>Actual turf</summary><pre id='layer-actual'>[actual_layer]</pre></details>"
	body += "<details><summary>Maintenance / public / department ownership</summary><pre id='layer-ownership'>[ownership_layer]</pre></details>"
	body += "<details><summary>Operational lighting coverage</summary><pre id='layer-lighting'>[lighting_layer]</pre></details>"
	body += "<details open><summary>Functional machinery and furnishings</summary><pre id='layer-content'>[content_layer]</pre></details>"
	body += "<details><summary>Structure, doors, and wall adjacency</summary><pre id='layer-structure'>[structure_layer]</pre></details>"
	body += "<details open><summary>Plan mismatches</summary><pre id='layer-mismatch'>[mismatch_layer]</pre></details></body></html>"
	qdel(metrics)
	return jointext(body, "")

/client/verb/show_generated_station_architecture()
	set name = "Show Generated Station Architecture"
	set category = "Debug"
	if(!check_rights(R_DEBUG))
		return
	var/datum/expedition_site/found_site
	for(var/key in SSexpedition?.sites)
		var/datum/expedition_site/site = SSexpedition.sites[key]
		if(site.z_level == mob?.z && site.station_materialization)
			found_site = site
			break
	if(!found_site)
		to_chat(src, span_warning("There is no generated station on your current z-level."))
		return
	var/datum/generated_station_validation_result/validation = found_site.station_materialization.validate_architecture(found_site.station_spec)
	var/html = found_site.station_materialization.diagnostic_minimap_html(validation)
	mob << browse(html, "window=generated_station_architecture;size=1000x800")
	qdel(validation)

#undef GENERATED_STATION_COMPACTNESS_LIMIT
#undef GENERATED_STATION_MAX_TRANSIT_FLOOR_RATIO
#undef GENERATED_STATION_MIN_DEPARTMENT_FRONTAGE
#undef GENERATED_STATION_MIN_PRIMARY_TRANSIT_COVERAGE
#undef GENERATED_STATION_MAX_IDENTICAL_ROOM_SHAPE_RATIO
#undef GENERATED_STATION_MAX_STRAIGHT_HALL_LENGTH
#undef GENERATED_STATION_MIN_CIRCULATION_JUNCTIONS
#undef GENERATED_STATION_MAX_DIRECT_MAIN_HALL_RATIO
#undef GENERATED_STATION_MAX_REPEATED_DOOR_INTERVAL_RATIO
