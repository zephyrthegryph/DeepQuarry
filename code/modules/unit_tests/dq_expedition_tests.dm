// DQ expedition generator tests.
// Exercises the on-demand z-level generator (SSexpedition) end-to-end. This is
// a genuine integration test: generate_site() allocates a real z-level, runs
// the verdigris cave-gen FFI to carve it, and scatters content. If verdigris
// failed to load, the carve would no-op (every cell stays a dense wall),
// populate_site() would find no walkable floor, and generate_site() returns
// null — so a non-null site with a walkable landing turf proves the whole
// chain (z-allocation + Rust cave gen + content scatter) works.

// Directly exercises the verdigris cave-gen FFI the expedition carver depends on.
// Cheap (one small grid, no z-allocation) so it runs even under slow emulation.
// If verdigris isn't loaded/working, verdigris_generate_automata() returns null
// or a degenerate uniform grid.
/datum/unit_test/dq_verdigris_cavegen_ffi

/datum/unit_test/dq_verdigris_cavegen_ffi/Run()
	var/list/grid = verdigris_generate_automata(48, 48, 4, 45)
	TEST_ASSERT_NOTNULL(grid, "verdigris_generate_automata() returned null — cave-gen FFI not loaded/working")
	TEST_ASSERT_EQUAL(length(grid), 48 * 48, "automata grid has [length(grid)] cells, expected [48 * 48]")
	// A real carve yields a MIX of cell states; a uniform grid means the FFI
	// produced nothing meaningful. Cell values are numbers, so key the set by
	// their string form — list[number] would be positional indexing, not a set.
	var/list/distinct = list()
	for(var/cell in grid)
		distinct["[cell]"] = TRUE
	TEST_ASSERT(length(distinct) >= 2, "automata grid is uniform (states: [json_encode(distinct)]) — no cave structure carved")
	log_test("verdigris cave-gen FFI OK: [length(grid)] cells across [length(distinct)] distinct states")


/datum/unit_test/dq_expedition_generates_site

/datum/unit_test/dq_expedition_generates_site/Run()
	TEST_ASSERT_NOTNULL(SSexpedition, "SSexpedition is null — subsystem failed to initialize")

	var/pre_maxz = world.maxz
	var/datum/expedition_site/site = SSexpedition.generate_site(null, EXP_DIFF_MED)

	TEST_ASSERT_NOTNULL(site, "generate_site() returned null — z-alloc, verdigris carve, or content scatter failed")
	TEST_ASSERT(world.maxz > pre_maxz, "world.maxz did not grow: [pre_maxz] -> [world.maxz]; load_new_z() allocated nothing")
	TEST_ASSERT_EQUAL(site.z_level, world.maxz, "site z-level [site.z_level] is not the newly-allocated top z [world.maxz]")

	// A walkable landing turf only exists if the carver actually opened floors.
	TEST_ASSERT_NOTNULL(site.landing, "site has no landing turf — carve produced no walkable floor (verdigris likely not loaded)")
	TEST_ASSERT(!site.landing.density, "landing turf is dense — not actually walkable")
	TEST_ASSERT_EQUAL(site.landing.z, site.z_level, "landing turf z [site.landing.z] != site z [site.z_level]")

	// The site must be registered for later lookup.
	TEST_ASSERT(SSexpedition.sites["[site.z_level]"] == site, "site was not registered in SSexpedition.sites")

	// Count carved floors as a sanity signal on the cave gen.
	var/floor_count = 0
	for(var/turf/simulated/mineral/T as anything in block(locate(1, 1, site.z_level), locate(world.maxx, world.maxy, site.z_level)))
		if(!T.density)
			floor_count++
	TEST_ASSERT(floor_count > 50, "only [floor_count] walkable floors on the generated site — cave gen produced almost no open space")
	log_test("Expedition site generated on z[site.z_level] with [floor_count] walkable floor turfs.")
