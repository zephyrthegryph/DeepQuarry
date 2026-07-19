#define GENERATED_ROOM_SCORE_INVALID -1000000

/// One resolved feature position within a generated functional room.
/datum/generated_room_placement
	var/datum/generated_room_feature/feature
	var/x
	var/y
	var/dir = SOUTH
	var/score = 0
	var/list/reserved_frontage

/datum/generated_room_placement/New()
	..()
	reserved_frontage = list()

/datum/generated_room_placement/Destroy()
	QDEL_NULL(feature)
	reserved_frontage = null
	return ..()

/// Complete, inspectable result of resolving one room definition.
/datum/generated_room_solution
	var/definition_id
	var/module_id
	var/floor_type = /turf/simulated/floor/tiled
	var/accent_color = COLOR_WHITE
	var/aesthetic_id = "general"
	var/trim_density = 0
	var/decoration_density = 0
	var/valid = FALSE
	var/score = 0
	var/floor_tiles = 0
	var/occupied_tiles = 0
	var/wall_placements = 0
	var/largest_empty_region = 0
	var/list/placements
	var/list/fragments
	var/list/circulation
	var/list/door_circulation
	var/list/occupied
	var/list/issues

/datum/generated_room_solution/New()
	..()
	placements = list()
	fragments = list()
	circulation = list()
	door_circulation = list()
	occupied = list()
	issues = list()

/datum/generated_room_solution/Destroy()
	QDEL_LIST(placements)
	QDEL_LIST(fragments)
	circulation = null
	door_circulation = null
	occupied = null
	issues = null
	return ..()

/datum/generated_room_solution/proc/tile_key(x, y)
	return "[x],[y]"

/datum/generated_room_solution/proc/reserve_circulation(x, y)
	var/key = tile_key(x, y)
	circulation[key] = TRUE
	door_circulation[key] = TRUE

/datum/generated_room_solution/proc/is_reserved(x, y)
	return circulation[tile_key(x, y)] || occupied[tile_key(x, y)]

/// Deterministic room-level constraint solver. It never consumes global rand().
/datum/generated_room_solver
	var/datum/generated_station_materializer/materializer
	var/datum/generated_station_module/module
	var/datum/generated_room_definition/definition
	var/datum/generated_room_content_plan/content_plan
	var/datum/generated_station_prng/prng
	var/datum/generated_room_solution/solution
	var/list/entrances
	var/list/candidates
	var/last_feature_base_candidates = 0
	var/last_feature_scored_candidates = 0

/datum/generated_room_solver/Destroy()
	materializer = null
	module = null
	definition = null
	QDEL_NULL(content_plan)
	QDEL_NULL(prng)
	QDEL_NULL(solution)
	entrances = null
	candidates = null
	return ..()

/datum/generated_room_solver/proc/solve(datum/generated_station_materializer/new_materializer, datum/generated_station_module/new_module, datum/generated_room_definition/new_definition, seed, faction_id, style_id)
	if(!new_materializer || !new_module || !new_definition)
		return null
	materializer = new_materializer
	module = new_module
	definition = new_definition
	if(module.x2 < module.x1 || module.y2 < module.y1)
		return null
	prng = new(seed)
	solution = new
	solution.definition_id = definition.id
	solution.module_id = module.id
	if(definition.room_style)
		solution.floor_type = definition.room_style.floor_type
		solution.accent_color = definition.room_style.accent_color
		solution.aesthetic_id = definition.room_style.aesthetic_id
		solution.trim_density = definition.room_style.trim_density
		solution.decoration_density = definition.room_style.decoration_density
	var/module_width = module.width()
	var/module_height = module.height()
	if(!module.satisfies(definition))
		solution.issues += "Room footprint [module_width]x[module_height] with [module.footprint_tiles()] usable tiles violates the [definition.min_width * definition.min_height]-[definition.max_width * definition.max_height] tile capacity contract."
		var/datum/generated_room_solution/rejected = solution
		solution = null
		return rejected
	content_plan = definition.build_content_plan(seed, faction_id, style_id)
	if(!content_plan)
		solution.issues += "Room definition did not produce a content plan."
		return solution
	discover_room_geometry()
	if(!place_fragments())
		return resolved_solution()
	if(!reserve_entrance_routes())
		solution.issues += "Authored room anchors leave no valid route between an entrance and the functional core."
		return resolved_solution()
	var/list/features = expanded_features()
	var/list/ordered_features = list()
	var/list/feature_ids = list()
	var/list/dependency_targets = list()
	for(var/datum/generated_room_feature/feature in features)
		feature_ids[feature.id] = TRUE
	for(var/datum/generated_room_feature/feature in features)
		for(var/datum/generated_room_constraint/constraint in feature.constraints)
			if(feature_ids[constraint.target_id])
				dependency_targets[constraint.target_id] = TRUE
	for(var/datum/generated_room_feature/feature in features)
		if(dependency_targets[feature.id])
			ordered_features |= feature
	for(var/datum/generated_room_feature/feature in features)
		if(feature.placement_kind == "wall" && ispath(feature.atom_type, /obj/machinery))
			ordered_features |= feature
	for(var/datum/generated_room_feature/feature in features)
		if(feature.placement_kind == "wall" && !ispath(feature.atom_type, /obj/machinery))
			ordered_features |= feature
	for(var/datum/generated_room_feature/feature in features)
		if(feature.placement_kind != "wall")
			ordered_features |= feature
	for(var/datum/generated_room_feature/feature in ordered_features)
		if(!place_feature(feature))
			var/list/placed_ids = list()
			for(var/datum/generated_room_placement/placed in solution.placements)
				placed_ids += placed.feature.id
			solution.issues += "Required feature '[feature.id]' has no valid placement after [length(placed_ids)] fixtures ([jointext(placed_ids, ", ")]); [last_feature_base_candidates] base candidates and [last_feature_scored_candidates] constraint-valid facings."
			return solution
	fill_cosmetic_density()
	measure_solution()
	// Density is a quality metric for randomized furnishing, not a runtime
	// materialization invariant. Small footprints cannot represent every target
	// ratio exactly, so the architecture tests audit it with suitable tolerance.
	solution.valid = circulation_is_valid()
	if(!solution.valid && !length(solution.issues))
		solution.issues += "Room solution failed density or circulation constraints."
	return resolved_solution()

/datum/generated_room_solver/proc/resolved_solution()
	var/datum/generated_room_solution/resolved = solution
	solution = null
	return resolved

/datum/generated_room_solver/proc/discover_room_geometry()
	entrances = list()
	candidates = list()
	var/minimum_x = module.footprint_x1 || module.x1
	var/minimum_y = module.footprint_y1 || module.y1
	var/maximum_x = module.footprint_x2 || module.x2
	var/maximum_y = module.footprint_y2 || module.y2
	for(var/x in minimum_x to maximum_x)
		for(var/y in minimum_y to maximum_y)
			if(!module.contains_tile(x, y))
				continue
			var/turf/T = materializer.world_turf(x, y)
			if(!T || T.density)
				continue
			solution.floor_tiles++
			candidates += list(list(x, y))
			var/on_edge = FALSE
			for(var/direction in GLOB.cardinal)
				var/nx = x + (direction == EAST) - (direction == WEST)
				var/ny = y + (direction == NORTH) - (direction == SOUTH)
				if(!module.contains_tile(nx, ny))
					on_edge = TRUE
					break
			if(!on_edge)
				continue
			if(locate(/obj/machinery/door) in T)
				entrances += list(list(x, y))
				continue
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor = get_step(T, direction)
				if(locate(/obj/machinery/door) in neighbor)
					entrances += list(list(x, y))
					break
	if(!length(entrances))
		entrances += list(list(round((module.x1 + module.x2) / 2), round((module.y1 + module.y2) / 2)))

/datum/generated_room_solver/proc/reserve_entrance_routes()
	var/centroid_x = round((module.x1 + module.x2) / 2)
	var/centroid_y = round((module.y1 + module.y2) / 2)
	var/center_x
	var/center_y
	var/best_distance = 1.0e31
	for(var/list/point in candidates)
		if(solution.occupied[solution.tile_key(point[1], point[2])])
			continue
		var/distance = abs(point[1] - centroid_x) + abs(point[2] - centroid_y)
		if(distance < best_distance)
			center_x = point[1]
			center_y = point[2]
			best_distance = distance
	if(!center_x || !center_y)
		return FALSE
	for(var/list/entrance in entrances)
		if(!reserve_path(entrance[1], entrance[2], center_x, center_y))
			return FALSE
	return TRUE

/// Reserves a shortest room-local route around authored fragment occupancy.
/datum/generated_room_solver/proc/reserve_path(start_x, start_y, end_x, end_y)
	var/start_key = solution.tile_key(start_x, start_y)
	var/end_key = solution.tile_key(end_x, end_y)
	var/list/frontier = list(list(start_x, start_y))
	var/list/came_from = list()
	var/list/points = list()
	came_from[start_key] = FALSE
	points[start_key] = list(start_x, start_y)
	while(length(frontier))
		var/list/current = frontier[1]
		frontier.Cut(1, 2)
		var/current_key = solution.tile_key(current[1], current[2])
		if(current_key == end_key)
			break
		for(var/direction in GLOB.cardinal)
			var/nx = current[1] + (direction == EAST) - (direction == WEST)
			var/ny = current[2] + (direction == NORTH) - (direction == SOUTH)
			var/next_key = solution.tile_key(nx, ny)
			if((next_key in came_from) || !module.contains_tile(nx, ny) || solution.occupied[next_key])
				continue
			var/turf/T = materializer.world_turf(nx, ny)
			if(!T || T.density)
				continue
			came_from[next_key] = current_key
			points[next_key] = list(nx, ny)
			frontier += list(points[next_key])
	if(!(end_key in came_from))
		return FALSE
	var/current_key = end_key
	while(current_key)
		var/list/point = points[current_key]
		solution.reserve_circulation(point[1], point[2])
		current_key = came_from[current_key]
	return TRUE

/datum/generated_room_solver/proc/expanded_features()
	var/list/features = list()
	var/list/feature_ids = list()
	for(var/feature_type in content_plan.feature_types)
		var/datum/generated_room_feature/feature = new feature_type
		if(feature_ids[feature.id])
			qdel(feature)
			continue
		feature_ids[feature.id] = TRUE
		features += feature
	var/feature_budget = max(length(features), FLOOR(solution.floor_tiles * definition.density_max, 1))
	for(var/group_type in content_plan.group_types)
		var/datum/generated_room_feature_group/group = new group_type
		var/count = max(1, group.min_instances)
		if(group.tiles_per_instance > 0)
			count = clamp(round(solution.floor_tiles / group.tiles_per_instance), group.min_instances, group.max_instances)
		else if(group.max_instances > count)
			count = prng.next_range(count, group.max_instances)
		var/features_per_instance = max(1, length(group.feature_types))
		var/affordable_instances = max(group.min_instances, FLOOR(max(0, feature_budget - length(features)) / features_per_instance, 1))
		count = min(count, affordable_instances)
		for(var/i in 1 to count)
			var/list/assembly_features = list()
			var/list/assembly_ids = list()
			for(var/feature_type in group.feature_types)
				var/datum/generated_room_feature/feature = new feature_type
				var/original_id = feature.id
				feature.id = "[original_id]-[group.id]-[i]"
				assembly_ids[original_id] = feature.id
				assembly_features += feature
			for(var/datum/generated_room_feature/feature in assembly_features)
				for(var/datum/generated_room_constraint/constraint in feature.constraints)
					constraint.subject_id = feature.id
					if(assembly_ids[constraint.target_id])
						constraint.target_id = assembly_ids[constraint.target_id]
			for(var/datum/generated_room_feature/feature in assembly_features)
				if(feature_ids[feature.id])
					qdel(feature)
					continue
				feature_ids[feature.id] = TRUE
				features += feature
		qdel(group)
	return features

/// One authored fragment footprint selected by the room solver.
/datum/generated_room_fragment_placement
	var/datum/generated_room_fragment/fragment
	var/x
	var/y
	var/rotation = 0
	var/mirrored = FALSE

/datum/generated_room_fragment_placement/Destroy()
	QDEL_NULL(fragment)
	return ..()

/datum/generated_room_solver/proc/place_fragments()
	for(var/fragment_type in content_plan.fragment_types)
		var/datum/generated_room_fragment/fragment = new fragment_type
		if(!place_fragment(fragment))
			qdel(fragment)
			continue
	return TRUE

/datum/generated_room_solver/proc/place_fragment(datum/generated_room_fragment/fragment)
	var/best_score = GENERATED_ROOM_SCORE_INVALID
	var/list/best
	for(var/x in module.x1 to module.x2 - fragment.width + 1)
		for(var/y in module.y1 to module.y2 - fragment.height + 1)
			if(fragment.anchor_edge == SOUTH && y != module.y1)
				continue
			if(fragment.anchor_edge == NORTH && y + fragment.height - 1 != module.y2)
				continue
			if(fragment.anchor_edge == WEST && x != module.x1)
				continue
			if(fragment.anchor_edge == EAST && x + fragment.width - 1 != module.x2)
				continue
			var/score = fragment_candidate_score(fragment, x, y)
			if(score > best_score)
				best_score = score
				best = list(x, y)
	if(!best)
		return FALSE
	var/datum/generated_room_fragment_placement/placement = new
	placement.fragment = fragment
	placement.x = best[1]
	placement.y = best[2]
	solution.fragments += placement
	for(var/list/offset in fragment.occupied_offsets)
		var/x = placement.x + offset[1] - 1
		var/y = placement.y + offset[2] - 1
		solution.occupied[solution.tile_key(x, y)] = placement
	return TRUE

/datum/generated_room_solver/proc/fragment_candidate_score(datum/generated_room_fragment/fragment, start_x, start_y)
	var/score = 100
	for(var/x in start_x to start_x + fragment.width - 1)
		for(var/y in start_y to start_y + fragment.height - 1)
			if(!module.contains_tile(x, y))
				return GENERATED_ROOM_SCORE_INVALID
			var/turf/T = materializer.world_turf(x, y)
			if(!T || T.density)
				return GENERATED_ROOM_SCORE_INVALID
	// Authored fragments may contain intentionally empty tiles. Circulation can
	// cross those tiles, but never an offset occupied by the fragment itself.
	for(var/list/offset in fragment.occupied_offsets)
		var/occupied_x = start_x + offset[1] - 1
		var/occupied_y = start_y + offset[2] - 1
		for(var/list/entrance in entrances)
			if(entrance[1] == occupied_x && entrance[2] == occupied_y)
				return GENERATED_ROOM_SCORE_INVALID
	if(!fragment_preserves_access(fragment, start_x, start_y))
		return GENERATED_ROOM_SCORE_INVALID
	for(var/datum/generated_room_fragment_socket/socket in fragment.sockets)
		var/socket_x = start_x
		var/socket_y = start_y
		switch(socket.edge)
			if(NORTH)
				socket_x += socket.offset - 1
				socket_y += fragment.height - 1
			if(SOUTH)
				socket_x += socket.offset - 1
			if(EAST)
				socket_x += fragment.width - 1
				socket_y += socket.offset - 1
			if(WEST)
				socket_y += socket.offset - 1
		if(socket_x < start_x || socket_x >= start_x + fragment.width || socket_y < start_y || socket_y >= start_y + fragment.height)
			if(socket.required)
				return GENERATED_ROOM_SCORE_INVALID
			continue
		var/turf/socket_turf = materializer.world_turf(socket_x, socket_y)
		var/turf/front = get_step(socket_turf, socket.edge)
		if(socket.required && !front)
			return GENERATED_ROOM_SCORE_INVALID
		// Access and circulation sockets need a clear approach. Utility sockets
		// intentionally terminate against a wall or service strip.
		if(socket.required && socket.kind != "utility" && front.density)
			return GENERATED_ROOM_SCORE_INVALID
		score += 5
	return score

/datum/generated_room_solver/proc/fragment_preserves_access(datum/generated_room_fragment/fragment, start_x, start_y)
	var/list/blocked = solution.occupied.Copy()
	for(var/list/offset in fragment.occupied_offsets)
		blocked[solution.tile_key(start_x + offset[1] - 1, start_y + offset[2] - 1)] = TRUE
	var/centroid_x = round((module.x1 + module.x2) / 2)
	var/centroid_y = round((module.y1 + module.y2) / 2)
	var/list/core
	var/best_distance = 1.0e31
	for(var/list/point in candidates)
		if(blocked[solution.tile_key(point[1], point[2])])
			continue
		var/distance = abs(point[1] - centroid_x) + abs(point[2] - centroid_y)
		if(distance < best_distance)
			core = point
			best_distance = distance
	if(!core)
		return FALSE
	var/core_key = solution.tile_key(core[1], core[2])
	for(var/list/entrance in entrances)
		var/entrance_key = solution.tile_key(entrance[1], entrance[2])
		if(blocked[entrance_key])
			return FALSE
		var/list/frontier = list(entrance)
		var/list/visited = list()
		visited[entrance_key] = TRUE
		while(length(frontier) && !visited[core_key])
			var/list/current = frontier[1]
			frontier.Cut(1, 2)
			for(var/direction in GLOB.cardinal)
				var/nx = current[1] + (direction == EAST) - (direction == WEST)
				var/ny = current[2] + (direction == NORTH) - (direction == SOUTH)
				var/next_key = solution.tile_key(nx, ny)
				if(visited[next_key] || blocked[next_key] || !module.contains_tile(nx, ny))
					continue
				var/turf/T = materializer.world_turf(nx, ny)
				if(!T || T.density)
					continue
				visited[next_key] = TRUE
				frontier += list(list(nx, ny))
		if(!visited[core_key])
			return FALSE
	return TRUE

/datum/generated_room_solver/proc/fill_cosmetic_density()
	var/target_density = min(definition.density_max, definition.density_min + solution.decoration_density)
	var/target = CEILING(solution.floor_tiles * target_density, 1)
	var/department_id = "command"
	if(materializer.nodes_by_id)
		department_id = materializer.department_id_for_module(module) || department_id
	var/list/palette = generated_room_cosmetic_palette(department_id, module.role)
	var/index = 1
	var/failed_attempts = 0
	var/maximum_attempts = max(length(palette) * 3, target * 2)
	while(visual_occupancy_count() < target && length(palette) && failed_attempts < maximum_attempts)
		var/datum/generated_room_feature/cosmetic = new
		cosmetic.id = "cosmetic-[index]"
		cosmetic.atom_type = palette[((index - 1) % length(palette)) + 1]
		if(ispath(cosmetic.atom_type, /obj/structure/bed/chair))
			cosmetic.interaction_clearance = 1
		if(ispath(cosmetic.atom_type, /obj/structure/closet) || ispath(cosmetic.atom_type, /obj/structure/filingcabinet))
			cosmetic.placement_kind = "wall"
		if(!place_feature(cosmetic))
			failed_attempts++
		index++

/datum/generated_room_feature/cosmetic
	id = "cosmetic"

/datum/generated_room_solver/proc/visual_occupancy_count()
	var/count = length(solution.placements)
	for(var/datum/generated_room_fragment_placement/placement in solution.fragments)
		count += length(placement.fragment.occupied_offsets)
	return count

/datum/generated_room_solver/proc/place_feature(datum/generated_room_feature/feature)
	var/best_score = GENERATED_ROOM_SCORE_INVALID
	var/list/best_point
	var/best_dir = SOUTH
	last_feature_base_candidates = 0
	last_feature_scored_candidates = 0
	var/offset = length(candidates) ? prng.next_range(1, length(candidates)) : 0
	for(var/i in 1 to length(candidates))
		var/index = ((i + offset - 2) % length(candidates)) + 1
		var/list/point = candidates[index]
		if(!feature_position_base_valid(feature, point[1], point[2]))
			continue
		last_feature_base_candidates++
		var/preferred_direction = preferred_facing(point[1], point[2], feature)
		for(var/direction in GLOB.cardinal)
			var/candidate_score = score_feature_position(feature, point[1], point[2], direction)
			if(candidate_score > GENERATED_ROOM_SCORE_INVALID)
				last_feature_scored_candidates++
			if(direction == preferred_direction && candidate_score > GENERATED_ROOM_SCORE_INVALID)
				candidate_score += 3
			if(candidate_score > best_score)
				best_score = candidate_score
				best_point = point
				best_dir = direction
	if(best_score <= GENERATED_ROOM_SCORE_INVALID || !best_point)
		var/list/rejections = list()
		for(var/list/point in candidates)
			var/reason = feature_position_base_rejection(feature, point[1], point[2]) || "constraints"
			rejections[reason] = (rejections[reason] || 0) + 1
		var/list/rejection_text = list()
		for(var/reason in rejections)
			rejection_text += "[reason]=[rejections[reason]]"
		solution.issues += "Candidate rejection breakdown for '[feature.id]': [jointext(rejection_text, ", ")]."
		qdel(feature)
		return FALSE
	var/datum/generated_room_placement/placement = new
	placement.feature = feature
	placement.x = best_point[1]
	placement.y = best_point[2]
	placement.dir = best_dir
	placement.score = best_score
	solution.placements += placement
	solution.occupied[solution.tile_key(placement.x, placement.y)] = placement
	reserve_frontage(placement)
	return TRUE

/datum/generated_room_solver/proc/feature_position_base_valid(datum/generated_room_feature/feature, x, y)
	return !feature_position_base_rejection(feature, x, y)

/datum/generated_room_solver/proc/feature_position_base_rejection(datum/generated_room_feature/feature, x, y)
	if(solution.is_reserved(x, y))
		return "reserved"
	var/datum/generated_station_tile_intent/tile_intent = materializer.result?.tile_plan?.tile(x, y)
	if(tile_intent?.has_utility_fixture())
		return "floor-utility"
	if(feature.placement_kind != "wall" && !ispath(feature.atom_type, /obj/structure/bed/chair) && !placement_preserves_room_connectivity(x, y))
		return "connectivity"
	var/turf/T = materializer.world_turf(x, y)
	if(!T || T.density)
		return "dense-turf"
	for(var/direction in GLOB.cardinal)
		var/turf/neighbor = get_step(T, direction)
		if(neighbor && locate(/obj/machinery/door) in neighbor)
			return "door-adjacent"
		var/neighbor_x = x + (direction == EAST) - (direction == WEST)
		var/neighbor_y = y + (direction == NORTH) - (direction == SOUTH)
		if(materializer.result?.tile_plan?.tile(neighbor_x, neighbor_y)?.door_type)
			return "planned-door-adjacent"
	for(var/atom/movable/occupant in T)
		if(occupant.density || istype(occupant, /obj/machinery/door))
			return "dense-occupant"
	if(feature.placement_kind == "wall" && !adjacent_planned_wall_direction(x, y))
		return "not-wall-adjacent"
	return null

/datum/generated_room_solver/proc/score_feature_position(datum/generated_room_feature/feature, x, y, direction)
	var/score = 100
	var/wall_direction = adjacent_planned_wall_direction(x, y)
	if(feature.placement_kind == "wall")
		score += 30
	else if(wall_direction)
		score += 4
	if(feature.interaction_clearance > 0)
		var/turf/front = materializer.world_turf(x + (direction == EAST) - (direction == WEST), y + (direction == NORTH) - (direction == SOUTH))
		if(!front || front.density || solution.is_reserved(front.x - materializer.min_x + 1, front.y - materializer.min_y + 1))
			return GENERATED_ROOM_SCORE_INVALID
	for(var/datum/generated_room_constraint/constraint in feature.constraints)
		var/value = score_constraint(constraint, x, y, direction)
		if(value <= GENERATED_ROOM_SCORE_INVALID && constraint.hard)
			return GENERATED_ROOM_SCORE_INVALID
		score += max(-100, value) * constraint.weight
	// Wall equipment belongs on the service perimeter. Freestanding functional
	// assemblies belong near the room core so the solver produces work islands
	// and seating groups instead of an empty center with a ring of loose props.
	var/center_distance = abs(x - round((module.x1 + module.x2) / 2)) + abs(y - round((module.y1 + module.y2) / 2))
	if(feature.placement_kind == "wall")
		score += center_distance
	else
		score -= center_distance * 2
	return score

/// Ensures furnishings cannot create sealed pockets of otherwise walkable floor.
/datum/generated_room_solver/proc/placement_preserves_room_connectivity(blocked_x, blocked_y)
	var/list/available = list()
	var/list/first
	for(var/list/point in candidates)
		var/x = point[1]
		var/y = point[2]
		if((x == blocked_x && y == blocked_y) || solution.occupied[solution.tile_key(x, y)])
			continue
		var/key = solution.tile_key(x, y)
		available[key] = point
		if(!first)
			first = point
	if(!first)
		return TRUE
	var/list/reached = list()
	var/list/frontier = list(first)
	while(length(frontier))
		var/list/current = frontier[1]
		frontier.Cut(1, 2)
		var/current_key = solution.tile_key(current[1], current[2])
		if(reached[current_key])
			continue
		reached[current_key] = TRUE
		for(var/direction in GLOB.cardinal)
			var/nx = current[1] + (direction == EAST) - (direction == WEST)
			var/ny = current[2] + (direction == NORTH) - (direction == SOUTH)
			var/next_key = solution.tile_key(nx, ny)
			if(available[next_key] && !reached[next_key])
				frontier += list(available[next_key])
	return length(reached) == length(available)

/datum/generated_room_solver/proc/score_constraint(datum/generated_room_constraint/constraint, x, y, direction)
	if(istype(constraint, /datum/generated_room_constraint/against_wall))
		return adjacent_planned_wall_direction(x, y) ? 10 : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/in_corner))
		var/walls = 0
		for(var/cardinal in GLOB.cardinal)
			var/nx = x + (cardinal == EAST) - (cardinal == WEST)
			var/ny = y + (cardinal == NORTH) - (cardinal == SOUTH)
			var/datum/generated_station_tile_intent/intent = materializer.result?.tile_plan?.tile(nx, ny)
			if(intent?.is_structural_wall())
				walls++
		return walls >= 2 ? 15 : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/visible_from_entrance))
		var/minimum = 1000
		for(var/list/entrance in entrances)
			minimum = min(minimum, abs(x - entrance[1]) + abs(y - entrance[2]))
		return max(0, 12 - minimum)
	if(istype(constraint, /datum/generated_room_constraint/near_feature))
		var/datum/generated_room_placement/target = placement_by_id(constraint.target_id)
		if(!target)
			return constraint.hard ? GENERATED_ROOM_SCORE_INVALID : 0
		var/distance = abs(x - target.x) + abs(y - target.y)
		return distance <= max(1, constraint.radius) ? 10 - distance : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/faces_feature))
		var/datum/generated_room_placement/target = placement_by_id(constraint.target_id)
		if(!target)
			return constraint.hard ? GENERATED_ROOM_SCORE_INVALID : 0
		var/distance = abs(x - target.x) + abs(y - target.y)
		return distance <= 2 ? 16 - distance * 3 : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/separated_from))
		var/datum/generated_room_placement/target = placement_by_id(constraint.target_id)
		if(!target)
			return 0
		var/distance = abs(x - target.x) + abs(y - target.y)
		return distance >= max(1, constraint.radius) ? distance : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/clear_radius))
		return area_is_clear(x, y, max(1, constraint.radius)) ? 10 : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/clear_frontage))
		return frontage_is_clear(x, y, direction, max(1, constraint.radius)) ? 10 : GENERATED_ROOM_SCORE_INVALID
	if(istype(constraint, /datum/generated_room_constraint/requires_access_path))
		return frontage_is_clear(x, y, direction, 1) ? 10 : GENERATED_ROOM_SCORE_INVALID
	return 0

/datum/generated_room_solver/proc/placement_by_id(id)
	for(var/datum/generated_room_placement/placement in solution.placements)
		if(placement.feature.id == id)
			return placement
	return null

/datum/generated_room_solver/proc/adjacent_wall_direction(x, y)
	var/turf/T = materializer.world_turf(x, y)
	for(var/direction in GLOB.cardinal)
		if(get_step(T, direction)?.density)
			return direction
	return 0

/// Returns a wall supplied by the authoritative tile plan, rather than treating
/// temporary density or a furnishing as architectural support for a fixture.
/datum/generated_room_solver/proc/adjacent_planned_wall_direction(x, y)
	for(var/direction in GLOB.cardinal)
		var/nx = x + (direction == EAST) - (direction == WEST)
		var/ny = y + (direction == NORTH) - (direction == SOUTH)
		var/datum/generated_station_tile_intent/intent = materializer.result?.tile_plan?.tile(nx, ny)
		if(intent?.is_structural_wall())
			return direction
	return 0

/datum/generated_room_solver/proc/preferred_facing(x, y, datum/generated_room_feature/feature)
	for(var/datum/generated_room_constraint/faces_feature/constraint in feature.constraints)
		var/datum/generated_room_placement/target = placement_by_id(constraint.target_id)
		if(target)
			return cardinal_direction_toward(x, y, target.x, target.y)
	var/wall_direction = adjacent_planned_wall_direction(x, y)
	if(wall_direction)
		return turn(wall_direction, 180)
	return cardinal_direction_toward(x, y, round((module.x1 + module.x2) / 2), round((module.y1 + module.y2) / 2))

/datum/generated_room_solver/proc/cardinal_direction_toward(from_x, from_y, to_x, to_y)
	var/dx = to_x - from_x
	var/dy = to_y - from_y
	if(abs(dx) >= abs(dy) && dx)
		return dx > 0 ? EAST : WEST
	if(dy)
		return dy > 0 ? NORTH : SOUTH
	return SOUTH

/datum/generated_room_solver/proc/area_is_clear(x, y, radius)
	for(var/check_x in max(module.footprint_x1, x - radius) to min(module.footprint_x2, x + radius))
		for(var/check_y in max(module.footprint_y1, y - radius) to min(module.footprint_y2, y + radius))
			if(check_x == x && check_y == y)
				continue
			if(solution.occupied[solution.tile_key(check_x, check_y)])
				return FALSE
	return TRUE

/datum/generated_room_solver/proc/frontage_is_clear(x, y, direction, distance)
	for(var/i in 1 to distance)
		x += (direction == EAST) - (direction == WEST)
		y += (direction == NORTH) - (direction == SOUTH)
		if(!module.contains_tile(x, y) || solution.occupied[solution.tile_key(x, y)])
			return FALSE
		var/turf/T = materializer.world_turf(x, y)
		if(!T || T.density)
			return FALSE
	return TRUE

/datum/generated_room_solver/proc/reserve_frontage(datum/generated_room_placement/placement)
	var/distance = max(0, placement.feature.interaction_clearance)
	if(!(placement.dir in GLOB.cardinal))
		placement.dir = SOUTH
	for(var/i in 1 to distance)
		var/x = placement.x + ((placement.dir == EAST) - (placement.dir == WEST)) * i
		var/y = placement.y + ((placement.dir == NORTH) - (placement.dir == SOUTH)) * i
		var/key = solution.tile_key(x, y)
		solution.circulation[key] = TRUE
		placement.reserved_frontage += key

/datum/generated_room_solver/proc/circulation_is_valid()
	for(var/list/entrance in entrances)
		if(solution.occupied[solution.tile_key(entrance[1], entrance[2])])
			return FALSE
	return TRUE

/datum/generated_room_solver/proc/measure_solution()
	solution.occupied_tiles = visual_occupancy_count()
	for(var/datum/generated_room_placement/placement in solution.placements)
		solution.score += placement.score
		if(adjacent_planned_wall_direction(placement.x, placement.y))
			solution.wall_placements++
	solution.largest_empty_region = largest_empty_region()
	var/density = solution.floor_tiles ? solution.occupied_tiles / solution.floor_tiles : 0
	solution.score -= round(abs(density - ((definition.density_min + definition.density_max) / 2)) * 100)
	solution.score -= solution.largest_empty_region

/datum/generated_room_solver/proc/density_is_valid()
	if(!solution.floor_tiles)
		return FALSE
	var/density = solution.occupied_tiles / solution.floor_tiles
	if(density < definition.density_min || density > definition.density_max)
		solution.issues += "Occupied density [density] is outside [definition.density_min]-[definition.density_max]."
		return FALSE
	return TRUE

/datum/generated_room_solver/proc/largest_empty_region()
	var/list/visited = list()
	var/largest = 0
	for(var/list/point in candidates)
		var/key = solution.tile_key(point[1], point[2])
		if(visited[key] || solution.is_reserved(point[1], point[2]))
			continue
		var/size = 0
		var/list/frontier = list(point)
		visited[key] = TRUE
		while(length(frontier))
			var/list/current = frontier[1]
			frontier.Cut(1, 2)
			size++
			for(var/direction in GLOB.cardinal)
				var/nx = current[1] + (direction == EAST) - (direction == WEST)
				var/ny = current[2] + (direction == NORTH) - (direction == SOUTH)
				var/next_key = solution.tile_key(nx, ny)
				if(!module.contains_tile(nx, ny) || visited[next_key] || solution.is_reserved(nx, ny))
					continue
				visited[next_key] = TRUE
				frontier += list(list(nx, ny))
		largest = max(largest, size)
	return largest

/// Instantiates a solved feature set after every hard constraint has passed.
/datum/generated_station_materializer/proc/materialize_room_solution(datum/generated_room_solution/solution)
	if(!solution?.valid)
		return FALSE
	var/owned_start = length(result.owned_furnishing_atoms)
	var/furnishing_start = length(result.furnishings)
	var/styled_start = result.styled_floor_count
	var/accent_start = result.accent_decal_count
	if(!style_room_solution(solution))
		return FALSE
	for(var/datum/generated_room_fragment_placement/fragment_placement in solution.fragments)
		var/turf/origin = world_turf(fragment_placement.x, fragment_placement.y)
		if(!fragment_placement.fragment.materialize(origin, fragment_placement.rotation, fragment_placement.mirrored, result))
			rollback_room_materialization(owned_start, furnishing_start, styled_start, accent_start)
			return FALSE
	for(var/datum/generated_room_placement/placement in solution.placements)
		if(!placement.feature.atom_type)
			continue
		var/turf/T = world_turf(placement.x, placement.y)
		if(!T || T.density)
			rollback_room_materialization(owned_start, furnishing_start, styled_start, accent_start)
			return FALSE
		var/atom/movable/created = new placement.feature.atom_type(T)
		created.set_dir(placement.dir)
		result.register_furnishing(created)
	return TRUE

/datum/generated_station_materializer/proc/rollback_room_materialization(owned_start, furnishing_start, styled_start, accent_start)
	for(var/i in length(result.owned_furnishing_atoms) to owned_start + 1 step -1)
		var/atom/movable/created = result.owned_furnishing_atoms[i]
		if(created && !QDELETED(created))
			qdel(created)
	result.owned_furnishing_atoms.Cut(owned_start + 1)
	result.furnishings.Cut(furnishing_start + 1)
	result.styled_floor_count = styled_start
	result.accent_decal_count = accent_start

/// Applies Southern Cross-style flooring and an inset department-color room outline.
/datum/generated_station_materializer/proc/style_room_solution(datum/generated_room_solution/solution)
	var/datum/generated_station_module/module
	for(var/datum/generated_station_module/candidate in result.modules)
		if(candidate.id == solution.module_id)
			module = candidate
			break
	if(!module || !ispath(solution.floor_type, /turf/simulated/floor))
		return FALSE
	var/area/generated_station/department_area = module_areas[module.id] || department_areas[module.department_node_id]
	for(var/x in module.footprint_x1 to module.footprint_x2)
		for(var/y in module.footprint_y1 to module.footprint_y2)
			if(!module.contains_tile(x, y))
				continue
			var/turf/T = world_turf(x, y)
			if(!istype(T, /turf/simulated/floor) || get_area(T) != department_area)
				continue
			result.styled_floor_count++
			for(var/direction in GLOB.cardinal)
				var/nx = x + (direction == EAST) - (direction == WEST)
				var/ny = y + (direction == NORTH) - (direction == SOUTH)
				if(module.contains_tile(nx, ny))
					continue
				var/obj/effect/floor_decal/borderfloor/decal = new(T, direction, solution.accent_color)
				result.register_furnishing(decal)
				result.accent_decal_count++
	return TRUE

/// Synthesizes every functional room from typed definitions rather than palettes.
/datum/generated_station_materializer/proc/resolve_room_definition(department_id, role)
	return generated_room_definition_for(department_id, role)

/datum/generated_station_materializer/proc/resolve_compact_room_definition(department_id, role)
	return generated_compact_room_definition_for(department_id, role)

/datum/generated_station_materializer/proc/resolve_minimum_room_definition(department_id, role)
	return generated_minimum_room_definition_for(department_id, role)

/datum/generated_station_materializer/proc/synthesize_rooms()
	for(var/datum/generated_station_module/module in result.modules)
		var/department_id = department_id_for_module(module)
		var/datum/generated_room_definition/primary_definition = resolve_room_definition(department_id, module.role)
		if(!primary_definition)
			continue
		var/dimensions_fit = (module.width() >= primary_definition.min_width && module.height() >= primary_definition.min_height) || (module.width() >= primary_definition.min_height && module.height() >= primary_definition.min_width)
		if(module.footprint_tiles() < 9 || !dimensions_fit)
			qdel(primary_definition)
			primary_definition = resolve_compact_room_definition(department_id, module.role)
		var/list/definitions = list(primary_definition)
		if(!findtext(primary_definition.id, "-compact-"))
			definitions += resolve_compact_room_definition(department_id, module.role)
		definitions += resolve_minimum_room_definition(department_id, module.role)
		var/room_seed = spec.seed + length(result.modules) * 7919 + module.x1 * 101 + module.y1 * 313
		var/resolved = FALSE
		var/attempt = 0
		for(var/datum/generated_room_definition/definition in definitions)
			attempt++
			var/datum/generated_room_solver/solver = new
			var/datum/generated_room_solution/room_solution = solver.solve(src, module, definition, room_seed + attempt * 104729, spec.faction_id, spec.architecture_style)
			var/materialized = room_solution?.valid && materialize_room_solution(room_solution)
			if(materialized)
				if(attempt > 1)
					var/degradation = "room [module.id] used [definition.id] after authored content could not fit"
					result.degradation_events += degradation
					log_world("Generated station [spec.id] degraded [degradation].")
				result.room_solutions += room_solution
				resolved = TRUE
				qdel(solver)
				break
			var/details = room_solution ? jointext(room_solution.issues, "; ") : "solver returned no solution"
			if(!length(details))
				details = "room solution could not be committed"
			last_failure_details = "room [module.id] ([definition.id]): [details]"
			log_world("Generated station room [module.id] ([module.width()]x[module.height()] core, [module.footprint_tiles()] footprint tiles) rejected [definition.id]: [details]")
			qdel(room_solution)
			qdel(solver)
			if(strict_room_contracts)
				QDEL_LIST(definitions)
				return FALSE
		QDEL_LIST(definitions)
		if(!resolved)
			return FALSE
		CHECK_TICK
	return TRUE

#undef GENERATED_ROOM_SCORE_INVALID
