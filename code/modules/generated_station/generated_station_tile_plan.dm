#define GENERATED_STATION_UTILITY_APC "apc"
#define GENERATED_STATION_UTILITY_APC_TERMINAL "apc-terminal"
#define GENERATED_STATION_UTILITY_VENT "vent"
#define GENERATED_STATION_UTILITY_SCRUBBER "scrubber"
#define GENERATED_STATION_UTILITY_AIR_ALARM "air-alarm"
#define GENERATED_STATION_UTILITY_FIRE_ALARM "fire-alarm"
#define GENERATED_STATION_UTILITY_LIGHT "light"
#define GENERATED_STATION_UTILITY_SMES "smes"
#define GENERATED_STATION_UTILITY_GENERATOR "generator"
#define GENERATED_STATION_UTILITY_SUPPLY_TANK "supply-tank"
#define GENERATED_STATION_UTILITY_SCRUB_TANK "scrub-tank"
#define GENERATED_STATION_UTILITY_POWER_ROUTE "power-route"
#define GENERATED_STATION_UTILITY_SUPPLY_ROUTE "supply-route"
#define GENERATED_STATION_UTILITY_SCRUB_ROUTE "scrub-route"

/// Complete, immutable-by-convention description of one generated map coordinate.
/// Geometry is rejected when two producers disagree instead of resolving by write order.
/datum/generated_station_tile_intent
	var/local_x
	var/local_y
	var/owner_id
	var/zone_id
	var/structure_kind = GENERATED_STATION_TILE_EXTERIOR
	var/floor_type
	var/access_id
	var/door_type
	var/door_direction
	var/list/utility_intents
	var/list/utility_wall_directions

/datum/generated_station_tile_intent/New(new_x, new_y)
	..()
	local_x = new_x
	local_y = new_y
	utility_intents = list()
	utility_wall_directions = list()

/// Returns whether this coordinate is authoritative structural support for a wall fixture.
/datum/generated_station_tile_intent/proc/is_structural_wall()
	return structure_kind == GENERATED_STATION_TILE_HULL

/datum/generated_station_tile_intent/proc/has_utility_fixture()
	for(var/utility_id in utility_intents)
		switch(utility_id)
			if(GENERATED_STATION_UTILITY_APC, GENERATED_STATION_UTILITY_AIR_ALARM, GENERATED_STATION_UTILITY_FIRE_ALARM, GENERATED_STATION_UTILITY_LIGHT, GENERATED_STATION_UTILITY_VENT, GENERATED_STATION_UTILITY_SCRUBBER, GENERATED_STATION_UTILITY_SMES, GENERATED_STATION_UTILITY_GENERATOR, GENERATED_STATION_UTILITY_SUPPLY_TANK, GENERATED_STATION_UTILITY_SCRUB_TANK)
				return TRUE
	return FALSE

/datum/generated_station_tile_intent/proc/has_wall_utility_fixture()
	for(var/utility_id in utility_intents)
		if(utility_id in list(GENERATED_STATION_UTILITY_APC, GENERATED_STATION_UTILITY_AIR_ALARM, GENERATED_STATION_UTILITY_FIRE_ALARM, GENERATED_STATION_UTILITY_LIGHT))
			return TRUE
	return FALSE

/// Authoritative geometry between the abstract planner and the BYOND map.
/datum/generated_station_tile_plan
	var/grid_width
	var/grid_height
	var/list/tiles
	var/list/errors
	/// Exclusive fixture ownership keyed by structural wall coordinate and room-facing side.
	var/list/wall_fixture_edges
	var/tmp/datum/generated_station_materializer/generation_owner
	var/list/utility_floors_by_owner
	var/list/utility_floors_by_zone
	/// Working state of derive_hull_step() and validate_seal_step() between slices.
	var/tmp/list/hull_openings
	var/tmp/list/hull_coordinates
	var/tmp/list/hull_corners
	var/tmp/list/seal_open
	var/tmp/list/seal_visited
	var/tmp/list/seal_queued
	var/tmp/seal_open_count = 0

CAPABILITIES(/datum/generated_station_tile_plan)
	owns_many(nameof(tiles))

/// `deferred`: the grid is filled a column at a time by fill_column() (the materializer's phases).
/datum/generated_station_tile_plan/New(new_width, new_height, datum/generated_station_materializer/new_generation_owner, deferred = FALSE)
	..()
	grid_width = new_width
	grid_height = new_height
	rel_take_all(src, nameof(tiles))
	errors = list()
	wall_fixture_edges = list()
	utility_floors_by_owner = list()
	utility_floors_by_zone = list()
	rel_set(src, nameof(generation_owner), new_generation_owner)
	if(!deferred)
		for(var/x in 1 to grid_width)
			fill_column(x)

/datum/generated_station_tile_plan/proc/fill_column(x)
	for(var/y in 1 to grid_height)
		rel_add(src, nameof(tiles), new /datum/generated_station_tile_intent(x, y), coordinate_key(x, y))


/datum/generated_station_tile_plan/proc/coordinate_key(local_x, local_y)
	return "[local_x],[local_y]"

/datum/generated_station_tile_plan/proc/tile(local_x, local_y) as /datum/generated_station_tile_intent
	if(local_x < 1 || local_y < 1 || local_x > grid_width || local_y > grid_height)
		return null
	return tiles?[coordinate_key(local_x, local_y)]

/// Builds the utility candidate index once. Utility planning previously scanned
/// the complete grid independently for every fixture in every room.
/datum/generated_station_tile_plan/proc/index_utility_floors()
	utility_floors_by_owner.Cut()
	utility_floors_by_zone.Cut()
	for(var/key in tiles)
		var/datum/generated_station_tile_intent/intent = tiles?[key]
		if(intent.structure_kind != GENERATED_STATION_TILE_FLOOR)
			continue
		if(!utility_floors_by_owner[intent.owner_id])
			utility_floors_by_owner[intent.owner_id] = list()
		var/list/owner_floors = utility_floors_by_owner[intent.owner_id]
		owner_floors += intent
		if(intent.zone_id)
			if(!utility_floors_by_zone[intent.zone_id])
				utility_floors_by_zone[intent.zone_id] = list()
			var/list/zone_floors = utility_floors_by_zone[intent.zone_id]
			zone_floors += intent
		generation_owner()?.generation_checkpoint("Indexing utility sockets", 31)

/datum/generated_station_tile_plan/proc/utility_floors(owner_id, zone_id)
	return zone_id ? utility_floors_by_zone[zone_id] : utility_floors_by_owner[owner_id]

/// Claims a coordinate. Repeating the exact claim is harmless; conflicting claims fail.
/datum/generated_station_tile_plan/proc/claim(local_x, local_y, owner_id, zone_id, structure_kind, floor_type, access_id)
	var/datum/generated_station_tile_intent/intent = tile(local_x, local_y)
	if(!intent)
		errors += "Claim outside station bounds at [local_x],[local_y]."
		return FALSE
	if(intent.structure_kind != GENERATED_STATION_TILE_EXTERIOR)
		if(intent.owner_id == owner_id && intent.zone_id == zone_id && intent.structure_kind == structure_kind && intent.floor_type == floor_type && intent.access_id == access_id)
			return TRUE
		errors += "Tile [local_x],[local_y] is owned by [intent.owner_id]/[intent.zone_id] as [intent.structure_kind], conflicting with [owner_id]/[zone_id] as [structure_kind]."
		return FALSE
	intent.owner_id = owner_id
	intent.zone_id = zone_id
	intent.structure_kind = structure_kind
	intent.floor_type = floor_type
	intent.access_id = access_id
	return TRUE

/// Refines structure inside an owner's reservation. Only the existing owner may do this.
/datum/generated_station_tile_plan/proc/refine(local_x, local_y, owner_id, structure_kind, floor_type)
	var/datum/generated_station_tile_intent/intent = tile(local_x, local_y)
	if(!intent || intent.owner_id != owner_id)
		errors += "[owner_id] cannot refine tile [local_x],[local_y] owned by [intent?.owner_id]."
		return FALSE
	intent.structure_kind = structure_kind
	intent.floor_type = floor_type
	return TRUE

/// Adds an atom socket without changing structural ownership.
/datum/generated_station_tile_plan/proc/claim_door(local_x, local_y, owner_id, new_door_type, new_direction, new_access_id)
	var/datum/generated_station_tile_intent/intent = tile(local_x, local_y)
	if(!intent || intent.owner_id != owner_id || intent.structure_kind != GENERATED_STATION_TILE_FLOOR || intent.door_type)
		errors += "Invalid or conflicting door socket for [owner_id] at [local_x],[local_y]."
		return FALSE
	intent.door_type = new_door_type
	intent.door_direction = new_direction
	intent.access_id = new_access_id
	return TRUE

/datum/generated_station_tile_plan/proc/claim_utility(local_x, local_y, owner_id, utility_id)
	var/datum/generated_station_tile_intent/intent = tile(local_x, local_y)
	if(!intent || intent.owner_id != owner_id || intent.structure_kind == GENERATED_STATION_TILE_EXTERIOR)
		errors += "Invalid utility socket [utility_id] for [owner_id] at [local_x],[local_y]."
		return FALSE
	if(utility_id in intent.utility_intents)
		return TRUE
	intent.utility_intents += utility_id
	return TRUE

/// Reserves a fixture socket. Fixtures are exclusive; hidden routes may coexist below them.
/datum/generated_station_tile_plan/proc/claim_utility_fixture(local_x, local_y, owner_id, utility_id)
	var/datum/generated_station_tile_intent/intent = tile(local_x, local_y)
	if(!intent || intent.owner_id != owner_id || intent.structure_kind != GENERATED_STATION_TILE_FLOOR || intent.door_type)
		errors += "Invalid utility fixture [utility_id] for [owner_id] at [local_x],[local_y]."
		return FALSE
	for(var/existing_id in intent.utility_intents)
		if(existing_id != GENERATED_STATION_UTILITY_POWER_ROUTE && existing_id != GENERATED_STATION_UTILITY_SUPPLY_ROUTE && existing_id != GENERATED_STATION_UTILITY_SCRUB_ROUTE)
			var/new_is_wall_fixture = utility_id in list(GENERATED_STATION_UTILITY_APC, GENERATED_STATION_UTILITY_AIR_ALARM, GENERATED_STATION_UTILITY_FIRE_ALARM, GENERATED_STATION_UTILITY_LIGHT)
			var/existing_is_wall_fixture = existing_id in list(GENERATED_STATION_UTILITY_APC, GENERATED_STATION_UTILITY_AIR_ALARM, GENERATED_STATION_UTILITY_FIRE_ALARM, GENERATED_STATION_UTILITY_LIGHT)
			var/new_is_floor_atmos = utility_id in list(GENERATED_STATION_UTILITY_VENT, GENERATED_STATION_UTILITY_SCRUBBER)
			var/existing_is_floor_atmos = existing_id in list(GENERATED_STATION_UTILITY_VENT, GENERATED_STATION_UTILITY_SCRUBBER)
			if((new_is_wall_fixture && existing_is_floor_atmos) || (new_is_floor_atmos && existing_is_wall_fixture))
				continue
			if(new_is_wall_fixture && existing_is_wall_fixture)
				continue
			errors += "Utility fixture [utility_id] conflicts with [existing_id] at [local_x],[local_y]."
			return FALSE
	if(utility_id in list(GENERATED_STATION_UTILITY_APC, GENERATED_STATION_UTILITY_AIR_ALARM, GENERATED_STATION_UTILITY_FIRE_ALARM, GENERATED_STATION_UTILITY_LIGHT))
		var/wall_direction
		var/wall_edge_key
		for(var/direction in GLOB.cardinal)
			var/datum/generated_station_tile_intent/support = tile(local_x + (direction == EAST) - (direction == WEST), local_y + (direction == NORTH) - (direction == SOUTH))
			if(!support?.is_structural_wall())
				continue
			var/candidate_edge_key = "[support.local_x],[support.local_y],[direction]"
			if(wall_fixture_edges[candidate_edge_key])
				continue
			wall_direction = direction
			wall_edge_key = candidate_edge_key
			break
		if(!wall_direction)
			errors += "Wall fixture [utility_id] has no unclaimed structural edge at [local_x],[local_y]."
			return FALSE
		wall_fixture_edges[wall_edge_key] = utility_id
		intent.utility_wall_directions[utility_id] = wall_direction
	intent.utility_intents += utility_id
	return TRUE

/datum/generated_station_tile_plan/proc/has_utility(local_x, local_y, utility_id)
	var/datum/generated_station_tile_intent/intent = tile(local_x, local_y)
	return intent && (utility_id in intent.utility_intents)

/// Derives hull from the union of all pressure-bearing floors.
/datum/generated_station_tile_plan/proc/derive_hull(wall_owner_id = "station-hull")
	var/cursor = derive_hull_step(null, wall_owner_id)
	while(!isnull(cursor))
		cursor = derive_hull_step(cursor, wall_owner_id)
	return !length(errors)

/// derive_hull() a slice at a time: `cursor` is list(stage, index) (null to start); returns the
/// cursor to resume from, or null when the hull is claimed.
/datum/generated_station_tile_plan/proc/derive_hull_step(list/cursor, wall_owner_id = "station-hull")
	var/stage = cursor ? cursor[1] : 1
	var/i = cursor ? cursor[2] : 1
	if(!cursor)
		hull_openings = list()
		hull_coordinates = list()
		rel_clear(src, nameof(hull_corners))
	var/count = length(tiles)
	if(stage == 1)
		for(var/n in i to count)
			var/datum/generated_station_tile_intent/door_intent = tiles?[tiles?[n]]
			if(door_intent.door_type && ispath(door_intent.door_type, /obj/machinery/door/airlock/generated_station_exterior))
				var/open_x = door_intent.local_x + (door_intent.door_direction == EAST) - (door_intent.door_direction == WEST)
				var/open_y = door_intent.local_y + (door_intent.door_direction == NORTH) - (door_intent.door_direction == SOUTH)
				hull_openings[coordinate_key(open_x, open_y)] = TRUE
			if(n < count && generation_owner()?.generation_checkpoint("Deriving station hull", 29))
				return list(1, n + 1)
		stage = 2
		i = 1
	if(stage == 2)
		for(var/n in i to count)
			var/datum/generated_station_tile_intent/intent = tiles?[tiles?[n]]
			if(intent.structure_kind == GENERATED_STATION_TILE_FLOOR)
				for(var/list/offset in list(list(1, 0), list(-1, 0), list(0, 1), list(0, -1)))
					var/datum/generated_station_tile_intent/neighbor = tile(intent.local_x + offset[1], intent.local_y + offset[2])
					if(neighbor && hull_openings[coordinate_key(neighbor.local_x, neighbor.local_y)])
						continue
					if(neighbor && neighbor.structure_kind == GENERATED_STATION_TILE_EXTERIOR)
						var/list/hull_cell = list(neighbor.local_x, neighbor.local_y) // coordinates, not the intent (plain data)
						hull_coordinates[coordinate_key(neighbor.local_x, neighbor.local_y)] = hull_cell
			if(n < count && generation_owner()?.generation_checkpoint("Deriving station hull", 29))
				return list(2, n + 1)
		for(var/key in hull_coordinates)
			var/list/hull_xy = hull_coordinates[key]
			claim(hull_xy[1], hull_xy[2], wall_owner_id, "hull", GENERATED_STATION_TILE_HULL, null, null)
		stage = 3
		i = 1
	// Close convex corners with the one exterior cell shared by their two
	// perpendicular wall runs. Arbitrarily extending isolated walls creates thick
	// blocks and buried wall cells; a geometric corner claim is deterministic.
	for(var/n in i to count)
		var/datum/generated_station_tile_intent/intent = tiles?[tiles?[n]]
		if(intent.structure_kind == GENERATED_STATION_TILE_EXTERIOR)
			var/north = tile(intent.local_x, intent.local_y + 1)?.structure_kind == GENERATED_STATION_TILE_HULL
			var/south = tile(intent.local_x, intent.local_y - 1)?.structure_kind == GENERATED_STATION_TILE_HULL
			var/east = tile(intent.local_x + 1, intent.local_y)?.structure_kind == GENERATED_STATION_TILE_HULL
			var/west = tile(intent.local_x - 1, intent.local_y)?.structure_kind == GENERATED_STATION_TILE_HULL
			if((north || south) && (east || west) && (north + south + east + west == 2))
				rel_add(src, nameof(hull_corners), intent)
		if(n < count && generation_owner()?.generation_checkpoint("Closing station hull corners", 30))
			return list(3, n + 1)
	for(var/datum/generated_station_tile_intent/intent in hull_corners)
		claim(intent.local_x, intent.local_y, wall_owner_id, "hull", GENERATED_STATION_TILE_HULL, null, null)
	hull_openings = null
	hull_coordinates = null
	rel_clear(src, nameof(hull_corners))
	return null

/// Floods vacuum from the map edge and proves it cannot reach a pressurized floor.
/datum/generated_station_tile_plan/proc/validate_exterior_seal()
	var/cursor = validate_seal_step(null)
	while(!isnull(cursor))
		cursor = validate_seal_step(cursor)
	return !length(errors)

/// validate_exterior_seal() a slice at a time: the flood's work queue lives on the plan between
/// slices. Returns TRUE to be called again, or null when the proof is done (errors hold the result).
/datum/generated_station_tile_plan/proc/validate_seal_step(cursor)
	if(!cursor)
		var/cell_count = grid_width * grid_height
		seal_open = new /list(cell_count)
		seal_visited = new /list(cell_count)
		seal_queued = new /list(cell_count)
		seal_open_count = 0
		for(var/x in 1 to grid_width)
			seal_enqueue(tile(x, 1))
			seal_enqueue(tile(x, grid_height))
		for(var/y in 1 to grid_height)
			seal_enqueue(tile(1, y))
			seal_enqueue(tile(grid_width, y))
		if(generation_owner()?.generation_checkpoint("Seeding pressure-hull work queue", 30, TRUE))
			return TRUE
	var/list/open = seal_open
	var/list/visited = seal_visited
	while(seal_open_count)
		var/key = open[seal_open_count]
		open[seal_open_count--] = null
		var/datum/generated_station_tile_intent/current = tile(((key - 1) % grid_width) + 1, round((key - 1) / grid_width) + 1)
		if(!current)
			continue
		if(visited[key] || current.structure_kind == GENERATED_STATION_TILE_HULL || (current.door_type && ispath(current.door_type, /obj/machinery/door/airlock/generated_station_exterior)))
			continue
		visited[key] = TRUE
		if(current.structure_kind == GENERATED_STATION_TILE_FLOOR)
			errors += "Exterior vacuum reaches floor at [current.local_x],[current.local_y]."
			continue
		for(var/direction in GLOB.cardinal)
			var/neighbor_x = current.local_x + (direction == EAST) - (direction == WEST)
			var/neighbor_y = current.local_y + (direction == NORTH) - (direction == SOUTH)
			var/datum/generated_station_tile_intent/neighbor = tile(neighbor_x, neighbor_y)
			if(neighbor && !visited[(neighbor.local_y - 1) * grid_width + neighbor.local_x])
				seal_enqueue(neighbor)
		if(seal_open_count && generation_owner()?.generation_checkpoint("Validating station pressure hull", 30))
			return TRUE
	seal_open = null
	seal_visited = null
	seal_queued = null
	return null

/datum/generated_station_tile_plan/proc/seal_enqueue(datum/generated_station_tile_intent/intent)
	var/key = (intent.local_y - 1) * grid_width + intent.local_x
	if(seal_queued[key])
		return
	seal_queued[key] = TRUE
	seal_open[++seal_open_count] = key // the cell index (plain data): validate_seal_step() looks the tile up


/// Accessor for the generation_owner var.
/datum/generated_station_tile_plan/proc/generation_owner() as /datum/generated_station_materializer
	return generation_owner

/datum/generated_station_tile_plan/declared_cache_vars()
	var/list/L = ..()
	L = L ? L.Copy() : list()
	L["hull_coordinates"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	L["hull_corners"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	L["seal_open"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	return L
