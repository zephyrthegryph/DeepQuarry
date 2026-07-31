/// Area types owned by a materialized station. Separate instances are created
/// for every department so APC and alarm state cannot bleed between rooms.
/area/generated_station
	name = "Remote station"
	icon_state = "unknown"
	var/station_id
	var/department_id

/area/generated_station/command
	name = "Remote Station Command"

/area/generated_station/ai
	name = "Remote Station AI Core"

/area/generated_station/security
	name = "Remote Station Security"

/area/generated_station/medical
	name = "Remote Station Medical"

/area/generated_station/engineering
	name = "Remote Station Engineering"

/area/generated_station/logistics
	name = "Remote Station Logistics"

/area/generated_station/docking
	name = "Remote Station Docking"

/area/generated_station/transit
	name = "Remote Station Transit"

/area/generated_station/maintenance
	name = "Remote Station Maintenance"

/// Stable slot that later docking integration may replace with a shuttle port.
/obj/effect/landmark/generated_station_entry
	name = "generated station entry slot"
	var/station_id

/obj/effect/landmark/generated_station_entry/Destroy()
	return ..(TRUE)

/obj/machinery/door/airlock/generated_station_exterior
	name = "exterior EVA airlock"
	desc = "The outer pressure door of a generated station EVA vestibule."

/obj/machinery/door/airlock/maintenance/generated_station
	name = "maintenance access"

/obj/structure/filingcabinet/generated_station_compact
	name = "shallow records cabinet"
	desc = "A wall-depth records cabinet designed not to obstruct a compact workspace."
	density = FALSE

/obj/item/card/id/generated_station_master
	name = "remote station authority card"
	desc = "An emergency authority credential for the isolated installation."

/obj/item/card/id/generated_station_master/Initialize(mapload)
	. = ..()
	access |= SSaccess.get_all_station_access()

/// Shared baseline area used when generated geometry releases turf ownership.
/proc/generated_station_space_area()
	var/area/space/space_area = GLOB.areas_by_type[/area/space]
	if(!space_area)
		space_area = new
	return space_area

/// Summary returned to callers and tests after a successful materialization.
/datum/generated_station_materialization
	var/station_id
	var/z_level
	var/origin_x
	var/origin_y
	var/floor_count = 0
	var/wall_count = 0
	var/corridor_count = 0
	var/door_count = 0
	var/styled_floor_count = 0
	var/accent_decal_count = 0
	var/obj/effect/landmark/generated_station_entry/entry
	var/area/generated_station/transit/transit_area
	var/area/generated_station/maintenance/maintenance_area
	var/list/department_areas
	var/list/module_areas
	var/list/modules
	var/list/room_solutions
	var/list/control_landmarks
	var/list/service_endpoints
	var/list/service_routes
	var/list/furnishings
	var/list/owned_furnishing_atoms
	var/list/doors
	var/list/infrastructure
	var/list/degradation_events
	var/datum/generated_station_tile_plan/tile_plan
	var/datum/generated_station_validation_result/service_validation

/datum/generated_station_materialization/New()
	..()
	department_areas = list()
	module_areas = list()
	modules = list()
	room_solutions = list()
	control_landmarks = list()
	service_endpoints = list()
	service_routes = list()
	furnishings = list()
	owned_furnishing_atoms = list()
	doors = list()
	infrastructure = list()
	degradation_events = list()

/datum/generated_station_materialization/proc/world_turf(local_x, local_y)
	return locate(origin_x + local_x - 1, origin_y + local_y - 1, z_level)

/// Registers a furnishing and every movable it created inside itself for teardown.
/datum/generated_station_materialization/proc/register_furnishing(atom/movable/furnishing)
	if(!furnishing || (furnishing in furnishings))
		return
	furnishings += furnishing
	register_owned_furnishing_atom(furnishing)

/datum/generated_station_materialization/proc/register_owned_furnishing_atom(atom/movable/furnishing)
	if(!furnishing || (furnishing in owned_furnishing_atoms))
		return
	owned_furnishing_atoms += furnishing
	for(var/atom/movable/contained in furnishing)
		register_owned_furnishing_atom(contained)

/datum/generated_station_materialization/Destroy()
	QDEL_NULL(entry)
	var/area/space/space_area = generated_station_space_area()
	if(department_areas)
		for(var/node_id in department_areas)
			var/area/generated_station/A = department_areas[node_id]
			var/list/owned_turfs = A.contents.Copy()
			for(var/turf/T in owned_turfs)
				ChangeArea(T, space_area)
			qdel(A)
		department_areas = null
	if(module_areas)
		for(var/module_id in module_areas)
			var/area/generated_station/A = module_areas[module_id]
			var/list/owned_turfs = A.contents.Copy()
			for(var/turf/T in owned_turfs)
				ChangeArea(T, space_area)
			qdel(A)
		module_areas = null
	if(transit_area)
		var/list/owned_transit_turfs = transit_area.contents.Copy()
		for(var/turf/T in owned_transit_turfs)
			ChangeArea(T, space_area)
	QDEL_NULL(transit_area)
	if(maintenance_area)
		var/list/owned_maintenance_turfs = maintenance_area.contents.Copy()
		for(var/turf/T in owned_maintenance_turfs)
			ChangeArea(T, space_area)
	QDEL_NULL(maintenance_area)
	QDEL_LIST(modules)
	QDEL_LIST(room_solutions)
	QDEL_LIST(control_landmarks)
	QDEL_LIST(service_endpoints)
	QDEL_LIST(service_routes)
	QDEL_LIST(owned_furnishing_atoms)
	furnishings = null
	QDEL_LIST(doors)
	QDEL_LIST(infrastructure)
	degradation_events = null
	QDEL_NULL(tile_plan)
	QDEL_NULL(service_validation)
	return ..()

/// Converts planner-local coordinates into station turfs. This pass deliberately
/// creates no machinery: utility and room-content passes can safely follow it.
/datum/generated_station_materializer
	var/datum/generated_station_spec/spec
	var/z_level
	var/min_x
	var/min_y
	var/max_x
	var/max_y
	var/list/nodes_by_id
	var/list/department_areas
	var/list/module_areas
	var/area/generated_station/transit/transit_area
	var/area/generated_station/maintenance/maintenance_area
	var/datum/generated_station_materialization/result
	var/datum/generated_station_validation_result/last_architecture_validation
	var/datum/generated_station_tile_plan/tile_plan
	var/datum/generated_station_materialization_job/active_job
	var/last_failure_details
	var/last_yield_count = 0
	var/last_elapsed_seconds = 0
	var/last_peak_tick_usage = 0
	var/last_peak_phase
	/// CI and focused diagnostics default to a fail-closed authored-room contract.
	/// Live expedition generation disables this: aesthetic shortfalls must degrade
	/// the affected room, never discard an otherwise playable station.
	var/strict_room_contracts = TRUE

/datum/generated_station_materializer/Destroy()
	spec = null
	nodes_by_id = null
	department_areas = null
	module_areas = null
	transit_area = null
	maintenance_area = null
	result = null
	QDEL_NULL(last_architecture_validation)
	QDEL_NULL(tile_plan)
	active_job = null
	return ..()

/datum/generated_station_materializer/proc/materialize(datum/generated_station_spec/new_spec, new_z, origin_x = 1, origin_y = 1, datum/flight_plan/flight_plan = null, fast_mode = FALSE)
	var/datum/generated_station_materialization_job/job = new(src, flight_plan, fast_mode)
	var/datum/generated_station_materialization/materialization = job.execute(new_spec, new_z, origin_x, origin_y)
	last_yield_count = job.yield_count
	last_elapsed_seconds = (job.finished_at - job.started_at) / 10
	last_peak_tick_usage = job.peak_tick_usage
	last_peak_phase = job.peak_phase
	log_world("Generated station materialization telemetry: [last_elapsed_seconds]s, [last_yield_count] yields, peak [last_peak_tick_usage]% during [last_peak_phase].")
	qdel(job)
	return materialization

/datum/generated_station_materializer/proc/generation_checkpoint(phase, progress, force_yield = FALSE)
	if(active_job)
		active_job.checkpoint(phase, progress, force_yield)
	else
		CHECK_TICK

/datum/generated_station_materializer/proc/materialize_incremental(datum/generated_station_spec/new_spec, new_z, origin_x = 1, origin_y = 1, datum/generated_station_materialization_job/job)
	last_failure_details = null
	if(!istype(new_spec) || !isnum(new_z) || new_z < 1 || new_z > world.maxz)
		return null
	if(origin_x < 1 || origin_y < 1 || origin_x + new_spec.grid_width - 1 > world.maxx || origin_y + new_spec.grid_height - 1 > world.maxy)
		return null

	spec = new_spec
	active_job = job
	z_level = new_z
	min_x = origin_x
	min_y = origin_y
	max_x = origin_x + spec.grid_width - 1
	max_y = origin_y + spec.grid_height - 1
	nodes_by_id = list()
	department_areas = list()
	module_areas = list()
	transit_area = new
	transit_area.station_id = spec.id
	transit_area.name = "[spec.name] Transit"
	maintenance_area = new
	maintenance_area.station_id = spec.id
	maintenance_area.name = "[spec.name] Maintenance"
	result = new
	result.station_id = spec.id
	result.z_level = z_level
	result.origin_x = min_x
	result.origin_y = min_y
	result.transit_area = transit_area
	result.maintenance_area = maintenance_area
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		nodes_by_id[node.id] = node
		var/datum/generated_station_department_instance/department = department_for_node(node)
		if(department)
			var/area/generated_station/department_area = make_department_area(department.definition.id)
			department_area.station_id = spec.id
			department_area.department_id = department.id
			department_area.name = "[spec.name] [department.definition.name]"
			department_areas[node.id] = department_area
			result.department_areas[node.id] = department_area
		generation_checkpoint("Allocating station areas", 25)

	var/materialization_stage
	generation_checkpoint("Compiling structural ownership", 27)
	if(!build_tile_plan())
		materialization_stage = "tile-plan"
	else if(!build_planned_modules())
		materialization_stage = "planned-modules"
	else if(!build_room_areas())
		materialization_stage = "room-areas"
	else
		generation_checkpoint("Planning station utilities", 31)
	if(!materialization_stage && !plan_generated_station_utilities())
		materialization_stage = "utilities"
	else if(!materialization_stage)
		generation_checkpoint("Changing structural turfs", 35, TRUE)
	if(!materialization_stage && !apply_tile_plan())
		materialization_stage = "tile-application"
	if(!materialization_stage && !style_rust_blueprint_floors())
		materialization_stage = "floor-styling"
	if(materialization_stage)
		last_failure_details = "[materialization_stage]: [jointext(result?.tile_plan?.errors, "; ")]"
		log_world("Generated station [spec.id] materialization failed during [materialization_stage].")
		for(var/plan_error in result?.tile_plan?.errors)
			log_world("Generated station [spec.id] materialization rejected: [plan_error]")
		qdel(result)
		result = null
		active_job = null
		return null
	generation_checkpoint("Installing doors and station services", 46, TRUE)
	place_exterior_airlocks()
	generation_checkpoint("Installing exterior airlocks", 47)
	place_planned_control_landmarks()
	generation_checkpoint("Installing control landmarks", 47)
	furnish_transit_alcoves()
	generation_checkpoint("Furnishing transit alcoves", 48)
	place_entry()
	generation_checkpoint("Installing station entry", 48)
	build_services()
	generation_checkpoint("Furnishing functional rooms", 50, TRUE)
	if(!synthesize_rust_blueprint())
		last_failure_details ||= "room synthesis"
		log_world("Generated station [spec.id] materialization failed during room synthesis.")
		qdel(result)
		result = null
		active_job = null
		return null
	generation_checkpoint("Installing emergency equipment", 55, TRUE)
	if(!place_emergency_equipment())
		if(strict_room_contracts)
			last_failure_details = "emergency equipment"
			log_world("Generated station [spec.id] materialization failed during emergency equipment placement.")
			qdel(result)
			result = null
			active_job = null
			return null
		result.degradation_events += "one or more rooms could not place emergency equipment"
		log_world("Generated station [spec.id] continued without complete emergency equipment placement.")
	generation_checkpoint("Validating furnishing access", 55, TRUE)
	if(!finalize_furnishing_access())
		if(strict_room_contracts)
			last_failure_details = "furnishing access"
			log_world("Generated station [spec.id] materialization failed during furnishing access validation.")
			qdel(result)
			result = null
			active_job = null
			return null
		// Live generation is explicitly best-effort. The repair pass has already
		// removed optional blockers, relocated required fixtures, and attempted an
		// interior access door; retain the playable result and let the independent
		// architecture audit report any concrete remaining defect.
		log_world("Generated station [spec.id] retained its best-effort furnishing layout after access repair was exhausted.")
	result.service_validation = result.validate_services(spec, src)
	generation_checkpoint("Finalizing walls and atmosphere", 57, TRUE)
	finalize_wall_adjacencies()
	for(var/key in result.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = result.tile_plan.tiles[key]
		if(intent.structure_kind == GENERATED_STATION_TILE_FLOOR)
			generated_station_seed_air(world_turf(intent.local_x, intent.local_y))
		generation_checkpoint("Seeding station atmosphere", 60)
	finalize()
	active_job = null
	return result

/// Applies the Rust room floor contract after structural turfs exist. Room
/// base tiles come from the selected authored definition; this pass adds the
/// continuous Southern Cross-style department paint around each room edge.
/datum/generated_station_materializer/proc/style_rust_blueprint_floors()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		for(var/datum/generated_station_room_allocation/room in node.room_program)
			var/accent_color = generated_station_accent_color(room.accent_style)
			if(!accent_color)
				continue
			for(var/key in room.tiles)
				var/list/parts = splittext(key, ",")
				var/local_x = text2num(parts[1])
				var/local_y = text2num(parts[2])
				var/turf/simulated/floor/floor = world_turf(local_x, local_y)
				if(!istype(floor))
					continue
				for(var/direction in GLOB.cardinal)
					var/neighbor_x = local_x + (direction == EAST) - (direction == WEST)
					var/neighbor_y = local_y + (direction == NORTH) - (direction == SOUTH)
					if(room.tiles["[neighbor_x],[neighbor_y]"])
						continue
					// `borderfloor` is a pre-shaded dark stripe and cannot be
					// recolored correctly. `bordercolor` is the tintable mask
					// Southern Cross uses for department paint.
					new /obj/effect/floor_decal/corner/white/border(floor, direction, accent_color)
					result.accent_decal_count++
				result.styled_floor_count++
	return TRUE

/proc/generated_station_accent_color(accent_style)
	switch(accent_style)
		if("command-blue") return COLOR_COMMAND_BLUE
		if("ai-cyan") return COLOR_CYAN_BLUE
		if("security-red") return COLOR_RED_GRAY
		if("medical-blue") return COLOR_BLUE_GRAY
		if("engineering-yellow") return COLOR_DARK_ORANGE
		if("science-purple") return COLOR_PURPLE_GRAY
		if("cargo-brown") return COLOR_YELLOW_GRAY
		if("docking-gray") return COLOR_DARK_GUNMETAL
		if("neutral-gray") return COLOR_GRAY
	return COLOR_WHITE

/datum/generated_station_materializer/proc/world_turf(local_x, local_y)
	return locate(min_x + local_x - 1, min_y + local_y - 1, z_level)

/// Compiles planner geometry into one ownership map before touching live turfs.
/datum/generated_station_materializer/proc/build_tile_plan()
	QDEL_NULL(tile_plan)
	tile_plan = new(spec.grid_width, spec.grid_height, src)
	var/floor_type = /turf/simulated/floor/tiled
	if(spec.architecture_style == "sterile")
		floor_type = /turf/simulated/floor/tiled/eris/white
	else if(spec.architecture_style == "fortified")
		floor_type = /turf/simulated/floor/tiled/eris/steel/techfloor
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_department_instance/node_department = department_for_node(node)
		var/department_id = node_department?.definition?.id
		for(var/key in node.territory)
			var/list/parts = splittext(key, ",")
			tile_plan.claim(text2num(parts[1]), text2num(parts[2]), node.id, node.id, GENERATED_STATION_TILE_FLOOR, floor_type, department_id)
			generation_checkpoint("Compiling department territory", 28)
		for(var/key in node.local_circulation)
			var/list/parts = splittext(key, ",")
			tile_plan.refine(text2num(parts[1]), text2num(parts[2]), node.id, GENERATED_STATION_TILE_FLOOR, floor_type)
			generation_checkpoint("Compiling department circulation", 28)
		for(var/key in node.partition_walls)
			var/list/parts = splittext(key, ",")
			tile_plan.refine(text2num(parts[1]), text2num(parts[2]), node.id, GENERATED_STATION_TILE_HULL, null)
			generation_checkpoint("Compiling department partitions", 28)
		for(var/datum/generated_station_room_allocation/room in node.room_program)
			var/datum/generated_room_definition/definition
			if(room.definition_id == "[department_id]-compact-[room.role]")
				definition = generated_compact_room_definition_for(department_id, room.role)
			else if(room.definition_id == "[department_id]-micro-[room.role]")
				definition = generated_micro_room_definition_for(department_id, room.role)
			else
				definition = generated_room_definition_for(department_id, room.role)
			var/room_floor_type = definition?.room_style?.floor_type || floor_type
			for(var/key in room.tiles)
				var/list/parts = splittext(key, ",")
				var/datum/generated_station_tile_intent/intent = tile_plan.tile(text2num(parts[1]), text2num(parts[2]))
				if(intent?.owner_id == node.id)
					intent.zone_id = room.id
					intent.floor_type = room_floor_type
				generation_checkpoint("Compiling room ownership", 28)
			for(var/datum/generated_station_door_socket/socket in room.door_sockets)
				tile_plan.claim_door(socket.x, socket.y, node.id, /obj/machinery/door/airlock, socket.direction, department_id)
			qdel(definition)
		for(var/datum/generated_station_eva_vestibule/vestibule in node.eva_vestibules)
			for(var/key in vestibule.tiles)
				var/list/parts = splittext(key, ",")
				var/datum/generated_station_tile_intent/intent = tile_plan.tile(text2num(parts[1]), text2num(parts[2]))
				if(intent?.owner_id == node.id)
					intent.zone_id = vestibule.id
			for(var/datum/generated_station_door_socket/socket in vestibule.door_sockets)
				var/door_type = socket.kind == "eva-exterior" ? /obj/machinery/door/airlock/generated_station_exterior : /obj/machinery/door/airlock
				tile_plan.claim_door(socket.x, socket.y, node.id, door_type, socket.direction, department_id)
		for(var/datum/generated_station_door_socket/socket in node.frontage_sockets)
			tile_plan.claim_door(socket.x, socket.y, node.id, /obj/machinery/door/airlock, socket.direction, department_id)
		generation_checkpoint("Compiling department ownership", 28)
	for(var/key in spec.circulation_tiles)
		var/list/parts = splittext(key, ",")
		claim_transit_tile(text2num(parts[1]), text2num(parts[2]), floor_type)
		generation_checkpoint("Compiling public circulation", 28)
	for(var/key in spec.maintenance_tiles)
		var/list/parts = splittext(key, ",")
		var/x = text2num(parts[1])
		var/y = text2num(parts[2])
		if(tile_plan.claim(x, y, "maintenance", "maintenance", GENERATED_STATION_TILE_FLOOR, /turf/simulated/floor/tiled/eris/steel/techfloor, null) && spec.maintenance_doors[key])
			var/datum/generated_station_maintenance_door/maintenance_door = spec.maintenance_doors[key]
			var/datum/generated_station_layout_node/door_node = nodes_by_id[maintenance_door.owner_node_id]
			var/access_id
			if(maintenance_door.to_zone_id != "maintenance" && maintenance_door.to_zone_id != "public-circulation")
				access_id = department_for_node(door_node)?.definition?.id
			tile_plan.claim_door(x, y, "maintenance", /obj/machinery/door/airlock/maintenance/generated_station, maintenance_door.direction, access_id)
		generation_checkpoint("Compiling maintenance circulation", 29)
	for(var/key in spec.structural_tiles)
		var/list/parts = splittext(key, ",")
		tile_plan.claim(text2num(parts[1]), text2num(parts[2]), "station-structure", "structure", GENERATED_STATION_TILE_HULL, null, null)
		generation_checkpoint("Compiling structural walls", 29)
	tile_plan.derive_hull()
	if(!tile_plan.validate_exterior_seal())
		for(var/error in tile_plan.errors)
			log_world("Generated station [spec.id] tile plan rejected: [error]")
		return FALSE
	result.tile_plan = tile_plan
	tile_plan = null
	return TRUE

/// Resolves cross-room access constraints after every authored fragment and
/// generated furnishing exists, while the station can still be rejected safely.
/datum/generated_station_materializer/proc/finalize_furnishing_access()
	for(var/atom/movable/furnishing in result.furnishings)
		var/turf/current = get_turf(furnishing)
		if(!current)
			continue
		if(furnishing.density && !istype(furnishing, /obj/machinery/door))
			var/blocks_door = FALSE
			for(var/direction in GLOB.cardinal)
				if(locate(/obj/machinery/door) in get_step(current, direction))
					blocks_door = TRUE
					break
			if(blocks_door)
				var/turf/destination
				for(var/radius in 1 to 8)
					for(var/turf/simulated/floor/candidate in orange(radius, current))
						if(get_area(candidate) != get_area(current) || !generated_station_furnishing_access_tile(candidate))
							continue
						destination = candidate
						break
					if(destination)
						break
				if(!destination)
					if(generated_station_is_removable_decor(furnishing))
						result.furnishings -= furnishing
						result.owned_furnishing_atoms -= furnishing
						qdel(furnishing)
						continue
					// Some functional wall-side machinery is legitimately adjacent
					// to one of a room's multiple doors. Keep it in place here; the
					// authoritative room connectivity/door-reachability audit below
					// still rejects it if it actually blocks access.
					continue
				furnishing.forceMove(destination)
				current = destination
		if(istype(furnishing, /obj/structure/bed/chair))
			var/turf/front = get_step(current, furnishing.dir)
			if(generated_station_architectural_passable(front))
				continue
			for(var/direction in GLOB.cardinal)
				front = get_step(current, direction)
				if(generated_station_architectural_passable(front))
					furnishing.set_dir(direction)
					break
		generation_checkpoint("Validating furnishing access", 55)
	// A later room or emergency fixture can change the final boundary graph
	// after an individual room was solved. Remove only non-functional decor,
	// newest first, until every room again has one component connected to a door.
	for(var/module_id in module_areas)
		var/area/generated_station/A = module_areas[module_id]
		while(!generated_station_room_area_is_accessible(A))
			var/atom/movable/removable
			for(var/i in length(result.furnishings) to 1 step -1)
				var/atom/movable/candidate = result.furnishings[i]
				if(get_area(candidate) == A && generated_station_is_removable_decor(candidate))
					removable = candidate
					break
			if(!removable)
				if(relocate_blocking_room_furnishing(A))
					continue
				// Playability outranks a required decoration contract. If a dense
				// authored fixture still partitions the room after relocation, drop
				// that fixture and publish a degraded but fully traversable room.
				var/atom/movable/required_blocker
				for(var/i in length(result.furnishings) to 1 step -1)
					var/atom/movable/candidate = result.furnishings[i]
					if(get_area(candidate) == A && candidate.density && !istype(candidate, /obj/machinery/door))
						required_blocker = candidate
						break
				if(required_blocker)
					result.degradation_events += "removed [required_blocker.type] from [A.name] to preserve room access"
					result.furnishings -= required_blocker
					result.owned_furnishing_atoms -= required_blocker
					qdel(required_blocker)
					continue
				if(install_emergency_room_access(A))
					continue
				var/list/blockers = list()
				for(var/turf/simulated/floor/blocked_floor in A)
					for(var/atom/movable/blocker in blocked_floor)
						if(blocker.density && !istype(blocker, /obj/machinery/door))
							blockers += "[blocker.type]@[blocked_floor.x],[blocked_floor.y]"
				log_world("Generated station could not repair furnishing access for [A.name]: [jointext(blockers, ", ")]")
				return FALSE
			result.furnishings -= removable
			result.owned_furnishing_atoms -= removable
			qdel(removable)
			generation_checkpoint("Opening final room circulation", 55)
	return TRUE

/// Moves a required dense furnishing to another valid socket when the complete
/// room graph proves its authored position is an articulation point.
/datum/generated_station_materializer/proc/relocate_blocking_room_furnishing(area/generated_station/A)
	for(var/atom/movable/furnishing in result.furnishings)
		if(get_area(furnishing) != A || !furnishing.density || istype(furnishing, /obj/machinery/door))
			continue
		var/turf/original = get_turf(furnishing)
		for(var/turf/simulated/floor/candidate in A)
			if(candidate == original || !generated_station_furnishing_access_tile(candidate))
				continue
			furnishing.forceMove(candidate)
			if(generated_station_room_area_is_accessible(A))
				return TRUE
			furnishing.forceMove(original)
	return FALSE

/// Repairs the rare case where utilities/required machinery consume every
/// approach to a planned room door. This is an interior-only structural repair:
/// it opens a wall between the room and an already-walkable station tile, never
/// the exterior hull, then installs a tracked department airlock.
/datum/generated_station_materializer/proc/install_emergency_room_access(area/generated_station/A)
	for(var/turf/simulated/floor/inside in A)
		for(var/direction in GLOB.cardinal)
			var/turf/simulated/wall/wall = get_step(inside, direction)
			if(!istype(wall))
				continue
			var/turf/outside = get_step(wall, direction)
			if(!generated_station_architectural_passable(outside) || get_area(outside) == A)
				continue
			var/local_x = wall.x - min_x + 1
			var/local_y = wall.y - min_y + 1
			var/datum/generated_station_tile_intent/intent = result.tile_plan?.tile(local_x, local_y)
			if(intent)
				intent.structure_kind = GENERATED_STATION_TILE_FLOOR
				intent.floor_type = /turf/simulated/floor/tiled
				intent.door_type = /obj/machinery/door/airlock
				intent.door_direction = direction
			var/turf/simulated/floor/door_turf = wall.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
			ChangeArea(door_turf, A)
			var/obj/machinery/door/airlock/airlock = new(door_turf)
			airlock.set_dir(direction)
			result.doors += airlock
			result.door_count++
			return TRUE
	return FALSE

/proc/generated_station_is_removable_decor(atom/movable/furnishing)
	return istype(furnishing, /obj/structure/table) || istype(furnishing, /obj/structure/bed/chair) || istype(furnishing, /obj/structure/filingcabinet) || istype(furnishing, /obj/structure/flora/pottedplant)

/// Returns whether a generated furnishing can move here without consuming an
/// airlock approach, utility fixture, or another blocking object's footprint.
/datum/generated_station_materializer/proc/generated_station_furnishing_access_tile(turf/simulated/floor/candidate)
	if(!candidate || candidate.density || locate(/obj/machinery/door) in candidate)
		return FALSE
	for(var/atom/movable/occupant in candidate)
		if(occupant.density || istype(occupant, /obj/machinery))
			return FALSE
	for(var/direction in GLOB.cardinal)
		if(locate(/obj/machinery/door) in get_step(candidate, direction))
			return FALSE
	var/datum/generated_station_tile_intent/intent = result.tile_plan?.tile(candidate.x - min_x + 1, candidate.y - min_y + 1)
	return !intent?.has_utility_fixture()

/// Adapts planner-owned room programs to the existing furnishing solver without carving live turfs.
/datum/generated_station_materializer/proc/build_planned_modules()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		for(var/datum/generated_station_room_allocation/room in node.room_program)
			if(!length(room.tiles))
				return FALSE
			var/datum/generated_station_module/module = new
			module.id = room.id
			module.department_node_id = node.id
			module.role = room.role
			module.definition_id = room.definition_id
			module.x1 = spec.grid_width
			module.y1 = spec.grid_height
			module.x2 = 1
			module.y2 = 1
			for(var/key in room.tiles)
				var/list/parts = splittext(key, ",")
				var/x = text2num(parts[1])
				var/y = text2num(parts[2])
				module.add_footprint_tile(x, y)
				module.x1 = min(module.x1, x)
				module.y1 = min(module.y1, y)
				module.x2 = max(module.x2, x)
				module.y2 = max(module.y2, y)
			module.core_x1 = module.x1
			module.core_y1 = module.y1
			module.core_x2 = module.x2
			module.core_y2 = module.y2
			module.footprint_x1 = module.x1
			module.footprint_y1 = module.y1
			module.footprint_x2 = module.x2
			module.footprint_y2 = module.y2
			result.modules += module
	return TRUE

/// Gives every planned room an independent area and therefore its own APC,
/// alarms, environmental controls, and machine-power accounting.
/datum/generated_station_materializer/proc/build_room_areas()
	var/list/designation_counts = list()
	for(var/datum/generated_station_module/module in result.modules)
		var/department_id = department_id_for_module(module)
		var/area/generated_station/A = make_department_area(department_id)
		if(!A)
			return FALSE
		A.station_id = spec.id
		A.department_id = department_id
		var/designation_key = "[department_id]/[module.role]"
		designation_counts[designation_key] = (designation_counts[designation_key] || 0) + 1
		var/designation_number = designation_counts[designation_key]
		var/department_name = capitalize(department_id)
		var/role_name = capitalize(replacetext(module.role, "-", " "))
		var/datum/generated_station_room_allocation/allocation = room_allocation_for_module(module)
		var/base_name = allocation?.area_name || "[spec.name] [department_name] [role_name]"
		A.name = designation_number > 1 ? "[base_name] [designation_number]" : base_name
		module_areas[module.id] = A
		result.module_areas[module.id] = A
	return TRUE

/datum/generated_station_materializer/proc/room_allocation_for_module(datum/generated_station_module/module)
	var/datum/generated_station_layout_node/node = nodes_by_id[module?.department_node_id]
	for(var/datum/generated_station_room_allocation/room in node?.room_program)
		if(room.id == module.id)
			return room
	return null

/// Materializes the exact content plane returned by Rust. Existing DM utility
/// construction remains authoritative for APC/power/atmos network plumbing;
/// its endpoints correspond to the service fixtures in this blueprint.
/datum/generated_station_materializer/proc/synthesize_rust_blueprint()
	if(!length(spec.fixture_blueprint))
		last_failure_details = "Rust content blueprint is empty"
		return FALSE
	var/list/rooms_by_native_id = list()
	var/list/solutions_by_native_id = list()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		for(var/datum/generated_station_room_allocation/room in node.room_program)
			rooms_by_native_id["[room.rust_room_id]"] = room
			var/datum/generated_room_solution/solution = new
			solution.module_id = room.id
			solution.definition_id = room.selected_variant
			solution.aesthetic_id = room.aesthetic_id
			solution.valid = TRUE
			solution.score = room.occupancy_micros
			solution.floor_tiles = length(room.tiles)
			solution.occupied_tiles = CEILING(solution.floor_tiles * room.occupancy_micros / 1000000, 1)
			for(var/key in room.content_circulation)
				var/list/parts = splittext(key, ",")
				solution.reserve_circulation(text2num(parts[1]), text2num(parts[2]))
			solutions_by_native_id["[room.rust_room_id]"] = solution
			result.room_solutions += solution
	for(var/datum/generated_station_fixture_placement/fixture in spec.fixture_blueprint)
		generation_checkpoint("Materializing Rust room blueprint", 52)
		if(fixture.fixture_id in list("vent", "scrubber", "apc", "air_alarm", "fire_alarm", "wall_light"))
			continue
		var/atom_type = spec.fixture_type_registry[fixture.fixture_id] || generated_station_rust_fixture_type(fixture.fixture_id)
		if(!atom_type)
			last_failure_details = "unknown Rust fixture '[fixture.fixture_id]'"
			return FALSE
		var/turf/target = world_turf(fixture.x, fixture.y)
		var/datum/generated_station_room_allocation/room = rooms_by_native_id["[fixture.room_numeric_id]"]
		if(!target || (room && !room.tiles["[fixture.x],[fixture.y]"]))
			last_failure_details = "Rust fixture [fixture.id] lies outside room [fixture.room_numeric_id]"
			return FALSE
		var/atom/movable/created = new atom_type(target)
		created.set_dir(fixture.direction)
		if(fixture.layer == "Wall")
			var/wall_offset = 24
			switch(fixture.direction)
				if(NORTH)
					created.pixel_y = wall_offset
				if(SOUTH)
					created.pixel_y = -wall_offset
				if(EAST)
					created.pixel_x = wall_offset
				if(WEST)
					created.pixel_x = -wall_offset
		result.register_furnishing(created)
		var/datum/generated_room_solution/solution = solutions_by_native_id["[fixture.room_numeric_id]"]
		if(solution)
			var/datum/generated_room_placement/placement = new
			placement.feature = new /datum/generated_room_feature
			placement.feature.id = fixture.fixture_id
			placement.feature.atom_type = atom_type
			placement.x = fixture.x
			placement.y = fixture.y
			placement.dir = fixture.direction
			solution.placements += placement
	return TRUE

/// Stable Rust fixture vocabulary. Every identifier has an intentional live
/// game counterpart; unknown identifiers are contract errors, never generic
/// crates silently standing in for missing content.
/proc/generated_station_rust_fixture_type(fixture_id)
	switch(fixture_id)
		if("operating_table") return /obj/machinery/optable
		if("anesthetic", "medical_bed") return /obj/structure/bed
		if("privacy_screen") return /obj/structure/curtain/open/privacy
		if("medical_console") return /obj/machinery/computer/operating
		if("instrument_table", "experiment_table", "workbench", "conference_table", "food_prep", "serving_counter", "loading_table", "reception_desk", "worktable", "table", "side_table", "packing_table") return /obj/structure/table/standard
		if("medical_cabinet", "reagent_storage", "evidence_cabinet", "parts_bin", "parts_cabinet", "medicine_cart") return /obj/structure/filingcabinet
		if("medical_locker") return /obj/structure/closet/secure_closet/medical1
		if("stool") return /obj/structure/bed/chair
		if("analyzer", "plant_analyzer", "package_scanner", "role_console", "visitor_console", "control_console", "data_terminal") return /obj/machinery/computer/crew
		if("research_console") return /obj/machinery/computer/rdconsole_tg
		if("id_console") return /obj/machinery/computer/card
		if("robotics_console") return /obj/machinery/computer/robotics
		if("crew_monitor") return /obj/machinery/computer/crew
		if("ai_upload") return /obj/machinery/computer/aiupload
		if("power_monitor") return /obj/machinery/computer/power_monitor
		if("atmos_control") return /obj/machinery/computer/atmoscontrol
		if("equipment_recharger") return /obj/machinery/recharger
		if("charger_table") return /obj/structure/table/standard
		if("engineering_vendor") return /obj/machinery/vending/engineering
		if("air_canister") return /obj/machinery/portable_atmospherics/canister/air
		if("oxygen_canister") return /obj/machinery/portable_atmospherics/canister/oxygen
		if("autolathe") return /obj/machinery/autolathe
		if("armory_autolathe") return /obj/machinery/autolathe/armory
		if("electrical_locker") return /obj/structure/closet/secure_closet/engineering_electrical
		if("security_records") return /obj/machinery/computer/secure_data
		if("reinforced_table") return /obj/structure/table/reinforced
		if("chem_master") return /obj/machinery/chem_master
		if("reagent_grinder") return /obj/machinery/reagentgrinder
		if("sleeper") return /obj/machinery/sleeper
		if("iv_drip") return /obj/machinery/iv_drip
		if("medical_vendor") return /obj/machinery/vending/medical
		if("air_sensor") return /obj/machinery/air_sensor
		if("supply_console") return /obj/machinery/computer/supplycomp
		if("communications_console") return /obj/machinery/computer/communications
		if("disposal_unit") return /obj/machinery/disposal
		if("security_console", "flash") return /obj/machinery/computer/security
		if("weapon_rack", "secure_locker", "department_locker", "locker", "tool_rack", "supply_locker") return /obj/structure/closet/secure_closet/security
		if("chair", "waiting_bench", "work_chair", "operator_chair") return /obj/structure/bed/chair/office
		if("visitor_bench") return /obj/structure/bed/chair/comfy
		if("executive_chair") return /obj/structure/bed/chair/comfy/black
		if("engineering_console", "generator_control") return /obj/machinery/computer/power_monitor
		if("command_console", "holotable") return /obj/machinery/computer/communications
		if("filing_cabinet") return /obj/structure/filingcabinet/generated_station_compact
		if("manifest_board") return /obj/structure/noticeboard
		if("notice_board") return /obj/structure/noticeboard
		if("grill") return /obj/machinery/appliance/cooker/grill
		if("sink", "wash_station") return /obj/structure/sink
		if("fridge", "produce_bin") return /obj/machinery/smartfridge
		if("water_cooler") return /obj/structure/reagent_dispensers/water_cooler/full
		if("hydroponics_tray") return /obj/machinery/portable_atmospherics/hydroponics
		if("seed_extractor") return /obj/machinery/seed_extractor
		if("iv_stand") return /obj/machinery/iv_drip
		if("water_tank") return /obj/structure/closet/crate/internals
		if("internals_crate") return /obj/structure/closet/crate/internals
		if("freight_cart", "tool_cart") return /obj/structure/closet/crate/trashcart
		if("crate_rack") return /obj/structure/closet/crate/secure
		if("supply_crate") return /obj/structure/closet/crate
		if("pallet") return /obj/structure/closet/crate/plastic
		if("cargo_bin") return /obj/structure/closet/crate/bin
		if("cargo_console") return /obj/machinery/computer/supplycomp
		if("ai_core") return /obj/machinery/computer/aiupload
		if("server_rack", "server", "coolant_unit") return /obj/machinery/recharger
		if("plant") return /obj/structure/flora/pottedplant
		if("display_case") return /obj/structure/displaycase
		if("shelf") return /obj/structure/table/rack/shelf/steel
	return null

/// Instantiates semantic control points only after the authoritative structure exists.
/datum/generated_station_materializer/proc/place_planned_control_landmarks()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_module/control_module
		for(var/datum/generated_station_module/module in result.modules)
			if(module.department_node_id == node.id)
				control_module = module
		if(!control_module)
			continue
		var/turf/control_turf
		for(var/key in control_module.footprint)
			var/list/parts = splittext(key, ",")
			control_turf = world_turf(text2num(parts[1]), text2num(parts[2]))
			if(control_turf)
				break
		if(control_turf)
			var/obj/effect/landmark/generated_station_department_core/core = new(control_turf)
			core.station_id = spec.id
			core.department_node_id = node.id
			core.module_role = control_module.role
			result.control_landmarks += core

/// Transit cannot overwrite a department reservation; department frontages are opened later as doors.
/datum/generated_station_materializer/proc/claim_transit_tile(local_x, local_y, floor_type)
	var/datum/generated_station_tile_intent/current = tile_plan.tile(local_x, local_y)
	if(!current || current.structure_kind != GENERATED_STATION_TILE_EXTERIOR)
		return
	tile_plan.claim(local_x, local_y, "transit", "transit", GENERATED_STATION_TILE_FLOOR, floor_type, null)

/// Applies the completed plan exactly once. Later passes may place atoms but do not establish ownership.
/datum/generated_station_materializer/proc/apply_tile_plan()
	if(!result.tile_plan)
		return FALSE
	var/area/space/space_area = generated_station_space_area()
	var/wall_type = spec.architecture_style == "fortified" ? /turf/simulated/wall/r_wall : /turf/simulated/wall
	for(var/key in result.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = result.tile_plan.tiles[key]
		var/turf/T = world_turf(intent.local_x, intent.local_y)
		if(!T)
			return FALSE
		for(var/atom/movable/occupant in T)
			if(!ismob(occupant))
				qdel(occupant)
		switch(intent.structure_kind)
			if(GENERATED_STATION_TILE_FLOOR)
				T = T.ChangeTurf(intent.floor_type, tell_universe = FALSE)
				if(intent.owner_id == "transit")
					ChangeArea(T, transit_area)
					result.corridor_count++
				else if(intent.owner_id == "maintenance")
					ChangeArea(T, maintenance_area)
					result.corridor_count++
				else
					ChangeArea(T, module_areas[intent.zone_id] || department_areas[intent.owner_id])
					result.floor_count++
			if(GENERATED_STATION_TILE_HULL)
				T = T.ChangeTurf(wall_type, tell_universe = FALSE)
				ChangeArea(T, transit_area)
				result.wall_count++
			else
				T = T.ChangeTurf(/turf/space, tell_universe = FALSE)
				ChangeArea(T, space_area)
		generation_checkpoint("Changing structural turfs", 42)
	for(var/key in result.tile_plan.tiles)
		var/datum/generated_station_tile_intent/intent = result.tile_plan.tiles[key]
		if(!intent.door_type)
			continue
		var/turf/T = world_turf(intent.local_x, intent.local_y)
		var/obj/machinery/door/airlock/airlock = new intent.door_type(T)
		airlock.set_dir(intent.door_direction || NORTH)
		if(intent.owner_id != "transit" && intent.owner_id != "maintenance")
			configure_department_airlock(airlock, department_for_node(nodes_by_id[intent.owner_id]))
		else if(intent.access_id)
			configure_airlock_access(airlock, intent.access_id)
		result.doors += airlock
		result.door_count++
		generation_checkpoint("Installing planned doors", 45)
	return TRUE

/// Installs baseline fire detection and emergency supplies independently of room decoration.
/datum/generated_station_materializer/proc/place_emergency_equipment()
	for(var/module_id in module_areas)
		var/area/generated_station/A = module_areas[module_id]
		var/turf/alarm_turf
		for(var/datum/generated_station_tile_intent/intent in result.tile_plan.utility_floors(null, module_id))
			if(intent.zone_id == module_id && (GENERATED_STATION_UTILITY_FIRE_ALARM in intent.utility_intents))
				alarm_turf = world_turf(intent.local_x, intent.local_y)
				break
		if(!alarm_turf)
			return FALSE
		generation_checkpoint("Installing fire detection", 55, TRUE)
		var/obj/machinery/firealarm/alarm = new(alarm_turf)
		var/datum/generated_station_tile_intent/alarm_intent = result.tile_plan.tile(alarm_turf.x - min_x + 1, alarm_turf.y - min_y + 1)
		var/wall_direction = alarm_intent?.utility_wall_directions[GENERATED_STATION_UTILITY_FIRE_ALARM]
		alarm.set_dir(turn(wall_direction, 180))
		alarm.offset_alarm()
		result.register_furnishing(alarm)
		var/turf/closet_turf = find_emergency_fixture_turf(A, list(alarm_turf))
		if(closet_turf)
			generation_checkpoint("Installing emergency closet", 55, TRUE)
			var/obj/structure/closet/firecloset/full/generated_station/fire_closet = new(closet_turf)
			var/static/list/emergency_supply_types = list(
				/obj/item/clothing/suit/fire,
				/obj/item/clothing/mask/gas/clear,
				/obj/item/flashlight,
				/obj/item/tank/oxygen/red,
				/obj/item/extinguisher,
				/obj/item/clothing/head/hardhat/red,
				/obj/item/storage/toolbox/emergency,
			)
			// Closet contents are created by the budgeted late-initialization pass.
			// Instantiating this equipment inline can monopolize several game ticks.
			fire_closet.starts_with = emergency_supply_types.Copy()
			result.register_furnishing(fire_closet)
		generation_checkpoint("Installing emergency equipment", 55)
	return TRUE

/datum/generated_station_materializer/proc/find_emergency_fixture_turf(area/generated_station/A, list/excluded)
	for(var/turf/simulated/floor/T in A)
		generation_checkpoint("Selecting emergency closet position", 55)
		if((excluded && (T in excluded)) || T.density || locate(/obj/machinery/door) in T)
			continue
		var/datum/generated_station_tile_intent/intent = result.tile_plan?.tile(T.x - min_x + 1, T.y - min_y + 1)
		if(intent?.has_utility_fixture())
			continue
		var/blocked = FALSE
		for(var/atom/movable/occupant in T)
			if(occupant.density || istype(occupant, /obj/machinery))
				blocked = TRUE
				break
		if(blocked || !generated_station_adjacent_wall_direction(T))
			continue
		for(var/direction in GLOB.cardinal)
			if(locate(/obj/machinery/door) in get_step(T, direction))
				blocked = TRUE
				break
		if(!blocked && generated_station_area_removal_preserves_connectivity(T, A))
			return T
	return null

/// Emergency cabinets are placed after authored room solving. Prove that
/// occupying their selected floor cannot cut the room into sealed pockets.
/proc/generated_station_area_removal_preserves_connectivity(turf/blocked_turf, area/generated_station/A)
	var/list/available = list()
	for(var/turf/simulated/floor/T in A)
		if(T != blocked_turf && generated_station_architectural_passable(T))
			available |= T
	if(length(available) <= 1)
		return TRUE
	var/list/frontier = list(available[1])
	var/list/visited = list()
	while(length(frontier))
		var/turf/current = frontier[1]
		frontier.Cut(1, 2)
		if(visited[current])
			continue
		visited[current] = TRUE
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(current, direction)
			if(neighbor != blocked_turf && (neighbor in available) && !visited[neighbor])
				frontier += neighbor
	return length(visited) == length(available)

/proc/generated_station_area_is_connected(area/generated_station/A)
	var/list/available = list()
	for(var/turf/simulated/floor/T in A)
		if(generated_station_architectural_passable(T))
			available |= T
	if(length(available) <= 1)
		return TRUE
	var/list/frontier = list(available[1])
	var/list/visited = list()
	while(length(frontier))
		var/turf/current = frontier[1]
		frontier.Cut(1, 2)
		if(visited[current])
			continue
		visited[current] = TRUE
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(current, direction)
			if((neighbor in available) && !visited[neighbor])
				frontier += neighbor
	return length(visited) == length(available)

/// A room can be internally connected yet sealed away from its doorway. This
/// checks both the internal component and a clear connection to a physical
/// planned door on its boundary.
/proc/generated_station_room_area_is_accessible(area/generated_station/A)
	if(!generated_station_area_is_connected(A))
		return FALSE
	for(var/turf/simulated/floor/T in A)
		if(!generated_station_architectural_passable(T))
			continue
		if(locate(/obj/machinery/door) in T)
			return TRUE
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(T, direction)
			if(generated_station_architectural_passable(neighbor) && locate(/obj/machinery/door) in neighbor)
				return TRUE
	return FALSE

/proc/generated_station_adjacent_wall_direction(turf/T)
	for(var/direction in GLOB.cardinal)
		if(istype(get_step(T, direction), /turf/simulated/wall))
			return direction
	return null

/datum/generated_station_materializer/proc/department_for_node(datum/generated_station_layout_node/node) as /datum/generated_station_department_instance
	for(var/datum/generated_station_department_instance/department in spec.departments)
		if(department.id == node.department_instance_id)
			return department
	return null

/datum/generated_station_materializer/proc/make_department_area(department_id)
	switch(department_id)
		if("command")
			return new /area/generated_station/command
		if("ai")
			return new /area/generated_station/ai
		if("security")
			return new /area/generated_station/security
		if("medical")
			return new /area/generated_station/medical
		if("engineering")
			return new /area/generated_station/engineering
		if("logistics")
			return new /area/generated_station/logistics
		if("docking")
			return new /area/generated_station/docking
	return new /area/generated_station

/datum/generated_station_materializer/proc/fill_exterior()
	var/area/space/space_area = generated_station_space_area()
	for(var/x in 1 to spec.grid_width)
		for(var/y in 1 to spec.grid_height)
			var/turf/T = world_turf(x, y)
			if(T)
				for(var/atom/movable/occupant in T)
					if(!ismob(occupant))
						qdel(occupant)
				T.ChangeTurf(/turf/space, tell_universe = FALSE)
				ChangeArea(T, space_area)
		CHECK_TICK

/datum/generated_station_materializer/proc/carve_departments()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/area/generated_station/department_area = department_areas[node.id]
		for(var/x in node.x to node.x + node.width - 1)
			for(var/y in node.y to node.y + node.height - 1)
				var/turf/T = world_turf(x, y)
				if(!T)
					continue
				var/on_edge = x == node.x || y == node.y || x == node.x + node.width - 1 || y == node.y + node.height - 1
				var/floor_type = /turf/simulated/floor/tiled
				if(spec.architecture_style == "sterile")
					floor_type = /turf/simulated/floor/tiled/eris/white
				else if(spec.architecture_style == "fortified")
					floor_type = /turf/simulated/floor/tiled/eris/steel/techfloor
				var/wall_type = spec.architecture_style == "fortified" ? /turf/simulated/wall/r_wall : /turf/simulated/wall
				T.ChangeTurf(on_edge ? wall_type : floor_type, tell_universe = FALSE)
				ChangeArea(T, department_area)
				if(on_edge)
					result.wall_count++
				else
					result.floor_count++
		CHECK_TICK

/datum/generated_station_materializer/proc/node_at(local_x, local_y)
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		if(local_x >= node.x && local_x < node.x + node.width && local_y >= node.y && local_y < node.y + node.height)
			return node
	return null

/datum/generated_station_materializer/proc/carve_corridor_tile(local_x, local_y)
	if(local_x < 1 || local_y < 1 || local_x > spec.grid_width || local_y > spec.grid_height)
		return
	var/datum/generated_station_layout_node/node = node_at(local_x, local_y)
	if(node)
		return
	var/turf/T = world_turf(local_x, local_y)
	if(!T)
		return
	if(istype(T, /turf/space))
		T.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
		ChangeArea(T, transit_area)
		result.corridor_count++

/datum/generated_station_materializer/proc/carve_corridors()
	for(var/datum/generated_station_layout_edge/edge in spec.layout_edges)
		if(edge.kind != GENERATED_STATION_EDGE_TRANSIT)
			continue
		var/corridor_width = edge.corridor_class == "primary" ? 3 : 2
		for(var/i in 1 to length(edge.path))
			var/list/point = edge.path[i]
			carve_corridor_tile(point[1], point[2])
			var/dx = 0
			var/dy = 0
			if(i < length(edge.path))
				var/list/next = edge.path[i + 1]
				dx = next[1] - point[1]
				dy = next[2] - point[2]
			else if(i > 1)
				var/list/previous = edge.path[i - 1]
				dx = point[1] - previous[1]
				dy = point[2] - previous[2]
			if(dx)
				carve_corridor_tile(point[1], point[2] + 1)
				if(corridor_width >= 3)
					carve_corridor_tile(point[1], point[2] - 1)
			else if(dy)
				carve_corridor_tile(point[1] + 1, point[2])
				if(corridor_width >= 3)
					carve_corridor_tile(point[1] - 1, point[2])
		CHECK_TICK

/// Gives every exposed transit floor a real hull wall instead of leaving it open to space.
/datum/generated_station_materializer/proc/enclose_corridors()
	var/list/to_wall = list()
	for(var/turf/simulated/floor/T in transit_area)
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(T, direction)
			if(istype(neighbor, /turf/space))
				to_wall |= neighbor
	for(var/turf/T as anything in to_wall)
		T.ChangeTurf(spec.architecture_style == "fortified" ? /turf/simulated/wall/r_wall : /turf/simulated/wall, tell_universe = FALSE)
		ChangeArea(T, transit_area)
		result.wall_count++

/// Returns whether a department hull tile has clear room and transit approaches.
/datum/generated_station_materializer/proc/is_interface_door_candidate(datum/generated_station_layout_node/node, local_x, local_y, outward)
	var/turf/T = world_turf(local_x, local_y)
	var/turf/outside = get_step(T, outward)
	var/turf/inside = get_step(T, turn(outward, 180))
	return istype(outside, /turf/simulated/floor) && get_area(outside) == transit_area && istype(inside, /turf/simulated/floor) && node_at(local_x, local_y) == node

/// Converts the center of one continuous corridor frontage into an intentional entrance.
/datum/generated_station_materializer/proc/place_interface_door_run(datum/generated_station_layout_node/node, datum/generated_station_department_instance/department, list/run, outward)
	if(!length(run))
		return
	var/list/point = run[CEILING(length(run) / 2, 1)]
	var/turf/T = world_turf(point[1], point[2])
	T.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
	ChangeArea(T, department_areas[node.id])
	var/obj/machinery/door/airlock/airlock = new(T)
	airlock.set_dir(outward in list(EAST, WEST) ? EAST : NORTH)
	configure_department_airlock(airlock, department)
	result.doors += airlock
	result.door_count++

/// Applies the generated station's department access policy to an entrance.
/datum/generated_station_materializer/proc/configure_department_airlock(obj/machinery/door/airlock/airlock, datum/generated_station_department_instance/department)
	configure_airlock_access(airlock, department?.definition?.id)

/// Applies one department definition's access policy to an airlock.
/datum/generated_station_materializer/proc/configure_airlock_access(obj/machinery/door/airlock/airlock, department_id)
	if(spec.security_tier > 1)
		switch(department_id)
			if("command", "ai")
				airlock.req_access = list(ACCESS_HEADS)
			if("security")
				airlock.req_access = list(ACCESS_SECURITY)
			if("medical")
				airlock.req_access = list(ACCESS_MEDICAL)
			if("engineering")
				airlock.req_access = list(ACCESS_ENGINE)
			if("logistics")
				airlock.req_access = list(ACCESS_CARGO)

/// Connects departments that share a wall with a short internal doorway. The
/// abstract graph may legitimately choose this route instead of the concourse.
/datum/generated_station_materializer/proc/place_department_adjacency_doors()
	if(spec.primary_corridor_axis == "network")
		return
	for(var/datum/generated_station_layout_edge/edge in spec.layout_edges)
		if(edge.kind != GENERATED_STATION_EDGE_TRANSIT)
			continue
		var/datum/generated_station_layout_node/first = nodes_by_id[edge.from_node_id]
		var/datum/generated_station_layout_node/second = nodes_by_id[edge.to_node_id]
		if(!first || !second)
			continue
		var/turf/first_turf
		var/turf/second_turf
		var/door_direction
		if(first.x + first.width == second.x || second.x + second.width == first.x)
			var/start_y = max(first.y + 1, second.y + 1)
			var/end_y = min(first.y + first.height - 2, second.y + second.height - 2)
			if(start_y <= end_y)
				var/door_y = spec.grid_width >= 96 ? start_y + round((end_y - start_y) / 4) : round((start_y + end_y) / 2)
				var/datum/generated_station_layout_node/west = first.x < second.x ? first : second
				var/datum/generated_station_layout_node/east = west == first ? second : first
				first_turf = world_turf(west.x + west.width - 1, door_y)
				second_turf = world_turf(east.x, door_y)
				door_direction = EAST
		else if(first.y + first.height == second.y || second.y + second.height == first.y)
			var/start_x = max(first.x + 1, second.x + 1)
			var/end_x = min(first.x + first.width - 2, second.x + second.width - 2)
			if(start_x <= end_x)
				var/door_x = spec.grid_height >= 96 ? start_x + round((end_x - start_x) / 4) : round((start_x + end_x) / 2)
				var/datum/generated_station_layout_node/south = first.y < second.y ? first : second
				var/datum/generated_station_layout_node/north = south == first ? second : first
				first_turf = world_turf(door_x, south.y + south.height - 1)
				second_turf = world_turf(door_x, north.y)
				door_direction = NORTH
		if(!first_turf || !second_turf)
			continue
		first_turf.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
		second_turf.ChangeTurf(/turf/simulated/floor/tiled, tell_universe = FALSE)
		var/datum/generated_station_layout_node/door_node = node_at(first_turf.x - min_x + 1, first_turf.y - min_y + 1)
		ChangeArea(first_turf, department_areas[door_node.id])
		var/datum/generated_station_layout_node/approach_node = node_at(second_turf.x - min_x + 1, second_turf.y - min_y + 1)
		ChangeArea(second_turf, department_areas[approach_node.id])
		var/obj/machinery/door/airlock/airlock = new(first_turf)
		airlock.set_dir(door_direction)
		configure_department_airlock(airlock, department_for_node(door_node))
		result.doors += airlock
		result.door_count++

/// Places one entrance in each continuous transit frontage instead of filling
/// the entire side of a department with doors beside a main concourse.
/datum/generated_station_materializer/proc/place_interface_doors()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_department_instance/department = department_for_node(node)
		for(var/outward in GLOB.cardinal)
			var/list/run = list()
			var/start = (outward in list(EAST, WEST)) ? node.y + 1 : node.x + 1
			var/finish = (outward in list(EAST, WEST)) ? node.y + node.height - 2 : node.x + node.width - 2
			for(var/coordinate in start to finish + 1)
				var/local_x = outward == WEST ? node.x : outward == EAST ? node.x + node.width - 1 : coordinate
				var/local_y = outward == SOUTH ? node.y : outward == NORTH ? node.y + node.height - 1 : coordinate
				var/valid = coordinate <= finish && is_interface_door_candidate(node, local_x, local_y, outward)
				if(valid)
					run += list(list(local_x, local_y))
				else if(length(run))
					place_interface_door_run(node, department, run, outward)
					run = list()

/// Fills tiny side branches created where widened routes overlap at a bend.
/// Department approaches are retained; only wall-bounded geometric fringes are removed.
/datum/generated_station_materializer/proc/trim_short_transit_stubs()
	var/list/transit_floors = list()
	for(var/turf/simulated/floor/T in transit_area)
		transit_floors[T] = TRUE
	var/list/to_wall = list()
	for(var/turf/simulated/floor/start as anything in transit_floors)
		var/list/neighbors = list()
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(start, direction)
			if(transit_floors[neighbor])
				neighbors += neighbor
		if(length(neighbors) != 1)
			continue
		var/near_entrance = FALSE
		for(var/obj/machinery/door/door in range(2, start))
			if(!istype(get_area(door), /area/generated_station/transit))
				near_entrance = TRUE
				break
		if(near_entrance)
			continue
		var/list/branch = list(start)
		var/turf/previous
		var/turf/current = start
		while(length(branch) <= 20)
			var/list/forward = list()
			for(var/direction in GLOB.cardinal)
				var/turf/neighbor = get_step(current, direction)
				if(neighbor != previous && transit_floors[neighbor])
					forward += neighbor
			if(length(forward) != 1)
				if(length(forward) > 1 && current != start)
					branch -= current
				break
			previous = current
			current = forward[1]
			branch += current
		if(length(branch) <= 20)
			var/keep_from = 0
			for(var/i in 1 to length(branch))
				var/turf/branch_turf = branch[i]
				for(var/obj/machinery/door/door in range(2, branch_turf))
					if(!istype(get_area(door), /area/generated_station/transit))
						keep_from = i
						break
				if(keep_from)
					break
			var/prune_count = keep_from ? keep_from - 1 : length(branch)
			for(var/i in 1 to prune_count)
				to_wall |= branch[i]
	for(var/turf/T as anything in to_wall)
		T.ChangeTurf(spec.architecture_style == "fortified" ? /turf/simulated/wall/r_wall : /turf/simulated/wall, tell_universe = FALSE)
		ChangeArea(T, transit_area)
		result.wall_count++

/// Turns unavoidable short route termini into deliberate rest alcoves.
/datum/generated_station_materializer/proc/furnish_transit_alcoves()
	var/list/transit_floors = list()
	for(var/turf/simulated/floor/T in transit_area)
		transit_floors[T] = TRUE
	for(var/turf/simulated/floor/T as anything in transit_floors)
		var/list/neighbors = list()
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(T, direction)
			if(transit_floors[neighbor])
				neighbors += neighbor
		if(length(neighbors) != 1)
			continue
		var/branch_length = generated_station_dead_end_branch_length(T, transit_floors, 5)
		if(branch_length < 3 || branch_length > 4)
			continue
		var/near_entrance = FALSE
		for(var/obj/machinery/door/door in range(2, T))
			if(!istype(get_area(door), /area/generated_station/transit))
				near_entrance = TRUE
				break
		if(near_entrance || locate(/obj/structure/bed/chair) in T)
			continue
		var/obj/structure/bed/chair/seat = new(T)
		seat.set_dir(get_dir(T, neighbors[1]))
		result.register_furnishing(seat)

/// Adds a sealed two-door EVA vestibule instead of placing a naked maintenance hatch in the hull.
/datum/generated_station_materializer/proc/place_exterior_airlocks()
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/turf/hull_turf
		var/outward
		for(var/x in node.x to node.x + node.width - 1)
			for(var/y in node.y to node.y + node.height - 1)
				var/candidate_outward
				if(x == node.x && y > node.y + 1 && y < node.y + node.height - 2)
					candidate_outward = WEST
				else if(x == node.x + node.width - 1 && y > node.y + 1 && y < node.y + node.height - 2)
					candidate_outward = EAST
				else if(y == node.y && x > node.x + 1 && x < node.x + node.width - 2)
					candidate_outward = SOUTH
				else if(y == node.y + node.height - 1 && x > node.x + 1 && x < node.x + node.width - 2)
					candidate_outward = NORTH
				else
					continue
				var/turf/candidate = world_turf(x, y)
				var/turf/chamber_candidate = get_step(candidate, candidate_outward)
				var/turf/outer_candidate = get_step(chamber_candidate, candidate_outward)
				var/turf/vacuum_candidate = get_step(outer_candidate, candidate_outward)
				var/turf/interior_candidate = get_step(candidate, turn(candidate_outward, 180))
				if(generated_station_architectural_passable(interior_candidate) && istype(chamber_candidate, /turf/space) && istype(outer_candidate, /turf/space) && istype(vacuum_candidate, /turf/space))
					hull_turf = candidate
					outward = candidate_outward
					break
			if(hull_turf)
				break
		if(!hull_turf)
			continue
		var/area/generated_station/A = department_areas[node.id]
		var/turf/chamber = get_step(hull_turf, outward)
		var/turf/outer = get_step(chamber, outward)
		var/hull_local_x = hull_turf.x - result.origin_x + 1
		var/hull_local_y = hull_turf.y - result.origin_y + 1
		var/chamber_local_x = chamber.x - result.origin_x + 1
		var/chamber_local_y = chamber.y - result.origin_y + 1
		var/outer_local_x = outer.x - result.origin_x + 1
		var/outer_local_y = outer.y - result.origin_y + 1
		var/datum/generated_station_tile_intent/hull_intent = result.tile_plan.tile(hull_local_x, hull_local_y)
		var/datum/generated_station_tile_intent/chamber_intent = result.tile_plan.tile(chamber_local_x, chamber_local_y)
		var/datum/generated_station_tile_intent/outer_intent = result.tile_plan.tile(outer_local_x, outer_local_y)
		for(var/datum/generated_station_tile_intent/floor_intent in list(hull_intent, chamber_intent, outer_intent))
			floor_intent.owner_id = node.id
			floor_intent.zone_id = node.id
			floor_intent.structure_kind = GENERATED_STATION_TILE_FLOOR
			floor_intent.floor_type = /turf/simulated/floor/tiled/steel_ridged
		hull_intent.door_type = /obj/machinery/door/airlock/maintenance
		hull_intent.door_direction = (outward in list(EAST, WEST)) ? EAST : NORTH
		outer_intent.door_type = /obj/machinery/door/airlock/generated_station_exterior
		outer_intent.door_direction = (outward in list(EAST, WEST)) ? EAST : NORTH
		hull_turf.ChangeTurf(/turf/simulated/floor/tiled/steel_ridged, tell_universe = FALSE)
		chamber.ChangeTurf(/turf/simulated/floor/tiled/steel_ridged, tell_universe = FALSE)
		outer.ChangeTurf(/turf/simulated/floor/tiled/steel_ridged, tell_universe = FALSE)
		ChangeArea(hull_turf, A)
		ChangeArea(chamber, A)
		ChangeArea(outer, A)
		for(var/side in list(turn(outward, 90), turn(outward, -90)))
			for(var/turf/side_turf in list(get_step(chamber, side), get_step(outer, side)))
				var/side_local_x = side_turf.x - result.origin_x + 1
				var/side_local_y = side_turf.y - result.origin_y + 1
				var/datum/generated_station_tile_intent/side_intent = result.tile_plan.tile(side_local_x, side_local_y)
				side_intent.owner_id = "station-structure"
				side_intent.zone_id = "station-structure"
				side_intent.structure_kind = GENERATED_STATION_TILE_HULL
				side_turf.ChangeTurf(spec.architecture_style == "fortified" ? /turf/simulated/wall/r_wall : /turf/simulated/wall, tell_universe = FALSE)
				ChangeArea(side_turf, A)
		var/obj/machinery/door/airlock/maintenance/inner = new(hull_turf)
		inner.set_dir(outward in list(EAST, WEST) ? EAST : NORTH)
		inner.req_access = list(ACCESS_MAINT_TUNNELS)
		var/obj/machinery/door/airlock/generated_station_exterior/exterior = new(outer)
		exterior.set_dir(outward in list(EAST, WEST) ? EAST : NORTH)
		exterior.req_access = list(ACCESS_MAINT_TUNNELS)
		result.doors += list(inner, exterior)
		result.door_count += 2

/datum/generated_station_materializer/proc/place_entry()
	var/datum/generated_station_layout_node/docking
	for(var/datum/generated_station_layout_node/node in spec.layout_nodes)
		var/datum/generated_station_department_instance/department = department_for_node(node)
		if(department?.definition?.id == "docking")
			docking = node
			break
	if(!docking)
		return
	var/turf/T
	for(var/datum/generated_station_module/module in result.modules)
		if(module.department_node_id != docking.id || module.role != "berth")
			continue
		var/turf/candidate = world_turf(round((module.x1 + module.x2) / 2), round((module.y1 + module.y2) / 2))
		if(istype(candidate, /turf/simulated/floor) && !candidate.density)
			T = candidate
			break
	if(!T)
		var/area/generated_station/docking/docking_area = department_areas[docking.id]
		for(var/turf/simulated/floor/candidate in docking_area)
			if(!candidate.density && !(locate(/obj/machinery/door) in candidate))
				T = candidate
				break
	if(T)
		result.entry = new(T)
		result.entry.station_id = spec.id
		result.register_furnishing(new /obj/item/card/id/generated_station_master(T))

/datum/generated_station_materializer/proc/finalize_wall_adjacencies()
	for(var/key in result.tile_plan?.tiles)
		var/datum/generated_station_tile_intent/intent = result.tile_plan.tiles[key]
		if(intent.structure_kind != GENERATED_STATION_TILE_HULL)
			continue
		var/turf/simulated/wall/wall = result.world_turf(intent.local_x, intent.local_y)
		if(istype(wall))
			// Every generated wall is visited by this pass; propagating here would
			// recompute and redraw each neighbour repeatedly.
			wall.update_connections(FALSE)
			wall.update_icon()
		generation_checkpoint("Updating wall adjacencies", 58)

/datum/generated_station_materializer/proc/finalize()
	// All topology changes are complete before publishing the new z topology or
	// area power state, avoiding partially-built networks becoming observable.
	if(SSair)
		SSair.build_multiz_atmos_levels()
	for(var/node_id in department_areas)
		var/area/generated_station/A = department_areas[node_id]
		A.power_change()
	transit_area.power_change()
