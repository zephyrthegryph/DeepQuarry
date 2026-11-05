// First loads (gen/first-loads): what building a site after boot costs, as deterministic counts.

/// Seeds the equivalence and census tests build from.
#define FIRSTLOAD_SEEDS list(11, 222, 3333)

/// Digests of what the generators built from each seed before first loads placed final turfs (recorded from the fill-then-carve and
/// per-tile ChangeTurf paths; the building plan is drawn from the seed at the partition, build(seed =)): seed -> md5 of dq_firstload_digest(). Building: the layout with its doors, then with one entrance. A generator change that moves one of these changes what players get from the same seed.
GLOBAL_LIST_INIT(firstload_golden_building_layout, list(
	"11" = "01fb2c90c35b5fefdc4e82e81e55d4f9",
	"222" = "635136a4b80c95d65a427010b05775e2",
	"3333" = "0a348acc6c524aabb991552485d3c87f",
))
GLOBAL_LIST_INIT(firstload_golden_building_entrance, list(
	"11" = "583a9550b9776196e7ed98d5fdee3af5",
	"222" = "267a5ebca0f3a0dea1e2c0f092c9149c",
	"3333" = "57cd866e74d552d0e07ce2779b155ed2",
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

/// A text digest of a rectangle of `z`: each turf's type and area, and the sorted types of what stands on it.
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
			rows += "[x],[y]:[T.type]@[T.loc.type]=[stuff.Join("+")]"
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
		var/list/digests = dq_firstload_building_digests(seed, built)
		var/footprint = (B.fx2 - B.fx1 + 1) * (B.fy2 - B.fy1 + 1)
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
