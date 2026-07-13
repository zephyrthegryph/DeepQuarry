// Procedural building generator (BSP rooms + corridors).
//
// Unlike the cave carver (organic caverns) and the POI scatterers (objects on
// open floor), this lays down actual architecture: it fills a rectangular
// footprint with wall, binary-space-partitions it into leaves, carves a room in
// each leaf, connects the rooms with L-shaped corridors, drops doors where a
// corridor breaches a room wall, and punches cave-facing entrances so the
// structure is reachable from the surrounding cavern.
//
// build() returns TRUE on success; room_centers then holds the centre coord of
// each carved room (as list(x, y)) for callers to populate.
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
	/// Carved room rects: each list(rx1, ry1, rx2, ry2).
	var/list/rooms
	/// Room centres: each list(cx, cy).
	var/list/room_centers
	var/turf_floor = /turf/simulated/floor/plating
	var/turf_wall = /turf/simulated/wall
	var/door_type = /obj/machinery/door/airlock
	/// Whether to dress carved rooms with themed furniture + loot.
	var/furnish = TRUE
	/// Loot context, set by the caller so furnished crates roll appropriate tiers.
	var/loot_difficulty = EXP_DIFF_LOW
	var/loot_size = EXP_SIZE_SMALL
	var/datum/expedition_biome/loot_biome = null

// Draw a building centred on `center`, roughly w x h tiles. Returns TRUE if a
// usable structure (at least one room) was produced.
/datum/expedition_building/proc/build(turf/center, w = 16, h = 16)
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

	fill_footprint()
	partition(fx1, fy1, fx2, fy2, 4)
	carve_rooms()
	if(!length(rooms))
		return FALSE
	if(furnish)
		furnish_rooms()
	connect_rooms()
	place_entrances()
	return TRUE

// Clear the footprint and solidify it to wall — the negative space rooms and
// corridors are then carved out of.
/datum/expedition_building/proc/fill_footprint()
	var/n = 0
	for(var/x = fx1, x <= fx2, x++)
		for(var/y = fy1, y <= fy2, y++)
			var/turf/T = locate(x, y, z)
			if(!T)
				continue
			for(var/atom/movable/AM in T)
				if(ismob(AM))
					var/mob/M = AM
					if(M.client)
						continue
				qdel(AM)
			T.ChangeTurf(turf_wall, tell_universe = FALSE)
			if(++n % 200 == 0)
				CHECK_TICK

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

// Carve a room (inset, slightly randomised) into each leaf.
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
				var/turf/T = locate(x, y, z)
				if(T)
					T.ChangeTurf(turf_floor, tell_universe = FALSE)
		rooms += list(list(rx1, ry1, rx2, ry2))
		room_centers += list(list(round((rx1 + rx2) / 2), round((ry1 + ry2) / 2)))

// Chain the room centres together with L-shaped corridors.
/datum/expedition_building/proc/connect_rooms()
	for(var/i = 1, i < length(room_centers), i++)
		var/list/a = room_centers[i]
		var/list/b = room_centers[i + 1]
		carve_corridor(a[1], a[2], b[1], b[2])

/datum/expedition_building/proc/carve_corridor(ax, ay, bx, by)
	for(var/x = min(ax, bx), x <= max(ax, bx), x++)
		carve_corridor_tile(x, ay)
	for(var/y = min(ay, by), y <= max(ay, by), y++)
		carve_corridor_tile(bx, y)

/datum/expedition_building/proc/carve_corridor_tile(x, y)
	var/turf/T = locate(x, y, z)
	if(!T)
		return
	var/was_wall = T.density
	if(was_wall)
		T.ChangeTurf(turf_floor, tell_universe = FALSE)
		// A wall tile on a room's perimeter that a corridor breaches becomes a door.
		if(on_room_ring(x, y) && !(locate(/obj/machinery/door) in T))
			new door_type(T)

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

// Punch up to two doors on footprint edges that border open cavern, each
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
	while(length(candidates) && placed < 2)
		var/list/c = pick_n_take(candidates)
		if(carve_entrance(c[1], c[2], c[3], c[4]))
			placed++

/datum/expedition_building/proc/add_edge_candidate(x, y, dx, dy, list/candidates)
	var/turf/outside = locate(x + dx, y + dy, z)
	if(outside && !outside.density)
		candidates += list(list(x, y, dx, dy))

/datum/expedition_building/proc/carve_entrance(x, y, dx, dy)
	var/turf/edge = locate(x, y, z)
	if(!edge)
		return FALSE
	edge.ChangeTurf(turf_floor, tell_universe = FALSE)
	if(!(locate(/obj/machinery/door) in edge))
		new door_type(edge)
	// Tunnel from just inside the edge to the nearest room centre.
	var/inx = x - dx
	var/iny = y - dy
	var/list/nearest = nearest_room_center(inx, iny)
	if(nearest)
		carve_corridor(inx, iny, nearest[1], nearest[2])
	return TRUE

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

/datum/expedition_building/proc/furniture_for(theme)
	switch(theme)
		if("storage")
			return list(
				/obj/structure/closet/crate,
				/obj/structure/closet/crate,
				/obj/structure/closet,
				/obj/structure/table/standard,
			)
		if("quarters")
			return list(
				/obj/structure/bed,
				/obj/structure/bed/chair,
				/obj/structure/table/standard,
				/obj/structure/closet,
			)
		if("work")
			return list(
				/obj/structure/table/standard,
				/obj/structure/table/standard,
				/obj/structure/bed/chair,
				/obj/structure/closet,
			)
	return null // "empty"

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
		expedition_decorate(locate(cx, cy, z), 2, loot_biome, rand(1, 3))
