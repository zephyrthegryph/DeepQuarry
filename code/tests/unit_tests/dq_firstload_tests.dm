// First loads (gen/first-loads): what building a site after boot costs, as deterministic counts.

/// Seeds the equivalence and census tests build from.
#define FIRSTLOAD_SEEDS list(11, 222, 3333)

/// Digests of what the generators built from each seed before first loads placed final turfs (recorded from the fill-then-carve and
/// per-tile ChangeTurf paths): seed -> md5 of dq_firstload_digest(). Building: the layout with its doors, then with one entrance. Station: the
/// tiles and doors of a 96x96 plan. A generator change that moves one of these changes what players get from the same seed.
GLOBAL_LIST_INIT(firstload_golden_building_layout, list(
	"11" = "36dfe293222132c23b076dfa1664fbd7",
	"222" = "b4ef1d3f060c9aa3da0fbd65dae5463b",
	"3333" = "05990e82101c0d29e5643e39f6d4b0e1",
))
GLOBAL_LIST_INIT(firstload_golden_building_entrance, list(
	"11" = "2b647bd9887e7c866e1d7e5d1aa1f006",
	"222" = "d7ce35f497257932529963a4598befd5",
	"3333" = "877ae86b1d0d5d307271ef6282f82ce6",
))
GLOBAL_LIST_INIT(firstload_golden_station, list(
	"11" = "c406cffeb3eba580ebb487c3f9b442bd",
	"222" = "a7244987af443241c5555120a09dd3da",
	"3333" = "08bbae63d063ec77e0e729b73db59269",
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
	rand_seed(seed)
	var/datum/expedition_building/B = new
	B.furnish = FALSE
	B.entrances = 0
	var/turf/center = locate(round(world.maxx / 2), round(world.maxy / 2), z)
	B.build(center, 24, 24)
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
		TEST_ASSERT_EQUAL(dq_firstload_hash(digests[1]), GLOB.firstload_golden_building_layout["[seed]"], "seed [seed]: the building layout is the one the seed always built")
		TEST_ASSERT_EQUAL(dq_firstload_hash(digests[2]), GLOB.firstload_golden_building_entrance["[seed]"], "seed [seed]: the building with its entrance is the one the seed always built")
		for(var/part in 1 to 2)
			TEST_ASSERT_EQUAL(dq_firstload_hash(again[part]), dq_firstload_hash(digests[part]), "seed [seed] builds the same building twice (part [part])")
	test_driver_end()

/// The materializer up to the tile apply: the utility phase rejects every plan today (a vent against an APC terminal), and the tiles are what first
/// loads build. It stops after the turfs and doors are placed.
/datum/generated_station_materializer/firstload_probe

TYPE_TABLE(/datum/generated_station_materializer/firstload_probe, materialize_phases, list( \
		/datum/generated_station_materializer/proc/phase_tile_grid, \
		/datum/generated_station_materializer/proc/phase_tile_nodes, \
		/datum/generated_station_materializer/proc/phase_tile_circulation, \
		/datum/generated_station_materializer/proc/phase_tile_maintenance, \
		/datum/generated_station_materializer/proc/phase_tile_structure, \
		/datum/generated_station_materializer/proc/phase_tile_hull, \
		/datum/generated_station_materializer/proc/phase_tile_seal, \
		/datum/generated_station_materializer/proc/phase_modules, \
		/datum/generated_station_materializer/proc/phase_apply_turfs, \
		/datum/generated_station_materializer/proc/phase_apply_doors, \
	))

/// A fresh blank expedition z with the station planned from `seed` materialized on it. Returns list(z, spec, materialization, origin_x, origin_y).
/proc/dq_firstload_station(seed)
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_spec/spec = planner.plan(seed, 96, 96)
	if(!spec)
		return list(z, null, null, 0, 0)
	var/datum/generated_station_materializer/firstload_probe/materializer = new
	materializer.strict_room_contracts = FALSE
	var/origin_x = max(1, round((world.maxx - spec.grid_width) / 2))
	var/origin_y = max(1, round((world.maxy - spec.grid_height) / 2))
	rand_seed(seed)
	var/datum/generated_station_materialization/materialization = materializer.materialize(spec, z, origin_x, origin_y, null, TRUE)
	return list(z, spec, materialization, origin_x, origin_y)

/// What a generated station costs today: ChangeTurf calls against the turfs the station really ends with, and its digest.
/datum/unit_test/dq_firstload_station_golden

/datum/unit_test/dq_firstload_station_golden/Run()
	test_driver_begin()
	for(var/seed in FIRSTLOAD_SEEDS)
		var/changes_before = GLOB.turf_change_calls
		var/t0 = REALTIMEOFDAY
		var/list/built = dq_firstload_station(seed)
		var/datum/generated_station_spec/spec = built[2]
		TEST_ASSERT_NOTNULL(built[3], "seed [seed] materialized its station tiles ([spec ? "materialization failed" : "no plan"])")
		var/ox = built[4]
		var/oy = built[5]
		var/list/rows = dq_firstload_digest(built[1], ox, oy, ox + spec.grid_width - 1, oy + spec.grid_height - 1)
		var/non_space = 0
		for(var/row in rows)
			if(!findtext(row, ":/turf/space@"))
				non_space++
		log_test("FIRSTLOAD station seed [seed]: grid [spec.grid_width]x[spec.grid_height] = [spec.grid_width * spec.grid_height] tiles, [non_space] non-space, [GLOB.turf_change_calls - changes_before] ChangeTurf calls, [(REALTIMEOFDAY - t0) / 10]s, hash [dq_firstload_hash(rows)]")
		TEST_ASSERT_EQUAL(dq_firstload_hash(rows), GLOB.firstload_golden_station["[seed]"], "seed [seed]: the station tiles are the ones the seed always built")
	test_driver_end()
