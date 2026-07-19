#define GENERATED_STATION_SERVICE_MAINTENANCE "maintenance"

/// A deterministic functional subdivision inside a department rectangle.
/datum/generated_station_module
	var/id
	var/department_node_id
	var/role
	var/x1
	var/y1
	var/x2
	var/y2
	/// Inclusive rectangular area reserved for authored fragments and required machinery.
	var/core_x1
	var/core_y1
	var/core_x2
	var/core_y2
	var/footprint_x1
	var/footprint_y1
	var/footprint_x2
	var/footprint_y2
	/// Every walkable planner-local tile belonging to the room, including irregular bays.
	var/list/footprint

/datum/generated_station_module/New()
	..()
	footprint = list()

/datum/generated_station_module/Destroy()
	footprint = null
	return ..()

/datum/generated_station_module/proc/tile_key(x, y)
	return "[x],[y]"

/datum/generated_station_module/proc/add_footprint_tile(x, y)
	footprint[tile_key(x, y)] = TRUE

/datum/generated_station_module/proc/contains_tile(x, y)
	if(!length(footprint))
		return x >= x1 && x <= x2 && y >= y1 && y <= y2
	return footprint[tile_key(x, y)]

/datum/generated_station_module/proc/footprint_tiles()
	return length(footprint)

/datum/generated_station_module/proc/width()
	return core_x2 ? core_x2 - core_x1 + 1 : x2 - x1 + 1

/datum/generated_station_module/proc/height()
	return core_y2 ? core_y2 - core_y1 + 1 : y2 - y1 + 1

/datum/generated_station_module/proc/satisfies(datum/generated_room_definition/definition)
	if(!definition)
		return FALSE
	if(!length(footprint))
		return definition.accepts_dimensions(width(), height())
	var/usable_tiles = footprint_tiles()
	var/minimum_irregular_area = ceil(definition.min_width * definition.min_height * GENERATED_STATION_IRREGULAR_ROOM_MINIMUM_AREA_RATIO)
	var/minimum_short_side = definition.allow_narrow_irregular ? 2 : 3
	return usable_tiles >= minimum_irregular_area && usable_tiles <= definition.max_width * definition.max_height && min(width(), height()) >= minimum_short_side

/// A department-local connection to one station service.
/datum/generated_station_service_endpoint
	var/id
	var/department_node_id
	var/service_id
	var/x
	var/y
	var/obj/effect/landmark/generated_station_service/landmark

/datum/generated_station_service_endpoint/Destroy()
	QDEL_NULL(landmark)
	return ..()

/// A route between two service endpoints, stored in planner-local coordinates.
/datum/generated_station_service_route
	var/id
	var/service_id
	var/from_endpoint_id
	var/to_endpoint_id
	var/list/path
	var/list/physical_markers

/datum/generated_station_service_route/New()
	..()
	path = list()
	physical_markers = list()

/datum/generated_station_service_route/Destroy()
	QDEL_LIST(physical_markers)
	path = null
	return ..()

/obj/effect/landmark/generated_station_department_core
	name = "generated department control point"
	var/station_id
	var/department_node_id
	var/module_role

/obj/effect/landmark/generated_station_department_core/Destroy()
	return ..(TRUE)

/obj/effect/landmark/generated_station_service
	name = "generated station service endpoint"
	invisibility = INVISIBILITY_ABSTRACT
	var/station_id
	var/department_node_id
	var/service_id

/obj/effect/landmark/generated_station_service/Destroy()
	return ..(TRUE)

/obj/effect/landmark/generated_station_service_route
	name = "generated station service route"
	invisibility = INVISIBILITY_ABSTRACT
	var/station_id
	var/service_id

/obj/effect/landmark/generated_station_service_route/Destroy()
	return ..(TRUE)

/proc/generated_station_module_roles(department_id)
	switch(department_id)
		if("command")
			return list("operations", "communications")
		if("ai")
			return list("core", "support")
		if("security")
			return list("operations", "brig")
		if("medical")
			return list("treatment", "ward")
		if("engineering")
			return list("power", "atmospherics")
		if("logistics")
			return list("cargo", "processing")
		if("docking")
			return list("control", "berth")
	return list("control", "support")

/// Chooses a divider that satisfies both room contracts and wastes the least usable width.
/datum/generated_station_materializer/proc/generated_module_division(datum/generated_station_layout_node/node, department_id, list/roles)
	var/interior_width = node.width - 2
	var/interior_height = node.height - 2
	var/list/best
	for(var/split_vertical in list(TRUE, FALSE))
		var/available = (split_vertical ? interior_width : interior_height) - 1
		for(var/first_size in 3 to available - 3)
			var/second_size = available - first_size
			for(var/shape_shift in list(-1, 1, 0))
				var/datum/generated_room_definition/first_definition = generated_room_definition_for(department_id, roles[1])
				var/datum/generated_room_definition/second_definition = generated_room_definition_for(department_id, roles[2])
				if(!first_definition || !second_definition)
					qdel(first_definition)
					qdel(second_definition)
					continue
				var/first_span = first_size - (shape_shift < 0)
				var/second_span = second_size - (shape_shift > 0)
				var/first_width = split_vertical ? first_span : interior_width
				var/first_height = split_vertical ? interior_height : first_span
				var/second_width = split_vertical ? second_span : interior_width
				var/second_height = split_vertical ? interior_height : second_span
				var/valid = first_definition.accepts_dimensions(first_width, first_height) && second_definition.accepts_dimensions(second_width, second_height)
				var/score = valid ? first_definition.dimension_score(first_width, first_height) + second_definition.dimension_score(second_width, second_height) + (shape_shift ? 2 : 0) : -1
				qdel(first_definition)
				qdel(second_definition)
				if(score < 0 || (best && score <= best[3]))
					continue
				best = list(split_vertical, first_size, score, shape_shift)
	return best

/datum/generated_station_materializer/proc/build_internal_modules()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_department_instance/department = department_for_node(node)
		if(!department)
			continue
		var/list/roles = generated_station_module_roles(department.definition.id)
		if(spec.grid_width >= 96 && spec.grid_height >= 96)
			if(!build_large_department_modules(node, department.definition.id, roles))
				log_world("Generated station department [node.id] ([node.width]x[node.height]) cannot satisfy its expanded room program.")
				return FALSE
			continue
		var/list/division = generated_module_division(node, department.definition.id, roles)
		if(!division)
			log_world("Generated station department [node.id] ([node.width]x[node.height]) cannot satisfy its room program.")
			return FALSE
		var/split_vertical = division[1]
		var/first_size = division[2]
		var/shape_shift = division[4]
		var/split = split_vertical ? node.x + first_size + 1 : node.y + first_size + 1
		var/list/department_modules = list()
		for(var/i in 1 to 2)
			var/datum/generated_station_module/module = new
			module.id = "[node.id]-[roles[i]]"
			module.department_node_id = node.id
			module.role = roles[i]
			module.core_x1 = node.x + 1
			module.core_y1 = node.y + 1
			module.core_x2 = node.x + node.width - 2
			module.core_y2 = node.y + node.height - 2
			module.footprint_x1 = node.x + 1
			module.footprint_y1 = node.y + 1
			module.footprint_x2 = node.x + node.width - 2
			module.footprint_y2 = node.y + node.height - 2
			if(split_vertical)
				if(i == 1)
					module.core_x2 = split - 1 + min(0, shape_shift)
				else
					module.core_x1 = split + 1 + max(0, shape_shift)
			else if(i == 1)
				module.core_y2 = split - 1 + min(0, shape_shift)
			else
				module.core_y1 = split + 1 + max(0, shape_shift)
			module.x1 = module.core_x1
			module.y1 = module.core_y1
			module.x2 = module.core_x2
			module.y2 = module.core_y2
			result.modules += module
			department_modules += module
		var/door_coordinate = split_vertical ? node.y + round(node.height / 2) : node.x + round(node.width / 2)
		for(var/offset in 1 to (split_vertical ? node.height - 2 : node.width - 2))
			var/in_bay = offset <= max(2, round((split_vertical ? node.height : node.width) / 3))
			var/local_split = split + (in_bay ? shape_shift : 0)
			var/local_x = split_vertical ? local_split : node.x + offset
			var/local_y = split_vertical ? node.y + offset : local_split
			for(var/cross in 1 to (split_vertical ? node.width - 2 : node.height - 2))
				var/cross_x = split_vertical ? node.x + cross : local_x
				var/cross_y = split_vertical ? local_y : node.y + cross
				if((split_vertical ? cross_x : cross_y) == local_split)
					continue
				var/module_index = (split_vertical ? cross_x : cross_y) < local_split ? 1 : 2
				var/datum/generated_station_module/owner = department_modules[module_index]
				owner.add_footprint_tile(cross_x, cross_y)
			var/turf/T = world_turf(local_x, local_y)
			if(!T)
				continue
			if((split_vertical ? local_y : local_x) == door_coordinate)
				T.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
				var/obj/machinery/door/airlock/airlock = new(T)
				result.doors += airlock
				result.door_count++
			else
				T.ChangeTurf(/turf/simulated/wall, tell_universe = FALSE)
				result.wall_count++
		var/datum/generated_station_module/control_module = result.modules[length(result.modules) - 1]
		var/turf/control_turf = world_turf(round((control_module.x1 + control_module.x2) / 2), round((control_module.y1 + control_module.y2) / 2))
		if(control_turf)
			var/obj/effect/landmark/generated_station_department_core/core = new(control_turf)
			core.station_id = spec.id
			core.department_node_id = node.id
			core.module_role = control_module.role
			result.control_landmarks += core
	return TRUE

/// Builds an expanded department as a compact cluster around a foyer and a
/// bent internal street. Room footprints include deterministic alcoves and
/// setbacks so the room program, rather than a uniform quadrant, owns the
/// department's usable space.
/datum/generated_station_materializer/proc/build_large_department_modules(datum/generated_station_layout_node/node, department_id, list/roles)
	if(length(roles) < 2)
		return FALSE
	var/interior_x1 = node.x + 1
	var/interior_y1 = node.y + 1
	var/interior_x2 = node.x + node.width - 2
	var/interior_y2 = node.y + node.height - 2
	var/street_x = round((interior_x1 + interior_x2) / 2)
	var/street_y = round((interior_y1 + interior_y2) / 2)
	if(street_x + 5 > interior_x2 || street_y + 5 > interior_y2)
		return FALSE
	var/list/bounds = list(
		list(interior_x1, interior_y1, street_x - 2, street_y - 2),
		list(street_x + 2, interior_y1, interior_x2, street_y - 2),
		list(interior_x1, street_y + 2, street_x - 2, interior_y2),
		list(street_x + 2, street_y + 2, interior_x2, interior_y2),
	)
	var/list/shape_variants = list("northwest-notch", "south-bay", "service-notch", "foyer-wrap")

	// Begin with structure everywhere. Floors are carved only where circulation
	// or a solved room requires them, leaving useful wall thickness and alcoves.
	for(var/x in interior_x1 to interior_x2)
		for(var/y in interior_y1 to interior_y2)
			var/turf/interior = world_turf(x, y)
			if(interior)
				interior.ChangeTurf(/turf/simulated/wall, tell_universe = FALSE)
				result.wall_count++

	// The local street bends into a three-tile foyer. The widened terminus is a
	// motif socket suitable for reception fragments and department landmarks.
	for(var/y in interior_y1 to interior_y2)
		carve_department_cluster_floor(node, street_x, y)
	for(var/x in interior_x1 to interior_x2)
		carve_department_cluster_floor(node, x, street_y)
	for(var/x in street_x + 1 to min(street_x + 3, interior_x2))
		for(var/y in street_y + 1 to min(street_y + 2, interior_y2))
			carve_department_cluster_floor(node, x, y)
	for(var/x in max(street_x + 5, interior_x1) to interior_x2)
		for(var/y in max(interior_y1, street_y - 1) to min(interior_y2, street_y + 1))
			carve_department_cluster_floor(node, x, y)
	var/list/department_modules = list()
	for(var/i in 1 to length(bounds))
		var/role = roles[((i - 1) % length(roles)) + 1]
		var/list/room_bounds = bounds[i]
		var/datum/generated_room_definition/definition = generated_room_definition_for(department_id, role)
		var/room_width = room_bounds[3] - room_bounds[1] + 1
		var/room_height = room_bounds[4] - room_bounds[2] + 1
		if(!definition?.accepts_dimensions(room_width, room_height))
			qdel(definition)
			result.modules -= department_modules
			QDEL_LIST(department_modules)
			return FALSE
		var/has_authored_fragment = length(definition.fragment_options)
		qdel(definition)
		var/datum/generated_station_module/module = new
		module.id = "[node.id]-[role]-[i <= length(roles) ? 1 : 2]"
		module.department_node_id = node.id
		module.role = role
		module.x1 = room_bounds[1]
		module.y1 = room_bounds[2]
		module.x2 = room_bounds[3]
		module.y2 = room_bounds[4]
		module.core_x1 = module.x1
		module.core_y1 = module.y1
		module.core_x2 = module.x2
		module.core_y2 = module.y2
		module.footprint_x1 = module.x1
		module.footprint_y1 = module.y1
		module.footprint_x2 = module.x2
		module.footprint_y2 = module.y2
		for(var/x in module.x1 to module.x2)
			for(var/y in module.y1 to module.y2)
				if(generated_station_hull_setback(node, x, y) || (!has_authored_fragment && generated_station_cluster_notch(shape_variants[i], x, y, module)))
					continue
				module.add_footprint_tile(x, y)
				carve_department_cluster_floor(node, x, y)
		result.modules += module
		department_modules += module
	var/list/door_points = list(
		list(street_x - 1, round((bounds[1][2] + bounds[1][4]) / 2)),
		list(street_x + 1, round((bounds[2][2] + bounds[2][4]) / 2)),
		list(street_x - 1, round((bounds[3][2] + bounds[3][4]) / 2)),
		list(street_x + 1, round((bounds[4][2] + bounds[4][4]) / 2)),
	)
	for(var/list/point in door_points)
		var/turf/door_turf = world_turf(point[1], point[2])
		if(!door_turf)
			continue
		door_turf.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
		var/obj/machinery/door/airlock/airlock = new(door_turf)
		result.doors += airlock
		result.door_count++
	var/datum/generated_station_module/control_module = department_modules[length(department_modules)]
	var/turf/control_turf = world_turf(round((control_module.x1 + control_module.x2) / 2), round((control_module.y1 + control_module.y2) / 2))
	if(control_turf)
		var/obj/effect/landmark/generated_station_department_core/core = new(control_turf)
		core.station_id = spec.id
		core.department_node_id = node.id
		core.module_role = control_module.role
		result.control_landmarks += core
	return TRUE

/// Converts one planner-local position into finished department circulation.
/datum/generated_station_materializer/proc/carve_department_cluster_floor(datum/generated_station_layout_node/node, local_x, local_y)
	var/turf/T = world_turf(local_x, local_y)
	if(!T)
		return
	T.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
	var/area/generated_station/department_area = department_areas[node.id]
	if(department_area)
		ChangeArea(T, department_area)
	result.floor_count++

/// Returns TRUE for a small corner removed from an otherwise rectangular room.
/// Each variant keeps the footprint connected while producing a different
/// furnishing wall and a natural recess beside circulation.
/proc/generated_station_cluster_notch(shape_variant, x, y, datum/generated_station_module/module)
	switch(shape_variant)
		if("northwest-notch")
			return x <= module.x1 + 1 && y >= module.y2 - 1
		if("south-bay")
			return x >= module.x2 - 1 && y <= module.y1
		if("service-notch")
			return x >= module.x2 - 1 && y >= module.y2 - 1
		if("foyer-wrap")
			return x <= module.x1 + 2 && y <= module.y1 + 1
	return FALSE

/// Keeps a two-tile structural shoulder behind each exterior corner.
/proc/generated_station_hull_setback(datum/generated_station_layout_node/node, x, y)
	var/near_west = x == node.x + 1
	var/near_east = x == node.x + node.width - 2
	var/near_south = y == node.y + 1
	var/near_north = y == node.y + node.height - 2
	return (near_west || near_east) && (near_south || near_north)

/datum/generated_station_materializer/proc/services_for_department(datum/generated_station_department_instance/department)
	var/list/services = list(GENERATED_STATION_SERVICE_MAINTENANCE)
	for(var/datum/generated_station_capability_requirement/requirement in department.definition.requirements)
		services |= requirement.capability_id
	for(var/datum/generated_station_capability_provision/provision in department.definition.provisions)
		services |= provision.capability_id
	return services

/datum/generated_station_materializer/proc/build_service_endpoints()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_department_instance/department = department_for_node(node)
		if(!department)
			continue
		var/list/services = services_for_department(department)
		var/list/available_turfs = list()
		for(var/local_x in node.x + 1 to node.x + node.width - 2)
			for(var/local_y in node.y + 1 to node.y + node.height - 2)
				var/turf/candidate = world_turf(local_x, local_y)
				if(candidate && !candidate.density)
					available_turfs += candidate
		for(var/i in 1 to length(services))
			var/service_id = services[i]
			var/datum/generated_station_service_endpoint/endpoint = new
			endpoint.id = "endpoint-[node.id]-[service_id]"
			endpoint.department_node_id = node.id
			endpoint.service_id = service_id
			var/turf/T = length(available_turfs) ? available_turfs[((i - 1) % length(available_turfs)) + 1] : null
			if(T)
				endpoint.x = T.x - min_x + 1
				endpoint.y = T.y - min_y + 1
				endpoint.landmark = new(T)
				endpoint.landmark.station_id = spec.id
				endpoint.landmark.department_node_id = node.id
				endpoint.landmark.service_id = service_id
			result.service_endpoints += endpoint

/datum/generated_station_materializer/proc/endpoint_for(node_id, service_id)
	for(var/datum/generated_station_service_endpoint/endpoint in result.service_endpoints)
		if(endpoint.department_node_id == node_id && endpoint.service_id == service_id)
			return endpoint
	return null

/datum/generated_station_materializer/proc/service_for_utility_edge(datum/generated_station_layout_edge/edge)
	if(edge.service_id)
		return edge.service_id
	var/datum/generated_station_layout_node/from_node = nodes_by_id[edge.from_node_id]
	var/datum/generated_station_layout_node/to_node = nodes_by_id[edge.to_node_id]
	var/datum/generated_station_department_instance/provider = department_for_node(from_node)
	var/datum/generated_station_department_instance/consumer = department_for_node(to_node)
	for(var/datum/generated_station_capability_provision/provision in provider?.definition?.provisions)
		for(var/datum/generated_station_capability_requirement/requirement in consumer?.definition?.requirements)
			if(provision.capability_id == requirement.capability_id)
				return provision.capability_id
	return null

/datum/generated_station_materializer/proc/build_service_route(route_id, service_id, datum/generated_station_service_endpoint/start_endpoint, datum/generated_station_service_endpoint/end_endpoint)
	if(!start_endpoint || !end_endpoint)
		return
	var/datum/generated_station_service_route/route = new
	route.id = route_id
	route.service_id = service_id
	route.from_endpoint_id = start_endpoint.id
	route.to_endpoint_id = end_endpoint.id
	for(var/x in min(start_endpoint.x, end_endpoint.x) to max(start_endpoint.x, end_endpoint.x))
		route.path += list(list(x, start_endpoint.y))
	for(var/y in min(start_endpoint.y, end_endpoint.y) to max(start_endpoint.y, end_endpoint.y))
		if(y == start_endpoint.y)
			continue
		route.path += list(list(end_endpoint.x, y))
	for(var/list/point in route.path)
		var/turf/T = world_turf(point[1], point[2])
		if(!T || istype(T, /turf/space))
			continue
		var/obj/effect/landmark/generated_station_service_route/marker = new(T)
		marker.station_id = spec.id
		marker.service_id = service_id
		route.physical_markers += marker
	result.service_routes += route

/datum/generated_station_materializer/proc/build_services()
	build_service_endpoints()
	var/datum/generated_station_service_route/maintenance_route = new
	maintenance_route.id = "maintenance-physical"
	maintenance_route.service_id = GENERATED_STATION_SERVICE_MAINTENANCE
	for(var/key in spec.maintenance_tiles)
		var/list/parts = splittext(key, ",")
		maintenance_route.path += list(list(text2num(parts[1]), text2num(parts[2])))
		var/turf/T = world_turf(text2num(parts[1]), text2num(parts[2]))
		if(T)
			var/obj/effect/landmark/generated_station_service_route/marker = new(T)
			marker.station_id = spec.id
			marker.service_id = GENERATED_STATION_SERVICE_MAINTENANCE
			maintenance_route.physical_markers += marker
	result.service_routes += maintenance_route
	for(var/datum/generated_station_layout_edge/edge in spec.layout_edges)
		if(edge.kind == GENERATED_STATION_EDGE_UTILITY)
			var/service_id = service_for_utility_edge(edge)
			if(service_id)
				build_service_route("service-[edge.id]", service_id, endpoint_for(edge.from_node_id, service_id), endpoint_for(edge.to_node_id, service_id))

/datum/generated_station_materialization/proc/validate_services(datum/generated_station_spec/spec)
	var/datum/generated_station_validation_result/validation = new
	var/list/maintenance_floors = list()
	for(var/key in spec.maintenance_tiles)
		var/list/parts = splittext(key, ",")
		var/turf/T = world_turf(text2num(parts[1]), text2num(parts[2]))
		if(!istype(T, /turf/simulated/floor) || get_area(T) != maintenance_area)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "maintenance-turf-mismatch", "Planned maintenance is not physical maintenance flooring.", key)
			continue
		maintenance_floors[T] = TRUE
		if(spec.maintenance_doors[key] && !(locate(/obj/machinery/door/airlock/maintenance) in T))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "maintenance-door-missing", "Planned maintenance access has no maintenance airlock.", key)
	if(length(maintenance_floors))
		var/list/reached = list()
		var/list/frontier = list(maintenance_floors[1])
		while(length(frontier))
			var/turf/current = frontier[length(frontier)]
			frontier.len--
			if(reached[current])
				continue
			reached[current] = TRUE
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor = get_step(current, direction)
				if(maintenance_floors[neighbor] && !reached[neighbor])
					frontier += neighbor
		if(length(reached) != length(maintenance_floors))
			validation.add(GENERATED_STATION_ISSUE_ERROR, "maintenance-disconnected", "Physical maintenance contains [length(maintenance_floors) - length(reached)] unreachable floor tiles.", spec.id)
	else
		validation.add(GENERATED_STATION_ISSUE_ERROR, "maintenance-missing", "Station has no physical maintenance network.", spec.id)
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/has_maintenance_access = FALSE
		for(var/key in spec.maintenance_doors)
			var/list/parts = splittext(key, ",")
			var/turf/door_turf = world_turf(text2num(parts[1]), text2num(parts[2]))
			for(var/direction in GLOB.cardinal)
				if(get_area(get_step(door_turf, direction)) == department_areas[node.id])
					has_maintenance_access = TRUE
					break
			if(has_maintenance_access)
				break
		if(!has_maintenance_access)
			validation.add(GENERATED_STATION_ISSUE_ERROR, "department-without-maintenance", "Department has no physical access to the maintenance network.", node.id)
	for(var/datum/generated_station_department_instance/department in spec.departments)
		var/node_id = department.layout_node_id
		for(var/datum/generated_station_capability_requirement/requirement in department.definition.requirements)
			var/has_endpoint = FALSE
			var/has_route = FALSE
			// A department can satisfy an internal service locally; there is no
			// meaningful inter-department route to draw back to itself.
			for(var/datum/generated_station_capability_provision/local_provision in department.definition.provisions)
				if(local_provision.capability_id == requirement.capability_id)
					has_route = TRUE
					break
			for(var/datum/generated_station_service_endpoint/endpoint in service_endpoints)
				if(endpoint.department_node_id == node_id && endpoint.service_id == requirement.capability_id && endpoint.landmark)
					has_endpoint = TRUE
					break
			for(var/datum/generated_station_service_route/route in service_routes)
				if(route.service_id == requirement.capability_id && (route.from_endpoint_id == "endpoint-[node_id]-[requirement.capability_id]" || route.to_endpoint_id == "endpoint-[node_id]-[requirement.capability_id]") && length(route.physical_markers))
					has_route = TRUE
					break
			if(!has_endpoint)
				validation.add(requirement.optional ? GENERATED_STATION_ISSUE_WARNING : GENERATED_STATION_ISSUE_ERROR, "service-endpoint-missing", "Department has no physical [requirement.capability_id] endpoint.", department.id)
			if(!has_route)
				validation.add(requirement.optional ? GENERATED_STATION_ISSUE_WARNING : GENERATED_STATION_ISSUE_ERROR, "service-route-missing", "Department has no physical [requirement.capability_id] route.", department.id)
	return validation

#undef GENERATED_STATION_SERVICE_MAINTENANCE
