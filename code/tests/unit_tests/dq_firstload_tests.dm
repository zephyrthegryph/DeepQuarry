// First loads (gen/first-loads): what building a site after boot costs, as deterministic counts.

/// Seeds the equivalence and census tests build from.
#define FIRSTLOAD_SEEDS list(11, 222, 3333)

/// Pins of what the building generator builds from each seed (seed -> md5 of dq_firstload_digest()): the layout with its doors, then with one
/// entrance. Recorded from the data-first generator, with coordinates relative to the building's origin (a golden that moved with the world's size would pin the wrong thing). They are not the fill-then-carve generator's: that one drew from the random stream while its
/// turfs initialized (a filled footprint of walls, a floor per room tile), so its rooms depended on those draws and no seed reproduces them
/// without the wasted turfs. What carries over is the algorithm (partition, rooms, corridors, doors, entrances, run verbatim) and the
/// layout invariants dq_firstload_building_invariants() checks.
GLOBAL_LIST_INIT(firstload_golden_building_layout, list(
	"11" = "4044d029c2d3b43b818b835aa25c6c47",
	"222" = "7804040ccdaf97f13a2b6c353f87caa9",
	"3333" = "7613a1ba78043c3be8c85c20dc1f776a",
))
GLOBAL_LIST_INIT(firstload_golden_building_entrance, list(
	"11" = "89d33a19e1c14c1ce9567124222a1069",
	"222" = "b7669b9a3513124906d8a42bfe391305",
	"3333" = "935eea404fc44a468ae8c4cf4e020c4c",
))

/// The turfs of `z` that have run their Initialize().
/proc/dq_firstload_initialized_turfs(z)
	var/n = 0
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.flags & ATOM_INITIALIZED)
			n++
	return n

/// A footprint-sized census line: turf and movable counts of a rectangle.
/proc/dq_firstload_rect_census(z, x1, y1, x2, y2)
	var/turfs = 0
	var/atoms = 0
	for(var/turf/T as anything in block(locate(x1, y1, z), locate(x2, y2, z)))
		turfs++
		atoms += length(T.contents)
	return "turfs=[turfs] contents=[atoms]"

/// How a new z-level is built: the builtin makes the turfs without initializing them (the load's chunked init job does that), and every
/// turf of the level ends initialized.
/datum/unit_test/dq_firstload_new_z_defers_init

/datum/unit_test/dq_firstload_new_z_defers_init/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/datum/map_load/M = new(template, MAP_LOAD_NEW_Z, FALSE)
	var/t0 = REALTIMEOFDAY
	M.advance(TRUE) // PREPARE: the level is allocated
	var/z = M.new_z
	TEST_ASSERT(z, "the load allocated a z-level")
	var/total = world.maxx * world.maxy
	var/initialized_by_alloc = dq_firstload_initialized_turfs(z)
	log_test("FIRSTLOAD maxz++: [total] turfs, [initialized_by_alloc] initialized inside the allocation, [(REALTIMEOFDAY - t0) / 10]s")
	TEST_ASSERT_EQUAL(initialized_by_alloc, 0, "no turf of the new level initializes inside the allocation call")
	var/steps = 0
	while(M.advance(TRUE) == JOB_MORE)
		steps++
	TEST_ASSERT(M.result, "the blank expedition template loaded")
	var/final_total = world.maxx * world.maxy
	log_test("FIRSTLOAD load_new_z(expedition_site) [steps] steps, total [(REALTIMEOFDAY - t0) / 10]s, initialized turfs [dq_firstload_initialized_turfs(z)] of [final_total]")
	TEST_ASSERT_EQUAL(dq_firstload_initialized_turfs(z), final_total, "every turf of the new level ends initialized")
	test_driver_end()

/// A text digest of a rectangle of `z`, coordinates relative to its first corner (so it does not change with where the world puts the rectangle): each turf's type and area, and the sorted types of what stands on it.
/proc/dq_firstload_digest(z, x1, y1, x2, y2)
	var/list/rows = list()
	for(var/y in y1 to y2)
		for(var/x in x1 to x2)
			var/turf/T = locate(x, y, z)
			var/list/stuff = list()
			for(var/atom/movable/AM as anything in T)
				// Rolled loot is not a seeded draw (its item init has its own randomness): items count, their kind does not.
				if(istype(AM, /obj/effect/decal/cleanable))
					continue // a floor drops dirt at random when it initializes: not a function of the seed or of how the site was built
				stuff += isitem(AM) ? "/obj/item" : "[AM.type]"
			sortTim(stuff, GLOBAL_PROC_REF(cmp_text_asc))
			rows += "[x - x1],[y - y1]:[T.type]@[T.loc.type]=[stuff.Join("+")]"
	return rows

/// md5 of a digest.
/proc/dq_firstload_hash(list/rows)
	return md5(rows.Join("\n"))

/// A fresh blank expedition z, and a building drawn on it from `seed`: the layout, rooms, corridors and their doors (no furniture, no
/// entrances: what the furniture's and doors' own initialization draws from the random stream is not a function of the seed).
/// Returns list(z, building).
/proc/dq_firstload_building(seed)
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/datum/expedition_building/B = new
	B.furnish = FALSE
	B.entrances = 0
	var/turf/center = locate(round(world.maxx / 2), round(world.maxy / 2), z)
	B.build(center, 24, 24, seed)
	return list(z, B)

/// The building's digest, and then its digest with one entrance punched from a freshly seeded stream. list(layout rows, entrance rows).
/proc/dq_firstload_building_digests(seed, list/built)
	var/datum/expedition_building/B = built[2]
	var/list/layout = dq_firstload_digest(built[1], B.fx1 - 1, B.fy1 - 1, B.fx2 + 1, B.fy2 + 1)
	rand_seed(seed)
	B.entrances = 1
	B.place_entrances()
	return list(layout, dq_firstload_digest(built[1], B.fx1 - 1, B.fy1 - 1, B.fx2 + 1, B.fy2 + 1))

/// What a building must be however it was built, as a list of failures: rooms and corridors are open floor, every room is reachable from every
/// other, the footprint edge is wall (no entrance was punched), a door stands where a corridor breaches a room wall, and nothing outside a room or
/// corridor is open.
/proc/dq_firstload_building_invariants(z, datum/expedition_building/B)
	var/list/failures = list()
	var/list/open_tiles = list()
	for(var/list/r in B.rooms)
		for(var/x in r[1] to r[3])
			for(var/y in r[2] to r[4])
				open_tiles["[x],[y]"] = TRUE
	for(var/key in B.corridor_tiles)
		open_tiles[key] = TRUE
	for(var/x in B.fx1 to B.fx2)
		for(var/y in B.fy1 to B.fy2)
			var/turf/T = locate(x, y, z)
			if(open_tiles["[x],[y]"] && T.density)
				failures += "tile [x],[y] should be open"
			if(!open_tiles["[x],[y]"] && !T.density)
				failures += "tile [x],[y] should be wall"
			if((x == B.fx1 || x == B.fx2 || y == B.fy1 || y == B.fy2) && !T.density)
				failures += "footprint edge [x],[y] is open"
	for(var/list/coords in B.corridor_doors)
		if(!(locate(/obj/machinery/door) in locate(coords[1], coords[2], z)))
			failures += "no door at [coords[1]],[coords[2]]"
	// Every room centre reaches the first one over open tiles.
	var/list/seen = list()
	var/list/frontier = list(list(B.room_centers[1][1], B.room_centers[1][2]))
	seen["[B.room_centers[1][1]],[B.room_centers[1][2]]"] = TRUE
	while(length(frontier))
		var/list/at = frontier[length(frontier)]
		frontier.len--
		for(var/dir in list(NORTH, SOUTH, EAST, WEST))
			var/nx = at[1] + (dir & EAST ? 1 : 0) - (dir & WEST ? 1 : 0)
			var/ny = at[2] + (dir & NORTH ? 1 : 0) - (dir & SOUTH ? 1 : 0)
			if(seen["[nx],[ny]"] || !open_tiles["[nx],[ny]"])
				continue
			seen["[nx],[ny]"] = TRUE
			frontier += list(list(nx, ny))
	for(var/list/c in B.room_centers)
		if(!seen["[c[1]],[c[2]]"])
			failures += "room centre [c[1]],[c[2]] is cut off"
	return failures

/// What the BSP building generator costs today (fill the footprint with wall, then carve), and the digests of what it builds.
/datum/unit_test/dq_firstload_building_golden

/datum/unit_test/dq_firstload_building_golden/Run()
	test_driver_begin()
	var/list/mismatched = list()
	for(var/seed in FIRSTLOAD_SEEDS)
		var/changes_before = GLOB.turf_change_calls
		var/list/built = dq_firstload_building(seed)
		var/datum/expedition_building/B = built[1 + 1]
		var/layout_changes = GLOB.turf_change_calls - changes_before
		// Before the entrance is punched: the layout alone.
		var/list/broken = dq_firstload_building_invariants(built[1], B)
		TEST_ASSERT_EQUAL(length(broken), 0, "seed [seed] building layout: [broken.Join("; ")]")
		var/list/digests = dq_firstload_building_digests(seed, built)
		var/footprint = (B.fx2 - B.fx1 + 1) * (B.fy2 - B.fy1 + 1)
		// Final turfs only: the footprint is placed once (no wall-then-floor), so the layout costs one ChangeTurf per footprint tile.
		TEST_ASSERT_EQUAL(layout_changes, footprint, "seed [seed]: the building layout replaces each footprint tile exactly once")
		log_test("FIRSTLOAD building seed [seed]: footprint [footprint] turfs, [layout_changes] ChangeTurf calls for the layout, [GLOB.turf_change_calls - changes_before] with the entrance, [length(B.rooms)] rooms, layout hash [dq_firstload_hash(digests[1])] entrance hash [dq_firstload_hash(digests[2])]")
		// The same seed builds the same thing a second time on another z.
		var/list/again = dq_firstload_building_digests(seed, dq_firstload_building(seed))
		if(dq_firstload_hash(digests[1]) != GLOB.firstload_golden_building_layout["[seed]"])
			mismatched += "seed [seed] layout"
		if(dq_firstload_hash(digests[2]) != GLOB.firstload_golden_building_entrance["[seed]"])
			mismatched += "seed [seed] entrance"
		for(var/part in 1 to 2)
			TEST_ASSERT_EQUAL(dq_firstload_hash(again[part]), dq_firstload_hash(digests[part]), "seed [seed] builds the same building twice (part [part])")
	TEST_ASSERT_EQUAL(length(mismatched), 0, "the building is the one its seed always built: [mismatched.Join(", ")]")
	test_driver_end()

/// A furnished building keeps its furniture on room floors (never on a corridor), has an airlock where each corridor breaches a room wall, and
/// opens onto the ground outside through its entrances.
/datum/unit_test/dq_firstload_building_furnished

/datum/unit_test/dq_firstload_building_furnished/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/datum/expedition_building/B = new
	var/turf/center = locate(round(world.maxx / 2), round(world.maxy / 2), z)
	TEST_ASSERT(B.build(center, 24, 24, 11), "the building was built")
	var/furniture = 0
	for(var/key in B.corridor_tiles)
		var/list/coords = B.corridor_tiles[key]
		var/turf/T = locate(coords[1], coords[2], z)
		TEST_ASSERT(!T.density, "corridor tile [key] is open floor")
		TEST_ASSERT_NULL(locate(/obj/structure/closet) in T, "no closet stands in the corridor at [key]")
		TEST_ASSERT_NULL(locate(/obj/structure/table) in T, "no table stands in the corridor at [key]")
	for(var/list/r in B.rooms)
		for(var/x in r[1] to r[3])
			for(var/y in r[2] to r[4])
				var/turf/T = locate(x, y, z)
				TEST_ASSERT(!T.density, "room tile [x],[y] is open floor")
				if(locate(/obj/structure) in T)
					furniture++
	TEST_ASSERT(furniture > 0, "the rooms were furnished")
	for(var/list/coords in B.corridor_doors)
		TEST_ASSERT_NOTNULL(locate(/obj/machinery/door) in locate(coords[1], coords[2], z), "a door stands where the corridor breaches the room at [coords[1]],[coords[2]]")
	var/turf/edge_check = null
	var/open_edges = 0
	for(var/x in B.fx1 to B.fx2)
		for(var/y in list(B.fy1, B.fy2))
			edge_check = locate(x, y, z)
			if(!edge_check.density)
				open_edges++
	for(var/y in B.fy1 to B.fy2)
		for(var/x in list(B.fx1, B.fx2))
			edge_check = locate(x, y, z)
			if(!edge_check.density)
				open_edges++
	TEST_ASSERT(open_edges >= 1, "the building opens onto the ground outside through an entrance")
	test_driver_end()
