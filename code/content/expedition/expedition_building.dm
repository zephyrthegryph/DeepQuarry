// Procedural building generator (BSP rooms + corridors).
//
// Unlike the cave carver (organic caverns) and the POI scatterers (objects on
// open floor), this lays down actual architecture: it partitions a rectangular
// footprint into leaves, plans a room in each leaf, connects the rooms with
// L-shaped corridors, and marks a door where a corridor breaches a room wall.
// All of that is planned as data (a grid of wall and floor); the footprint is then
// placed once as final turfs (place_turfs), never filled with wall and carved. Rooms
// are furnished, the corridor doors made, and cave-facing entrances punched
// last, in the order the random stream has always been drawn.
//
// build() returns TRUE on success; room_centers then holds the centre coord of
// each room (as list(x, y)) for callers to populate.

/datum/expedition_building
	/// z-level the building is drawn on.
	var/z = 0
	/// Footprint bounds (inclusive).
	var/fx1 = 0
	var/fy1 = 0
	var/fx2 = 0
	var/fy2 = 0
	/// Smallest a BSP region may get before it stops splitting.
	var/min_leaf = 6
	/// BSP leaf rects: each list(x1, y1, x2, y2).
	var/list/leaves
	/// Room rects: each list(rx1, ry1, rx2, ry2).
	var/list/rooms
	/// Room centres: each list(cx, cy).
	var/list/room_centers
	/// The plan: per footprint tile (tile_index()), TRUE for floor and FALSE for wall.
	var/list/tiles
	/// Where a corridor breaches a room wall: each list(x, y), a door once the rooms are furnished.
	var/list/corridor_doors
	/// "x,y" -> list(x, y) for the tiles only a corridor opened (not room floor).
	var/list/corridor_tiles
	var/turf_floor = /turf/simulated/floor/plating
	var/turf_wall = /turf/simulated/wall
	var/door_type = /obj/machinery/door/airlock
	/// Entrances punched through the footprint edge onto open ground.
	var/entrances = 2
	/// Whether to dress rooms with themed furniture + loot.
	var/furnish = TRUE
	/// Loot context, set by the caller so furnished crates roll appropriate tiers.
	var/loot_difficulty = EXP_DIFF_LOW
	var/loot_size = EXP_SIZE_SMALL

// Draw a building centred on `center`, roughly w x h tiles. Returns TRUE if a
// usable structure (at least one room) was produced. With a `seed` the plan (partition, rooms, entrances) is drawn from it. The footprint is planned
// first (partition, rooms, corridors) and placed once as final turfs; rooms are
// then furnished, the corridor doors made and the entrances punched, in the order
// the random stream has always been drawn. A building with no room changes nothing.
/datum/expedition_building/proc/build(turf/center, w = 16, h = 16, seed = null)
	if(!isturf(center))
		return FALSE
	z = center.z
	leaves = list()
	rooms = list()
	room_centers = list()

	fx1 = max(2, center.x - round(w / 2))
	fy1 = max(2, center.y - round(h / 2))
	fx2 = min(world.maxx - 1, fx1 + w)
	fy2 = min(world.maxy - 1, fy1 + h)
	if((fx2 - fx1) < 8 || (fy2 - fy1) < 8)
		return FALSE

	plan_footprint()
	if(seed)
		rand_seed(seed) // the plan is a function of the seed alone
	partition(fx1, fy1, fx2, fy2, 4)
	carve_rooms()
	if(!length(rooms))
		return FALSE
	connect_rooms()
	place_footprint()
	if(furnish)
		furnish_rooms()
	place_corridor_doors()
	place_entrances()
	return TRUE

/// Index of (x, y) in `tiles`, or 0 outside the footprint.
/datum/expedition_building/proc/tile_index(x, y)
	if(x < fx1 || x > fx2 || y < fy1 || y > fy2)
		return 0
	return (x - fx1) * (fy2 - fy1 + 1) + (y - fy1) + 1

/// Every tile of the footprint starts as wall, in the plan only.
/datum/expedition_building/proc/plan_footprint()
	tiles = new /list((fx2 - fx1 + 1) * (fy2 - fy1 + 1))
	for(var/i in 1 to length(tiles))
		tiles[i] = FALSE
	corridor_doors = list()
	corridor_tiles = list()

/// Places the planned footprint: one final turf per tile.
/datum/expedition_building/proc/place_footprint()
	var/list/types = list()
	for(var/x = fx1, x <= fx2, x++)
		for(var/y = fy1, y <= fy2, y++)
			var/turf/T = locate(x, y, z)
			if(!T)
				continue
			types[T] = tiles[tile_index(x, y)] ? turf_floor : turf_wall
	place_turfs(types, label = "expedition building")

// Recursively split the footprint into leaf regions.
/datum/expedition_building/proc/partition(x1, y1, x2, y2, depth)
	var/w = x2 - x1
	var/h = y2 - y1
	if(depth <= 0 || (w < 2 * min_leaf && h < 2 * min_leaf))
		leaves += list(list(x1, y1, x2, y2))
		return
	var/split_vertical
	if(w >= h && w >= 2 * min_leaf)
		split_vertical = TRUE
	else if(h >= 2 * min_leaf)
		split_vertical = FALSE
	else
		leaves += list(list(x1, y1, x2, y2))
		return
	if(split_vertical)
		var/sx = rand(x1 + min_leaf, x2 - min_leaf)
		partition(x1, y1, sx, y2, depth - 1)
		partition(sx + 1, y1, x2, y2, depth - 1)
	else
		var/sy = rand(y1 + min_leaf, y2 - min_leaf)
		partition(x1, y1, x2, sy, depth - 1)
		partition(x1, sy + 1, x2, y2, depth - 1)

// Plan a room (inset, slightly randomised) in each leaf.
/datum/expedition_building/proc/carve_rooms()
	for(var/list/leaf in leaves)
		var/lx1 = leaf[1]
		var/ly1 = leaf[2]
		var/lx2 = leaf[3]
		var/ly2 = leaf[4]
		if((lx2 - lx1) < 4 || (ly2 - ly1) < 4)
			continue
		var/rx1 = lx1 + rand(1, 2)
		var/ry1 = ly1 + rand(1, 2)
		var/rx2 = lx2 - rand(1, 2)
		var/ry2 = ly2 - rand(1, 2)
		if((rx2 - rx1) < 2 || (ry2 - ry1) < 2)
			continue
		for(var/x = rx1, x <= rx2, x++)
			for(var/y = ry1, y <= ry2, y++)
				var/index = tile_index(x, y)
				if(index)
					tiles[index] = TRUE
		rooms += list(list(rx1, ry1, rx2, ry2))
		room_centers += list(list(round((rx1 + rx2) / 2), round((ry1 + ry2) / 2)))

// Chain the room centres together with L-shaped corridors.
/datum/expedition_building/proc/connect_rooms()
	for(var/i = 1, i < length(room_centers), i++)
		var/list/a = room_centers[i]
		var/list/b = room_centers[i + 1]
		plan_corridor(a[1], a[2], b[1], b[2])

/datum/expedition_building/proc/plan_corridor(ax, ay, bx, by)
	for(var/x = min(ax, bx), x <= max(ax, bx), x++)
		plan_corridor_tile(x, ay)
	for(var/y = min(ay, by), y <= max(ay, by), y++)
		plan_corridor_tile(bx, y)

/datum/expedition_building/proc/plan_corridor_tile(x, y)
	var/index = tile_index(x, y)
	if(!index || tiles[index])
		return
	tiles[index] = TRUE
	corridor_tiles["[x],[y]"] = list(x, y)
	// A wall tile on a room's perimeter that a corridor breaches becomes a door.
	if(on_room_ring(x, y))
		corridor_doors += list(list(x, y))

/// The doors where the planned corridors breach a room wall, made now that the rooms are furnished.
/datum/expedition_building/proc/place_corridor_doors()
	var/list/types = list()
	var/list/things = list()
	for(var/list/coords in corridor_doors)
		var/turf/T = locate(coords[1], coords[2], z)
		if(!T || locate_on(T, /obj/machinery/door))
			continue
		types[T] = T.type
		things[T] = list(door_type)
	if(length(types))
		place_turfs(types, things = things, label = "expedition building doors")

/// The turfs only a corridor opened (room furnishing leaves them out of its decoration, which was laid before corridors were carved).
/datum/expedition_building/proc/corridor_turf_set()
	var/list/set_of = list()
	for(var/key in corridor_tiles)
		var/list/coords = corridor_tiles[key]
		var/turf/T = locate(coords[1], coords[2], z)
		if(T)
			set_of[T] = TRUE
	return set_of

// TRUE if (x, y) is on the one-tile wall border of any carved room.
/datum/expedition_building/proc/on_room_ring(x, y)
	for(var/list/r in rooms)
		var/rx1 = r[1]
		var/ry1 = r[2]
		var/rx2 = r[3]
		var/ry2 = r[4]
		if(x >= (rx1 - 1) && x <= (rx2 + 1) && y >= (ry1 - 1) && y <= (ry2 + 1))
			if(x < rx1 || x > rx2 || y < ry1 || y > ry2)
				return TRUE
	return FALSE

// Punch up to `entrances` doors on footprint edges that border open cavern, each
// tunnelled inward to the nearest room so the structure is enterable.
/datum/expedition_building/proc/place_entrances()
	var/list/candidates = list()
	for(var/x = fx1, x <= fx2, x++)
		add_edge_candidate(x, fy1, 0, -1, candidates)
		add_edge_candidate(x, fy2, 0, 1, candidates)
	for(var/y = fy1, y <= fy2, y++)
		add_edge_candidate(fx1, y, -1, 0, candidates)
		add_edge_candidate(fx2, y, 1, 0, candidates)
	var/placed = 0
	while(length(candidates) && placed < entrances)
		var/list/c = pick_n_take(candidates)
		if(carve_entrance(c[1], c[2], c[3], c[4]))
			placed++

/datum/expedition_building/proc/add_edge_candidate(x, y, dx, dy, list/candidates)
	var/turf/outside = locate(x + dx, y + dy, z)
	if(outside && !outside.density)
		candidates += list(list(x, y, dx, dy))

/// One entrance: the edge tile and the tunnel inward to the nearest room, placed together with their doors.
/datum/expedition_building/proc/carve_entrance(x, y, dx, dy)
	var/turf/edge = locate(x, y, z)
	if(!edge)
		return FALSE
	var/list/types = list()
	var/list/things = list()
	types[edge] = turf_floor
	if(!locate_on(edge, /obj/machinery/door))
		things[edge] = list(door_type)
	// Tunnel from just inside the edge to the nearest room centre.
	var/inx = x - dx
	var/iny = y - dy
	var/list/nearest = nearest_room_center(inx, iny)
	if(nearest)
		tunnel_corridor(inx, iny, nearest[1], nearest[2], types, things)
	place_turfs(types, things = things, label = "expedition building entrance")
	return TRUE

/datum/expedition_building/proc/tunnel_corridor(ax, ay, bx, by, list/types, list/things)
	for(var/x = min(ax, bx), x <= max(ax, bx), x++)
		tunnel_corridor_tile(x, ay, types, things)
	for(var/y = min(ay, by), y <= max(ay, by), y++)
		tunnel_corridor_tile(bx, y, types, things)

/// A tunnel tile still wall (and not already planned) becomes floor, with a door where it breaches a room wall.
/datum/expedition_building/proc/tunnel_corridor_tile(x, y, list/types, list/things)
	var/turf/T = locate(x, y, z)
	if(!T || !T.density || (T in types))
		return
	types[T] = turf_floor
	if(on_room_ring(x, y) && !(locate_on(T, /obj/machinery/door)))
		things[T] = list(door_type)

/datum/expedition_building/proc/nearest_room_center(x, y)
	var/list/best = null
	var/best_dist = INFINITY
	for(var/list/c in room_centers)
		var/d = abs(c[1] - x) + abs(c[2] - y)
		if(d < best_dist)
			best_dist = d
			best = c
	return best

// ---- Furnishing -----------------------------------------------------------
// Each room gets a theme and a light scatter of matching furniture (kept under
// a third of the floor so the room stays walkable). Crates may hold loot.

GLOBAL_LIST_INIT(expedition_room_furniture, list(
	"storage" = list(
		/obj/structure/closet/crate,
		/obj/structure/closet/crate,
		/obj/structure/closet,
		/obj/structure/table/standard,
	),
	"quarters" = list(
		/obj/structure/bed,
		/obj/structure/bed/chair,
		/obj/structure/table/standard,
		/obj/structure/closet,
	),
	"work" = list(
		/obj/structure/table/standard,
		/obj/structure/table/standard,
		/obj/structure/bed/chair,
		/obj/structure/closet,
	),
))

/// The furniture palette for a room theme (shared, read-only), or null for "empty".
/datum/expedition_building/proc/furniture_for(theme)
	return GLOB.expedition_room_furniture[theme]

/datum/expedition_building/proc/furnish_rooms()
	for(var/list/r in rooms)
		furnish_room(r)

/datum/expedition_building/proc/furnish_room(list/r)
	var/theme = pick("storage", "quarters", "work", "empty")
	var/list/palette = furniture_for(theme)
	if(!length(palette))
		return
	var/rx1 = r[1]
	var/ry1 = r[2]
	var/rx2 = r[3]
	var/ry2 = r[4]
	var/cx = round((rx1 + rx2) / 2)
	var/cy = round((ry1 + ry2) / 2)
	// Candidate floor tiles, leaving the centre clear for the corridor/spawns.
	var/list/spots = list()
	for(var/x = rx1, x <= rx2, x++)
		for(var/y = ry1, y <= ry2, y++)
			if(x == cx && y == cy)
				continue
			var/turf/T = locate(x, y, z)
			if(T && !T.density)
				spots += T
	var/count = max(1, round(length(spots) / 3))
	for(var/i in 1 to count)
		if(!length(spots))
			break
		var/turf/T = pick_n_take(spots)
		var/ftype = pick(palette)
		var/obj/o = new ftype(T)
		// Crates and closets may hold tier-rolled loot.
		if(istype(o, /obj/structure/closet) && prob(55))
			expedition_spawn_loot(null, expedition_roll_tier(loot_difficulty, loot_size), o)
	// A little grime/remains so rooms feel lived-in (and abandoned).
	if(prob(60))
		expedition_decorate(locate(cx, cy, z), 2, rand(1, 3), corridor_turf_set())
