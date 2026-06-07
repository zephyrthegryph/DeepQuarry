// Quarry persistence: snapshot/restore round-trip tests.
//
// These exercise the JSON serializer directly on a small fabricated
// patch, not the full 256x256 layer (a full layer takes ~30-60s to
// generate, way more than a unit test should burn). The patch is laid
// out on whatever z the test framework gives us, mutated, snapshotted,
// wiped, restored, and verified to round-trip the mutations.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#define QUARRY_TEST_PATCH_SIZE 4

// --- helper: walk a small block and force every turf to the
// quarry-cave baseline so the snapshot's "is_baseline" predicate works
// against a known starting state.
/proc/_dq_quarry_reset_patch(z, x0, y0, size)
	for(var/dx in 0 to size - 1)
		for(var/dy in 0 to size - 1)
			var/turf/T = locate(x0 + dx, y0 + dy, z)
			if(!isturf(T))
				continue
			// Strip movables first so the post-snapshot wipe later has
			// a clean baseline to compare against.
			for(var/atom/movable/AM in T)
				if(ismob(AM))
					continue
				qdel(AM)
			T.ChangeTurf(/turf/simulated/mineral/cave/quarry)


// Returns a turf we can mutate for the test. The DQ test map doesn't
// place a /obj/effect/landmark/unit_test_bottom_left, so the
// `run_loc_floor_bottom_left` helper is null. Pick the first simulated
// floor on z=1 as a workable substitute.
/datum/unit_test/proc/_dq_quarry_test_turf()
	for(var/turf/simulated/T in block(locate(1, 1, 1), locate(world.maxx, world.maxy, 1)))
		return T
	return null


// --- snapshot includes a turf-type diff -------------------------------

/datum/unit_test/dq_quarry_snapshot_tile_emits_turf_diff

/datum/unit_test/dq_quarry_snapshot_tile_emits_turf_diff/Run()
	var/turf/T = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(T, "no test turf available on z=1")
	// Force baseline, then swap to a floor to create a diff.
	T = T.ChangeTurf(/turf/simulated/mineral/cave/quarry)
	TEST_ASSERT_NOTNULL(T, "couldn't anchor on the test turf")
	var/turf/floor_turf = T.ChangeTurf(/turf/simulated/floor)
	TEST_ASSERT_NOTNULL(floor_turf, "ChangeTurf to floor failed")
	var/list/tile_doc = _quarry_serialize_tile(floor_turf)
	TEST_ASSERT_NOTNULL(tile_doc, "expected a tile doc for a non-baseline turf, got null")
	var/turf_key = "turf"
	var/list/turf_serial = tile_doc[turf_key]
	TEST_ASSERT(islist(turf_serial), "expected tile_doc\[\"turf\"\] to be a list")
	TEST_ASSERT(turf_serial["type"] == "/turf/simulated/floor", "expected turf type /turf/simulated/floor in tile doc, got [turf_serial["type"]]")


// --- baseline turf with no movables is skipped ------------------------

/datum/unit_test/dq_quarry_snapshot_tile_skips_baseline

/datum/unit_test/dq_quarry_snapshot_tile_skips_baseline/Run()
	var/turf/T = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(T, "no test turf available on z=1")
	T = T.ChangeTurf(/turf/simulated/mineral/cave/quarry)
	// Strip any movables that might have been on the test floor.
	for(var/atom/movable/AM in T)
		if(ismob(AM))
			continue
		qdel(AM)
	var/list/tile_doc = _quarry_serialize_tile(T)
	TEST_ASSERT_NULL(tile_doc, "expected null for a baseline-quarry-wall tile with no movables, got [tile_doc]")


// --- baseline turf WITH movables emits a tile doc ---------------------

/datum/unit_test/dq_quarry_snapshot_tile_emits_movables

/datum/unit_test/dq_quarry_snapshot_tile_emits_movables/Run()
	var/turf/T = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(T, "no test turf available on z=1")
	T = T.ChangeTurf(/turf/simulated/mineral/cave/quarry)
	for(var/atom/movable/AM in T)
		if(ismob(AM))
			continue
		qdel(AM)
	// Drop a wrench on the tile so the serializer has something to capture.
	var/obj/item/tool/wrench/W = new(T)
	TEST_ASSERT_NOTNULL(W, "couldn't spawn test wrench")
	var/list/tile_doc = _quarry_serialize_tile(T)
	TEST_ASSERT_NOTNULL(tile_doc, "expected a tile doc with movables present")
	TEST_ASSERT(islist(tile_doc["contents"]), "expected contents list, got [tile_doc["contents"]]")
	TEST_ASSERT(length(tile_doc["contents"]) >= 1, "expected at least one serialized atom in contents")


// --- write -> read -> apply round-trip --------------------------------
//
// Build a tiny doc by hand, write it to a temp path, read it back via
// the standard json_decode + file2text path, and verify list_to_object
// reconstructs the atom on the target turf.

/datum/unit_test/dq_quarry_snapshot_roundtrip_writes_and_reads

/datum/unit_test/dq_quarry_snapshot_roundtrip_writes_and_reads/Run()
	var/turf/T = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(T, "no test turf available on z=1")
	T = T.ChangeTurf(/turf/simulated/mineral/cave/quarry)
	for(var/atom/movable/AM in T)
		if(ismob(AM))
			continue
		qdel(AM)

	// Drop two items so we can verify multi-atom restore.
	var/obj/item/tool/wrench/W = new(T)
	W.name = "marked wrench"
	var/obj/item/tool/screwdriver/SD = new(T)
	SD.name = "marked screwdriver"

	// Build the doc the same way snapshot_layer would for this single tile.
	var/list/tile_doc = _quarry_serialize_tile(T)
	TEST_ASSERT_NOTNULL(tile_doc, "tile doc was null")
	var/list/doc = list("version" = 1, "depth" = 999, "tiles" = list(tile_doc))
	var/path = "data/quarry_snapshots/test_roundtrip.json"
	if(fexists(path))
		fdel(path)
	if(!fexists("data/quarry_snapshots/"))
		text2file("", "data/quarry_snapshots/.keep")
	text2file(json_encode(doc), path)
	TEST_ASSERT(fexists(path), "snapshot file [path] was not written")

	// Wipe the tile.
	qdel(W)
	qdel(SD)
	for(var/atom/movable/AM in T)
		if(ismob(AM))
			continue
		qdel(AM)

	// Read the doc and reapply.
	var/list/read_doc = json_decode(file2text(path))
	TEST_ASSERT(islist(read_doc), "read doc wasn't a list")
	TEST_ASSERT(islist(read_doc["tiles"]), "read doc had no tiles list")
	for(var/list/saved_tile in read_doc["tiles"])
		var/list/saved_contents = saved_tile["contents"]
		if(!islist(saved_contents))
			continue
		for(var/list/atom_data in saved_contents)
			list_to_object(atom_data, T)

	// Verify the two items came back, with their names intact.
	var/found_wrench = FALSE
	var/found_screwdriver = FALSE
	for(var/atom/movable/AM in T)
		if(istype(AM, /obj/item/tool/wrench) && AM.name == "marked wrench")
			found_wrench = TRUE
		else if(istype(AM, /obj/item/tool/screwdriver) && AM.name == "marked screwdriver")
			found_screwdriver = TRUE
	TEST_ASSERT(found_wrench, "wrench did not survive round-trip")
	TEST_ASSERT(found_screwdriver, "screwdriver did not survive round-trip")

	// Cleanup.
	fdel(path)


// --- skip_in_snapshot excludes mobs and landmarks ---------------------

/datum/unit_test/dq_quarry_snapshot_skips_mobs_and_landmarks

/datum/unit_test/dq_quarry_snapshot_skips_mobs_and_landmarks/Run()
	var/turf/T = _dq_quarry_test_turf()
	TEST_ASSERT_NOTNULL(T, "no test turf available on z=1")
	T = T.ChangeTurf(/turf/simulated/mineral/cave/quarry)
	for(var/atom/movable/AM in T)
		if(ismob(AM))
			continue
		qdel(AM)

	// Drop one of each interesting atom kind on the tile.
	var/obj/item/tool/wrench/W = new(T)
	var/obj/effect/landmark/LM = new(T)
	var/atom/movable/lighting_overlay/LO = new(T)

	var/list/tile_doc = _quarry_serialize_tile(T)
	TEST_ASSERT_NOTNULL(tile_doc, "tile doc was null")
	var/list/contents = tile_doc["contents"]
	TEST_ASSERT(islist(contents), "contents wasn't a list, got [contents]")
	// Only the wrench should be in there; the landmark and lighting
	// overlay should have been filtered by _quarry_skip_in_snapshot.
	TEST_ASSERT(length(contents) == 1, "expected exactly one serialized atom (wrench), got [length(contents)]")
	var/list/wrench_data = contents[1]
	TEST_ASSERT(wrench_data["type"] == "/obj/item/tool/wrench", "expected wrench type, got [wrench_data["type"]]")

	qdel(W)
	qdel(LM)
	qdel(LO)


// --- has_snapshot returns false when file doesn't exist ---------------

/datum/unit_test/dq_quarry_has_snapshot_negative

/datum/unit_test/dq_quarry_has_snapshot_negative/Run()
	var/path = "data/quarry_snapshots/9999.json"
	if(fexists(path))
		fdel(path)
	TEST_ASSERT(!SSquarry.has_snapshot(9999), "expected has_snapshot(9999) to be FALSE when file is missing")


// --- has_snapshot returns true after a write --------------------------

/datum/unit_test/dq_quarry_has_snapshot_positive

/datum/unit_test/dq_quarry_has_snapshot_positive/Run()
	var/path = "data/quarry_snapshots/9998.json"
	if(!fexists("data/quarry_snapshots/"))
		text2file("", "data/quarry_snapshots/.keep")
	text2file("{}", path)
	TEST_ASSERT(SSquarry.has_snapshot(9998), "expected has_snapshot(9998) to be TRUE after writing the file")
	fdel(path)


// --- benchmark: snapshot on a full 256x256 layer ----------------------
//
// Allocates a fresh z via the quarry_layer template, snapshots it,
// logs the phase timings, and fails if any phase exceeds its budget.
// The thresholds are generous on purpose — this is a regression
// guard against "snapshot suddenly takes 2 minutes", not a perf bar.
//
// What this is and isn't measuring:
//   - The substrate is a uniform field of /turf/simulated/mineral/cave/quarry.
//     Every tile is "baseline" in the snapshot's eyes, so the emitted
//     diff is empty. This measures the cost of WALKING the grid plus
//     the cost of the per-tile baseline check, not the cost of
//     serializing real content.
//   - This means the test is a LOWER bound on snapshot time. A real
//     played-out layer with mined-out walls + dropped loot will take
//     longer because each non-baseline tile adds a serialize() call
//     and a list entry.

/datum/unit_test/dq_quarry_bench_snapshot_empty_layer

/datum/unit_test/dq_quarry_bench_snapshot_empty_layer/Run()
	// Allocate a fresh z via the same map_template the real code uses.
	var/datum/map_template/quarry_layer/template = new
	TEST_ASSERT(template.load_new_z(), "couldn't load_new_z for benchmark")
	var/bench_z = world.maxz

	// Snapshot, time it, log phase + total.
	var/depth = 9990
	var/t0 = world.timeofday
	var/ok = SSquarry.snapshot_layer(depth, bench_z)
	var/t1 = world.timeofday
	var/elapsed_ds = t1 - t0  // deciseconds
	log_game("BENCH: snapshot_layer empty 256x256 z took [elapsed_ds / 10]s")
	TEST_ASSERT(ok, "snapshot_layer returned FALSE on benchmark z")
	// Cleanup the snapshot file so other tests don't see it.
	if(SSquarry.has_snapshot(depth))
		fdel("data/quarry_snapshots/[depth].json")
	// Sanity bound: a clean layer should snapshot in well under a minute
	// even on a slow CI host. Anything more is a regression.
	TEST_ASSERT(elapsed_ds < 600, "snapshot_layer took [elapsed_ds / 10]s, expected under 60s")


// --- benchmark: snapshot + wipe on a populated 256x256 layer ----------
//
// More realistic: spawn a handful of items on a fresh z so the
// snapshot has actual content to serialize, then time both the
// snapshot and the wipe. Wipe is the path that was taking 2+ minutes
// in production. Fails if either exceeds budget.

/datum/unit_test/dq_quarry_bench_snapshot_and_wipe_populated

/datum/unit_test/dq_quarry_bench_snapshot_and_wipe_populated/Run()
	var/datum/map_template/quarry_layer/template = new
	TEST_ASSERT(template.load_new_z(), "couldn't load_new_z")
	var/bench_z = world.maxz

	// Sprinkle some content: convert ~5% of tiles to floor and drop
	// an ore on each. Spread across the whole map so the wipe walks
	// a representative set.
	var/dropped = 0
	for(var/x in 1 to QUARRY_LAYER_SIZE step 5)
		for(var/y in 1 to QUARRY_LAYER_SIZE step 5)
			var/turf/T = locate(x, y, bench_z)
			if(!isturf(T))
				continue
			T = T.ChangeTurf(/turf/simulated/floor)
			new /obj/item/ore/iron(T)
			dropped++
	log_game("BENCH: populated [dropped] tiles with floor+ore")

	// Snapshot it.
	var/depth = 9991
	var/t0 = world.timeofday
	var/ok = SSquarry.snapshot_layer(depth, bench_z)
	var/t1 = world.timeofday
	var/snap_ds = t1 - t0
	log_game("BENCH: snapshot_layer 5% populated 256x256 took [snap_ds / 10]s")
	TEST_ASSERT(ok, "snapshot_layer returned FALSE")
	TEST_ASSERT(snap_ds < 900, "snapshot_layer took [snap_ds / 10]s on 5% populated layer; expected under 90s")

	// Cleanup snapshot file.
	if(SSquarry.has_snapshot(depth))
		fdel("data/quarry_snapshots/[depth].json")

	// Wipe pass: open-code the same loop that _finish_unload_layer
	// runs, so we measure just the destructive walk in isolation.
	// Mirrors the production wipe — qdel movables, skip empty tiles,
	// no ChangeTurf (the orphan z is abandoned and turfs cost nothing
	// once movables are gone).
	var/t2 = world.timeofday
	var/row_batch = 0
	for(var/y in 1 to QUARRY_LAYER_SIZE)
		for(var/x in 1 to QUARRY_LAYER_SIZE)
			var/turf/T = locate(x, y, bench_z)
			if(!isturf(T) || !length(T.contents))
				continue
			for(var/atom/movable/AM in T)
				if(istype(AM, /mob/observer))
					continue
				qdel(AM)
		row_batch++
		if(row_batch >= 4)
			row_batch = 0
			CHECK_TICK_HIGH_PRIORITY
	var/t3 = world.timeofday
	var/wipe_ds = t3 - t2
	log_game("BENCH: wipe 5% populated 256x256 took [wipe_ds / 10]s")
	// Should now be dominated by the empty-tile skip walk only.
	TEST_ASSERT(wipe_ds < 100, "wipe took [wipe_ds / 10]s on 5% populated layer; expected under 10s")

// --- benchmark: full lifecycle (generate / serialize / deserialize / clear)
//
// Times all four phases on the same depth so the numbers are
// comparable. Generates a real quarry layer via SSquarry, sprinkles
// player-side modifications (a few dropped ores), then runs the full
// snapshot -> wipe -> restore round-trip. Logs each phase.
//
// What "generate" means here: the FULL SSquarry.generate_layer call,
// which loads the substrate template, runs the cave generator, carves
// the elevator room, places ores/decorations, and spawns mobs from the
// config. That's the user-visible "first descent" cost.

/datum/unit_test/dq_quarry_bench_full_lifecycle

/datum/unit_test/dq_quarry_bench_full_lifecycle/Run()
	// Depth must be in [1, 25] so select_config picks a real biome.
	// Use 1 (shallows: cheapest tier, fewest mobs/decos — gives the
	// floor for the lifecycle cost; deeper tiers will be heavier).
	var/depth = 1
	// Cleanup leftover snapshot, if any.
	var/path = "data/quarry_snapshots/[depth].json"
	if(fexists(path))
		fdel(path)

	// --- Phase 1: generate ---------------------------------------------
	//
	// Calls SSquarry.generate_layer which does cave-gen + elevator carve
	// + ore placement + decoration scatter + mob spawn for a depth-1
	// config. This is what the player waits for on a fresh descent.
	var/t0 = world.timeofday
	var/datum/quarry_layer/L = SSquarry.generate_layer(depth)
	var/t1 = world.timeofday
	var/gen_ds = t1 - t0
	log_game("BENCH: generate_layer (depth [depth]) took [gen_ds / 10]s")
	TEST_ASSERT_NOTNULL(L, "generate_layer returned null")
	TEST_ASSERT(L.loaded, "generated layer not marked loaded")
	var/bench_z = L.z

	// Mark the layer "unloading" so SSquarry's periodic fire() doesn't
	// notice it's empty and try to unload it from under us. Don't add
	// to layers[] yet either — we'll register it just before snapshot.
	L.unloading = TRUE

	// Add some player-side modifications: drop a stack of ores on
	// random floor tiles. The generator already populated the layer
	// with ores and mobs and decorations; this just adds a layer of
	// "stuff the player would have left behind".
	var/dropped = 0
	for(var/i in 1 to 200)
		var/x = rand(1, QUARRY_LAYER_SIZE)
		var/y = rand(1, QUARRY_LAYER_SIZE)
		var/turf/T = locate(x, y, bench_z)
		if(!isturf(T) || T.density)
			continue
		new /obj/item/ore/iron(T)
		dropped++
	log_game("BENCH: dropped [dropped] items on the generated layer")

	// --- Phase 2: serialize (snapshot) ---------------------------------
	var/t2 = world.timeofday
	var/ok_snap = SSquarry.snapshot_layer(depth, bench_z)
	var/t3 = world.timeofday
	var/snap_ds = t3 - t2
	log_game("BENCH: snapshot_layer (depth [depth]) took [snap_ds / 10]s")
	TEST_ASSERT(ok_snap, "snapshot_layer returned FALSE")
	TEST_ASSERT(fexists(path), "snapshot file not written")
	// Log the file size so we have a sense of the on-disk payload.
	var/snap_bytes = length(file2text(path))
	log_game("BENCH: snapshot file size: [snap_bytes] bytes")

	// --- Phase 3: clear (wipe) -----------------------------------------
	//
	// Mirrors _finish_unload_layer's wipe loop — qdel movables, skip
	// empty tiles. The orphaned z stays loaded in BYOND but consumes
	// almost nothing once movables are gone.
	var/t4 = world.timeofday
	var/row_batch = 0
	for(var/y in 1 to QUARRY_LAYER_SIZE)
		for(var/x in 1 to QUARRY_LAYER_SIZE)
			var/turf/T = locate(x, y, bench_z)
			if(!isturf(T) || !length(T.contents))
				continue
			for(var/atom/movable/AM in T)
				if(istype(AM, /mob/observer))
					continue
				qdel(AM)
		row_batch++
		if(row_batch >= 4)
			row_batch = 0
			CHECK_TICK_HIGH_PRIORITY
	var/t5 = world.timeofday
	var/wipe_ds = t5 - t4
	log_game("BENCH: clear (wipe) (depth [depth]) took [wipe_ds / 10]s")

	// Drop the orphaned layer record so the restore path can rebuild.
	SSquarry.layers -= "[depth]"
	L.loaded = FALSE
	L.unloading = FALSE

	// --- Phase 4: deserialize (restore) --------------------------------
	//
	// restore_layer rebuilds the substrate via a fresh generate_layer
	// call AND overlays the snapshot's tile diffs on top. The
	// generate_layer cost is included here — that's what production
	// pays on a snapshot restore.
	var/t6 = world.timeofday
	var/datum/quarry_layer/restored = SSquarry.restore_layer(depth)
	var/t7 = world.timeofday
	var/restore_ds = t7 - t6
	log_game("BENCH: restore_layer (depth [depth]) took [restore_ds / 10]s")
	TEST_ASSERT_NOTNULL(restored, "restore_layer returned null")
	TEST_ASSERT(restored.loaded, "restored layer not marked loaded")

	// Cleanup: the restored layer is on a new z; record it so a
	// subsequent test run starts clean. Don't bother fully tearing it
	// down — the test process exits after this.
	if(fexists(path))
		fdel(path)

	// Sanity bounds (generous so a slow CI host doesn't trip them
	// unnecessarily — these are regression guards, not perf bars).
	TEST_ASSERT(gen_ds < 600,    "generate_layer took [gen_ds / 10]s, expected under 60s")
	TEST_ASSERT(snap_ds < 100,   "snapshot_layer took [snap_ds / 10]s, expected under 10s")
	TEST_ASSERT(wipe_ds < 100,   "clear took [wipe_ds / 10]s, expected under 10s")
	TEST_ASSERT(restore_ds < 600,"restore_layer took [restore_ds / 10]s, expected under 60s")

	log_game("BENCH: SUMMARY depth=[depth] generate=[gen_ds / 10]s snapshot=[snap_ds / 10]s clear=[wipe_ds / 10]s restore=[restore_ds / 10]s file=[snap_bytes]B")


// --- equality: state after deserialize equals state before serialize
//
// Generates a layer, sprinkles player-side modifications on top, takes
// a "fingerprint" of every tile's state (turf type + non-mob contents),
// snapshots, allocates a separate replacement layer via restore_layer
// from that snapshot, fingerprints again, and asserts the two
// fingerprints match exactly.
//
// Mobs are deliberately excluded from both fingerprints — they don't
// round-trip and the restore path re-spawns them from config, so
// requiring identity would be wrong.

/datum/unit_test/dq_quarry_serialize_deserialize_equals_original

/datum/unit_test/dq_quarry_serialize_deserialize_equals_original/Run()
	// Must be in [1, 25] so select_config picks a real biome.
	var/depth = 2
	var/path = "data/quarry_snapshots/[depth].json"
	if(fexists(path))
		fdel(path)

	var/datum/quarry_layer/L = SSquarry.generate_layer(depth)
	TEST_ASSERT_NOTNULL(L, "generate_layer returned null")
	// Mark unloading so periodic fire() doesn't unload it mid-test.
	L.unloading = TRUE

	// Sprinkle player-side modifications: drop ores on random non-dense
	// tiles. Adds non-baseline content the snapshot has to capture.
	for(var/i in 1 to 50)
		var/x = rand(1, QUARRY_LAYER_SIZE)
		var/y = rand(1, QUARRY_LAYER_SIZE)
		var/turf/T = locate(x, y, L.z)
		if(!isturf(T) || T.density)
			continue
		new /obj/item/ore/iron(T)

	var/list/before = _dq_quarry_fingerprint_layer(L.z)

	TEST_ASSERT(SSquarry.snapshot_layer(depth, L.z), "snapshot_layer returned FALSE")
	TEST_ASSERT(fexists(path), "snapshot file not written")

	// Drop the original layer record. Restore allocates a fresh z.
	SSquarry.layers -= "[depth]"
	L.loaded = FALSE

	var/datum/quarry_layer/restored = SSquarry.restore_layer(depth)
	TEST_ASSERT_NOTNULL(restored, "restore_layer returned null")
	TEST_ASSERT(restored.loaded, "restored layer not marked loaded")
	TEST_ASSERT(restored.z != L.z, "restored z must be different from original")

	var/list/after = _dq_quarry_fingerprint_layer(restored.z)

	// Compare. Build human-readable diffs for the first few divergences
	// so a failure points at exactly what didn't round-trip.
	var/list/mismatches = list()
	for(var/key in before)
		var/before_str = before[key]
		var/after_str = after[key]
		if(before_str != after_str)
			mismatches += "[key]: BEFORE=\"[before_str]\" AFTER=\"[after_str]\""
		if(length(mismatches) >= 5)
			break
	for(var/key in after)
		if(!(key in before) && length(mismatches) < 5)
			mismatches += "[key] appeared only AFTER: \"[after[key]]\""

	if(length(mismatches))
		TEST_FAIL("snapshot/restore not equal (before=[length(before)] tiles, after=[length(after)] tiles); first mismatches: [jointext(mismatches, " | ")]")

	if(fexists(path))
		fdel(path)


// Fingerprint a quarry z: for every tile that diverges from the
// baseline /turf/simulated/mineral/cave/quarry wall OR has any non-mob
// contents, emit "x,y" -> "turf_type|contents_signature" where the
// contents signature is the sorted concatenation of each movable's
// type. Items use type only because their per-instance vars get
// serialized via /atom/serialize and round-trip is asserted by the
// list_to_object call in restore — type identity is the strict
// invariant.
//
// Mobs are excluded. The snapshot intentionally drops them and the
// restore path re-spawns them from config, so requiring identity
// would be wrong.
/proc/_dq_quarry_fingerprint_layer(z)
	var/list/out = list()
	for(var/x in 1 to QUARRY_LAYER_SIZE)
		for(var/y in 1 to QUARRY_LAYER_SIZE)
			var/turf/T = locate(x, y, z)
			if(!isturf(T))
				continue
			var/list/content_types = list()
			for(var/atom/movable/AM in T)
				if(ismob(AM))
					continue
				if(istype(AM, /obj/effect/landmark))
					continue
				if(istype(AM, /atom/movable/lighting_overlay))
					continue
				content_types += "[AM.type]"
			content_types = sortList(content_types)
			var/turf_type_path = "[T.type]"
			var/is_baseline = (turf_type_path == "/turf/simulated/mineral/cave/quarry")
			if(is_baseline && !length(content_types))
				continue
			out["[x],[y]"] = "[turf_type_path]|[jointext(content_types, ",")]"
	return out


#undef QUARRY_TEST_PATCH_SIZE

#endif
