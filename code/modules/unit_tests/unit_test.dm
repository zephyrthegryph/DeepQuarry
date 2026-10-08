/*

Usage:
Override /Run() to run your test code

Call TEST_FAIL() to fail the test (You should specify a reason)

You may use /New() and /Destroy() for setup/teardown respectively

You can use the run_loc_floor_bottom_left and run_loc_floor_top_right to get turfs for testing

*/

GLOBAL_DATUM(current_test, /datum/unit_test)
GLOBAL_VAR_INIT(failed_any_test, FALSE)
/// The E0 proofs' tally for the run (TEST_TIER_E0, doc/testing.md "The E0 proofs"): green, failed only because an engine is missing, failed otherwise.
GLOBAL_VAR_INIT(e0_proofs_passed, 0)
GLOBAL_VAR_INIT(e0_proofs_pending, 0)
GLOBAL_VAR_INIT(e0_proofs_failed, 0)
/// When unit testing, all logs sent to log_mapping are stored here and retrieved in log_mapping unit test.
GLOBAL_LIST_EMPTY(unit_test_mapping_logs)
/// Global assoc list of required mapping items, [item typepath] to [required item datum].
GLOBAL_LIST_EMPTY(required_map_items)

/// A list of every test that is currently focused.
/// Use the PERFORM_ALL_TESTS macro instead.
GLOBAL_VAR_INIT(focused_tests, focused_tests())

/// How many isolated test blocks to keep in the pool. Tests run strictly
/// sequentially (RunUnitTests() calls each test's New()/Run()/restore_atmos()/
/// Destroy() in a plain for loop before starting the next), so one block would
/// be enough in theory -- but a test's Destroy() may still be draining async
/// leftovers (a delayed callback, an expedition teardown_z wait) when the next
/// test's New() runs, so a small pool lets us round-robin instead of forcing
/// every test to block on the previous test's straggling cleanup.
#define UNIT_TEST_BLOCK_POOL_SIZE 8
/// The blocks a focused run starts with; it grows up to UNIT_TEST_BLOCK_POOL_SIZE when a test waits for one.
#define UNIT_TEST_BLOCK_POOL_FOCUSED 2

/// Area of maps/templates/unit_tests.dmm. The template must only use types
/// that exist: the map parser silently drops unknown paths, which left every
/// cell with an empty model (build_coordinate() runtimes, no landmarks, an
/// empty block pool, and every test waiting 60 s for a block).
/area/unit_test
	name = "Unit Test Room"
	requires_power = FALSE

/// One isolated, walled-off copy of maps/templates/unit_tests.dmm on its own
/// z-level. Checked out to exactly one running unit test at a time so tests no
/// longer share a single global floor turf (the historic source of most
/// intermittent unit-test failures: leaked hotspots, gas, and temperature from
/// one test bleeding into the next).
/datum/unit_test_block
	/// Bottom-left floor turf of this block, mirrors run_loc_floor_bottom_left.
	var/turf/bottom_left
	/// Top-right floor turf of this block, mirrors run_loc_floor_top_right.
	var/turf/top_right
	/// The z-level this block's copy of the template was loaded onto.
	var/z
	/// TRUE while a test currently owns this block.
	var/in_use = FALSE

/// The pool of isolated test blocks. Built lazily on the first test that needs
/// one, so non-test worlds never pay for it.
GLOBAL_LIST_EMPTY(unit_test_block_pool)
/// TRUE once the pool has been built (or an attempt was made to build it).
GLOBAL_VAR_INIT(unit_test_block_pool_ready, FALSE)
/// TRUE while acquire_unit_test_block() adds a block to a focused run's pool.
GLOBAL_VAR_INIT(unit_test_block_pool_growing, FALSE)

/// Loads UNIT_TEST_BLOCK_POOL_SIZE independent copies of the unit-test room
/// template, each on its own z-level, and records their corner turfs. Safe to
/// call more than once -- only the first call does anything.
/proc/ensure_unit_test_block_pool()
	if(GLOB.unit_test_block_pool_ready)
		return
	// Set this before load_new_z() (which yields) so a re-entrant call made
	// while we're still loading the first copy doesn't start a second build.
	GLOB.unit_test_block_pool_ready = TRUE

	// load_new_z() -> initTemplateBounds() is a deliberate no-op while
	// SSatoms.initialized is still FALSE (code/modules/maps/map_template.dm):
	// during the main boot's own atom-init pass it assumes that pass will
	// pick up anything newly loaded, instead of double-initializing. The
	// unit-test suite can start running its first test (which builds this
	// pool from New()) before SSatoms actually finishes that pass, so
	// initTemplateBounds() silently skips calling SSatoms.InitializeAtoms()
	// on every copy's atoms -- landmarks (and everything else) never run
	// Initialize() and are never found below. This raced: it depended on
	// how far the main boot sweep had gotten by the time we checked, which
	// varies with machine load. Wait for real SSatoms completion first so
	// initTemplateBounds() always takes its normal, synchronous path.
	while(!SSatoms.initialized)
		sleep(1)

	// A focused run starts with UNIT_TEST_BLOCK_POOL_FOCUSED blocks and grows on demand (acquire_unit_test_block()):
	// each block is a new z-level, about 0.65 s to allocate, and a handful of tests rarely holds more than one.
	var/initial_size = unit_test_is_focused_run() ? UNIT_TEST_BLOCK_POOL_FOCUSED : UNIT_TEST_BLOCK_POOL_SIZE
	for(var/i in 1 to initial_size)
		unit_test_block_load(i)

	if(!length(GLOB.unit_test_block_pool))
		CRASH("ensure_unit_test_block_pool: failed to load any isolated test blocks.")

/// Loads one more isolated block (copy #i) into the pool; logs and adds nothing when every attempt fails.
/proc/unit_test_block_load(i)
	var/datum/unit_test_block/block
	// load_new_z()'s underlying map load (parsed_map/build_coordinate)
	// intermittently places nothing at all -- every turf on the new z
	// comes back a bare /turf/space with empty contents, no error
	// surfaced to us, no landmark to find. Confirmed by dumping the new
	// z's contents when this happens; not yet root-caused (a map-loader
	// or GLOB.cached_maps-reuse issue under this specific "allocate a
	// brand new z, back to back, several times" pattern -- load_new_z()
	// is also SSexpedition's z-allocation path, so this may not be
	// unique to tests). Retry a few fresh attempts per slot rather than
	// let one bad load silently shrink the pool.
	for(var/attempt in 1 to 3)
		var/datum/map_template/unit_tests/template = new
		var/new_z = template.load_new_z()
		if(!new_z)
			continue
		var/datum/unit_test_block/candidate = new
		candidate.z = new_z
		// Don't rely on REGISTRY_MEMBERS(REGISTRY_LANDMARKS): atom Initialize() for a
		// freshly loaded z can be queued rather than run synchronously
		// inside load_new_z(), so the landmark may not be registered
		// into that list yet. The atom instance itself is already in
		// its turf's contents the moment load_map() places it, so
		// locate it there directly. load_new_z() always places the
		// template at (1,1) on its new z (centered = FALSE).
		for(var/tx in 1 to template.width)
			for(var/ty in 1 to template.height)
				var/turf/T = locate(tx, ty, new_z)
				if(!T)
					continue
				if(!candidate.bottom_left && locate_within(T, /obj/effect/landmark/unit_test_bottom_left))
					rel_set(candidate, nameof(candidate.bottom_left), T)
				if(!candidate.top_right && locate_within(T, /obj/effect/landmark/unit_test_top_right))
					rel_set(candidate, nameof(candidate.top_right), T)
		if(candidate.bottom_left && candidate.top_right)
			block = candidate
			break
		log_world("ensure_unit_test_block_pool: copy #[i] attempt [attempt] on z[new_z] loaded no content (empty space, not a map-loader error) -- retrying on a fresh z.")

	if(!block)
		log_world("ensure_unit_test_block_pool: copy #[i] failed 3 attempts, the unit test block pool will be smaller than requested.")
		return

	GLOB.unit_test_block_pool += block
	// A block stands in for station floor: range-to-station checks (contact levels) pass on it
	// as they did when tests ran on the map itself.
	if(using_map)
		using_map.contact_levels |= block.z

/// Checks out a free isolated test block, waiting for one to be returned if
/// every block is currently in use (should be rare -- see the pool size
/// comment above). Bounded so a genuine deadlock fails loudly instead of
/// hanging the suite forever.
/proc/acquire_unit_test_block()
	RETURN_TYPE(/datum/unit_test_block)
	ensure_unit_test_block_pool()

	var/waited = 0
	while(TRUE)
		for(var/datum/unit_test_block/block as anything in GLOB.unit_test_block_pool)
			if(!block.in_use)
				block.in_use = TRUE
				return block
		// Every block is out: a focused run's small pool grows instead of waiting.
		if(length(GLOB.unit_test_block_pool) < UNIT_TEST_BLOCK_POOL_SIZE && !GLOB.unit_test_block_pool_growing)
			GLOB.unit_test_block_pool_growing = TRUE
			unit_test_block_load(length(GLOB.unit_test_block_pool) + 1)
			GLOB.unit_test_block_pool_growing = FALSE
			continue
		waited++
		if(waited > 600) // ~60s of real time at 1 tick/sleep(1) each
			CRASH("acquire_unit_test_block: every isolated test block is still in use after 60s -- likely a stuck async teardown.")
		sleep(1)

/// Resets a block to a clean floor (deletes everything spawned on it, restores
/// default air/temperature on every open turf, drops any walls a test put up)
/// and returns it to the pool. Waits for the world's own async teardown paths
/// so a block is never recycled mid-cleanup. This runs synchronously from
/// RunUnitTest() (the runner), right after qdel(test) -- not from
/// /datum/unit_test/Destroy() itself, so Destroy() (and every subtype's
/// override) can keep the base /datum/proc/Destroy()'s SHOULD_NOT_SLEEP(TRUE)
/// instead of opting back out of it. Test harness teardown is not subject to
/// the live-game "a Destroy() must never block a tick" rule, and RunUnitTests()
/// runs each test's New()/Run()/Destroy()/release strictly sequentially, so
/// nothing else is waiting on this world to keep ticking while it waits:
/// making this async caused later tests to race ahead of a block that hadn't
/// actually finished releasing yet.
/proc/release_unit_test_block(datum/unit_test_block/block, datum/unit_test/test)
	if(!block)
		return
	// Mirror /datum/unit_test/restore_atmos(): don't hand this block's z back
	// out while expedition teardown (or anything else async) is still touching
	// turfs on it.
	while(SSexpedition && length(SSexpedition.teardown_z))
		sleep(1)

	// Leak detection: by now the destroy transaction has deleted `allocated`, so anything
	// still sitting on this block's turfs (besides the corner landmarks) is
	// something the test spawned without tracking it through allocate() --
	// directly (new X(run_loc_floor_bottom_left)) or as a side effect (an
	// item's own inventory, a decal, a temporary effect). Returned as a
	// failure message; RunUnitTest() fails the test with it.
	var/leaked = 0
	var/list/leaked_types = list()
	for(var/turf/T in block_turfs(block))
		for(var/atom/movable/AM in contents_of(T))
			if(istype(AM, /obj/effect/landmark))
				continue
			// A fire is the block's atmosphere, not an object the test made: the air
			// reset below puts it out along with the gas that feeds it.
			if(istype(AM, /obj/effect/hotspot))
				continue
			leaked++
			leaked_types[AM.type] = (leaked_types[AM.type] || 0) + 1
			// Already destroyed but back on a turf (a test moved a qdel'd atom
			// here): qdel() is a no-op on it, so without this the husk sits on
			// the block and is re-reported by every later test that draws it.
			if(QDELETED(AM))
				log_world("UNIT TEST LEAK: [test ? test.type : "?"] -- [AM.type] was already destroyed but sat on the block; pulled off")
				AM.moveToNullspace()
				continue
			// A leaked object whose Destroy() runtimes must not abort the release:
			// the block would stay in_use forever and starve every later test.
			try
				qdel(AM)
			catch(var/exception/E)
				log_world("UNIT TEST LEAK: [test ? test.type : "?"] -- qdel of leaked [AM.type] runtimed during block release: [E]")

		if(istype(T, /turf/open))
			var/turf/open/OT = T
			if(OT.active_hotspot)
				qdel(OT.active_hotspot)
			if(OT.air)
				OT.air.copy_from(dq_unit_test_block_default_air())
				OT.air_update_turf(TRUE, FALSE)
			heat_set_solid(OT, T20C)
		else if(istype(T, /turf/simulated/wall))
			// A test isolated a pair of turfs with real walls (dq_atmos_test_isolate_pair
			// et al) and never got to restore them because it errored out early.
			T.ChangeTurf(/turf/simulated/floor/tiled/steel)

	if(leaked)
		var/list/parts = list()
		for(var/leaked_type in leaked_types)
			parts += "[leaked_type] x[leaked_types[leaked_type]]"
		. = "UNIT TEST LEAK: [test ? test.type : "?"] left [leaked] object(s) on its block: [parts.Join(", ")]"
		log_world(.)

	block.in_use = FALSE

/// The default air mix a block's open turfs start with -- standard station air.
/proc/dq_unit_test_block_default_air()
	RETURN_TYPE(/datum/gas_mixture)
	var/static/datum/gas_mixture/default_air
	if(!default_air)
		default_air = new
		heat_set(default_air, T20C, HEAT_SOURCE_OTHER)
		default_air.set_moles(/datum/gas/oxygen, MOLES_O2STANDARD)
		default_air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
	return default_air.copy()

/// Every turf in a block's rectangle (inclusive), by walking its bottom-left
/// to top-right corners -- the block is always one z-level.
/proc/block_turfs(datum/unit_test_block/block)
	var/list/turfs = list()
	if(!block?.bottom_left || !block.top_right)
		return turfs
	for(var/x in block.bottom_left.x to block.top_right.x)
		for(var/y in block.bottom_left.y to block.top_right.y)
			var/turf/T = locate(x, y, block.z)
			if(T)
				turfs += T
	return turfs

/// Waits for `condition` to hold, ticking `advance` once per attempt, instead
/// of assuming a fixed number of ticks/frames is always enough (the "timing
/// assumptions" flakiness pattern: a test that only passed because a shared
/// turf happened to already be warm, or because the CI machine happened to be
/// fast enough that round N finished within a guessed frame count). Returns
/// TRUE the moment `condition` is truthy, FALSE if `max_attempts` is
/// exhausted first. `condition` and `advance` are GLOBAL_PROC_REFs called with their `_with` lists; `advance` may be null to just poll `condition` on a sleep.
/proc/wait_for_condition(condition, list/condition_with, advance, list/advance_with, max_attempts = 60)
	for(var/i in 1 to max_attempts)
		if(call(condition)(arglist(condition_with || list())))
			return TRUE
		if(advance)
			call(advance)(arglist(advance_with || list()))
		else
			sleep(world.tick_lag)
	return call(condition)(arglist(condition_with || list()))

/// The focused test types: the file named by the test-focus world param
/// (`dm-test --focus=`, tools/dq_focused_test.sh) when given, otherwise every
/// TEST_FOCUS type compiled in. Null means the full suite.
/proc/focused_tests()
	var/list/focused_tests = list()
	var/focus_file = world.params?["test-focus"]
	if(focus_file)
		var/list/names = dq_test_read_name_list("test-focus", focus_file)
		for(var/path in names)
			focused_tests += path
		if(!length(focused_tests))
			// A focus file that names nothing runnable must not fall back to
			// the full suite; run one no-op test so the world reports and exits.
			stack_trace("test-focus file [focus_file] named no known unit test")
			focused_tests += /datum/unit_test/dq_focus_named_nothing
		return focused_tests
	for (var/datum/unit_test/unit_test as anything in subtypesof(/datum/unit_test))
		if (initial(unit_test.focus))
			focused_tests += unit_test

	return focused_tests.len > 0 ? focused_tests : null

/// TRUE when this unit-test world runs only TEST_FOCUS tests
/// (tools/dq_focused_test.sh). Focused runs skip boot and shutdown waits that
/// only matter for the full suite; see "Focused runs" in doc/testing.md.
/proc/unit_test_is_focused_run()
	return !!length(GLOB.focused_tests)

// ---- Sharded sweeps (doc/testing.md "Sharded sweeps") ----

/// This world's 0-based shard index and shard count for a sharded dm-test
/// run. Read once from world params (-params shard-index=K&shard-count=N) by
/// dq_test_shard_init(), called from world/proc/HandleTestRun(). The default
/// (count 1, index 0) means "not sharded" -- a plain dm-test or focused run.
GLOBAL_VAR_INIT(dq_test_shard_index, 0)
/// See dq_test_shard_index.
GLOBAL_VAR_INIT(dq_test_shard_count, 1)

/// The sharded runner's assignment of non-sweep test types to shards, as
/// path -> shard index, or null when this world runs every test (a plain
/// dm-test/focused run). Read from the file named by the `shard-tests` world
/// param: one "path<TAB>index" line per test, the same file for every shard.
/// A test the file doesn't name (new since the durations it was balanced on)
/// goes to shard dq_test_shard_of_unlisted(), so every test runs in exactly one
/// shard. Sweep-test types (is_sweep_test) run in every shard regardless --
/// sweep_types() already spreads their cost -- and are never assigned.
GLOBAL_VAR(dq_test_shard_assignment)

/// Explicit test selection from `dm-test --domains=`/`--tier=`/`--affected`
/// (see doc/testing.md "Domains, tiers and --affected"), or null to run
/// every test that survives shard/focus filtering. Unlike the shard assignment,
/// this applies to sweep tests too: a domain filter can legitimately exclude
/// a sweep unrelated to the requested domains, so there's no is_sweep_test
/// bypass here.
GLOBAL_VAR(dq_test_select_names)

/// Reads a newline-separated list of test type paths from `file` into an
/// assoc list (path -> TRUE), for the shard-tests/test-select world params.
/// Null (not an empty list) if the param was absent; stack_trace()s and
/// returns null if the file is missing, so a bad path fails loud instead of
/// silently running every test.
/proc/dq_test_read_name_list(param_name, file)
	if(isnull(file))
		return null
	if(!fexists(file))
		stack_trace("dq_test_read_name_list: [param_name] file [file] does not exist")
		return null
	var/list/names = list()
	for(var/line in splittext(file2text(file), "\n"))
		line = trim(line)
		if(!length(line))
			continue
		var/path = text2path(line)
		if(!path)
			stack_trace("dq_test_read_name_list: [param_name] file [file] names an unknown type [line]")
			continue
		names[path] = TRUE
	return names

/// Reads the shard-tests assignment file ("path<TAB>index" per line) into an
/// assoc list path -> index. A name the build doesn't have (the durations the
/// runner balanced on can name a test removed since) is logged and skipped.
/proc/dq_test_read_shard_assignment(file)
	if(isnull(file))
		return null
	if(!fexists(file))
		stack_trace("dq_test_read_shard_assignment: shard-tests file [file] does not exist")
		return null
	var/list/assignment = list()
	for(var/line in splittext(file2text(file), "\n"))
		line = trim(line)
		if(!length(line))
			continue
		var/list/parts = splittext(line, "\t")
		var/path = text2path(parts[1])
		var/index = length(parts) > 1 ? text2num(parts[2]) : GLOB.dq_test_shard_index
		if(!path)
			log_test("Shard assignment names [parts[1]], which this build doesn't have; skipped.")
			continue
		assignment[path] = index
	return assignment

/// The shard that runs a non-sweep test missing from the assignment: a stable
/// hash of its path, so every world agrees without seeing the others.
/proc/dq_test_shard_of_unlisted(test_path)
	// A plain rolling hash of the path text (text2num(hex, 16) came back null
	// here, which sent every unlisted test to shard 0).
	var/text = "[test_path]"
	var/hash = 0
	for(var/i in 1 to length(text))
		hash = (hash * 31 + text2ascii(text, i)) % 1000003
	return hash % GLOB.dq_test_shard_count

/// Reads shard-index/shard-count/shard-tests/test-select from world params
/// into the globals above. Called once, early, from
/// world/proc/HandleTestRun(). Missing shard-index/shard-count params leave
/// the "not sharded" default in place; malformed ones fall back to it too
/// (loud, via stack_trace()) rather than silently running a wrong slice.
/proc/dq_test_shard_init()
	var/count_text = world.params[TEST_SHARD_COUNT_PARAMETER]
	var/index_text = world.params[TEST_SHARD_INDEX_PARAMETER]
	if(!isnull(count_text) || !isnull(index_text))
		var/count = text2num(count_text)
		var/index = text2num(index_text)
		if(!count || count < 1 || isnull(index) || index < 0 || index >= count)
			stack_trace("dq_test_shard_init: ignoring malformed shard params index=[index_text] count=[count_text]")
		else
			GLOB.dq_test_shard_count = count
			GLOB.dq_test_shard_index = index

	GLOB.dq_test_shard_assignment = dq_test_read_shard_assignment(world.params[TEST_SHARD_TESTS_FILE_PARAMETER])
	GLOB.dq_test_select_names = dq_test_read_name_list(TEST_SELECT_FILE_PARAMETER, world.params[TEST_SELECT_FILE_PARAMETER])

/datum/unit_test
	//Bit of metadata for the future maybe
	var/list/procs_tested

	/// The bottom left floor turf of the testing zone
	var/turf/run_loc_floor_bottom_left

	/// The top right floor turf of the testing zone
	var/turf/run_loc_floor_top_right
	///The priority of the test, the larger it is the later it fires
	var/priority = TEST_DEFAULT
	/// TRUE for a type-sweep test that calls sweep_types() to divide its own
	/// work across shards (see doc/testing.md "Sharded sweeps"). Such a test
	/// always runs in every shard's world regardless of shard-tests, since
	/// its cost is already spread across shards by sweep_types() rather than
	/// being pinned to one shard by the runner's bin-packer.
	var/is_sweep_test = FALSE
	/// TEST_TIER_NORMAL or TEST_TIER_EXHAUSTIVE. Exhaustive tests only run with
	/// the test-tier world param set to "all"/"exhaustive" (dm-test --tier=all),
	/// or when named by a focused run.
	var/tier = TEST_TIER_NORMAL
	/// Set by an E0 proof's gate when it failed because an engine piece (E1-E6) does not exist yet: the run reports it as pending,
	/// separately from a proof that failed for any other reason (doc/testing.md "The E0 proofs").
	var/pending_engine = FALSE
	/// Curated entries sweep_types() actually found (see curated_types()).
	var/list/curated_matched
	//internal shit
	var/focus = FALSE
	var/succeeded = TRUE
	var/list/allocated
	var/list/fail_reasons

	/// Do not instantiate if type matches this
	abstract_type = /datum/unit_test

	/// List of atoms that we don't want to ever initialize in an agnostic context, like for Create and Destroy. Stored on the base datum for usability in other relevant tests that need this data.
	var/static/list/uncreatables = null

	/// The isolated block this test checked out of the pool, released on Destroy().
	var/datum/unit_test_block/test_block

	/// Seconds Run() gets before RunUnitTest() gives up on it and fails it by
	/// name instead of hanging the whole suite (a real incident: one test
	/// hung 55+ minutes with no log progress). Override per subtype for a
	/// legitimately slow test. DM has no way to preempt a proc mid-sleep, so a
	/// timed-out Run() keeps executing in the background even after the suite
	/// moves on -- this bounds how long the SUITE waits, not how long the
	/// leaked fiber runs.
	var/timeout = 60
	/// Set by RunWrapped() the moment Run() actually returns.
	var/tmp/run_finished = FALSE

	/// This test's deterministic RNG seed (see New()), logged on failure so a
	/// flake involving rand()/pick() is reproducible.
	var/tmp/seed

	/// list(datum, var name, original value) per var set_var() changed; restored on destroy.
	var/tmp/list/saved_vars
	/// Original config values set_config() changed, each boxed in a one-element
	/// list (so a saved null is still a saved value); restored on destroy.
	var/tmp/list/saved_configs
	/// Rows list(target, PROC_REF, with) defer_cleanup() queued; run last-first on destroy.
	var/tmp/list/deferred_cleanups

/// A stable, deterministic seed for a test's own name: same input, same
/// output, forever, regardless of process or run order -- unlike rand()'s own
/// state, which drifts with everything that ran before it.
/proc/dq_test_seed_for(text)
	var/hash = 0
	for(var/i in 1 to length(text))
		hash = ((hash * 31) + text2ascii(text, i)) & 0x7FFFFFFF
	return hash || 1

/datum/unit_test/proc/RunWrapped()
	// Run() starts inside RunUnitTest()'s own call stack (INVOKE_ASYNC only
	// detaches at the first sleep). Uncaught, a runtime before that sleep
	// unwinds RunUnitTest() and RunUnitTests() too -- and RunUnitTests() runs
	// under the OM sleep-guard trampoline, whose try/catch swallows it, so the
	// whole suite silently stops and the watchdog kills the world with no
	// results. Catch it here: the test fails with the runtime, the suite goes on.
	try
		Run()
	catch(var/exception/e)
		log_world("UNIT TEST RUNTIME: [type]: [e.name] at [e.file]:[e.line] -- [e.desc]")
		Fail("runtime in Run(): [e.name]", e.file || "RUNTIME", e.line || 0)
	// A representative must actually cover its curated subset: an entry that
	// was renamed or removed would otherwise shrink it silently.
	var/list/curated = curated_types()
	if(curated)
		for(var/entry in curated)
			if(!LAZYACCESS(curated_matched, "[entry]"))
				Fail("curated entry [entry] was not in the sweep (renamed or removed? update curated_types())", __FILE__, __LINE__)
	// End the test's world in the tick Run() returns. RunUnitTest() only notices run_finished
	// on its next poll and then restores atmos before deleting the test, and OM work still
	// pending on the test's entities (a mob's telegraphed strike is an om_after on its clock)
	// would otherwise fire in that gap, with nothing left to own what it makes.
	end_test_world()
	run_finished = TRUE

/// A normal-tier representative's fixed subset of an exhaustive sweep, or null
/// (the default: sweep everything). Filters sweep_types(); see doc/testing.md "Tiers".
/datum/unit_test/proc/curated_types()
	return null

/proc/cmp_unit_test_priority(datum/unit_test/a, datum/unit_test/b)
	return initial(a.priority) - initial(b.priority)

/datum/unit_test/New()
	if (isnull(uncreatables))
		uncreatables = build_list_of_uncreatables()

	rel_set(src, nameof(test_block), acquire_unit_test_block())
	rel_set(src, nameof(run_loc_floor_bottom_left), test_block.bottom_left)
	rel_set(src, nameof(run_loc_floor_top_right), test_block.top_right)

	// Deterministic per-test RNG: reseed from the test's own type name rather
	// than leaving the shared world RNG wherever the previous test's rand()
	// calls left it. That previous position depends on execution order and on
	// which other tests ran first (worse, on whether this is a full or
	// focused run), so a rand()/pick() a test relies on can silently see a
	// different draw between runs -- the "fishing-hat RNG" and unseeded
	// pick() flakes. Seeding from the type name makes every test's random
	// sequence reproducible on its own, independent of what ran before it:
	// re-running just this one test (dq_focused_test.sh) reproduces the exact
	// same sequence a full-suite failure saw.
	seed = dq_test_seed_for("[type]")
	rand_seed(seed)

	TEST_ASSERT(isfloorturf(run_loc_floor_bottom_left), "run_loc_floor_bottom_left was not a floor ([run_loc_floor_bottom_left])")
	TEST_ASSERT(isfloorturf(run_loc_floor_top_right), "run_loc_floor_top_right was not a floor ([run_loc_floor_top_right])")

/// Everything allocate() made is the test's to delete when it ends. `allocated` is a relation
/// list, never ownership: production code adopts allocated things freely, and whatever is still
/// alive here when the test is torn down is deleted (deleted entries have left the view).
/datum/unit_test/relations()
	. = ..()
	. += rel_many(nameof(allocated))

/datum/unit_test/on_destroy(force)
	end_test_world() // already done unless Run() timed out
	restore_test_overrides()
	..()

/// Runs the deferred cleanups, then deletes everything allocate()d; their timers and tasks die
/// with them. Called as Run() returns and again on destroy (a no-op the second time).
/datum/unit_test/proc/end_test_world()
	run_deferred_cleanups()
	for(var/datum/thing as anything in allocated?.Copy())
		if(!QDELETED(thing))
			qdel(thing)
	// A test that took the kernel clock (test_driver_begin) hands it back whatever way it ended: an early return from a failed
	// assertion or a runtime would otherwise leave every later test running on an injected clock.
	test_driver_end()

/// Sets `target.vars[name]` for the rest of this test. The first change to each var records its
/// original value, and on_destroy() puts it back (last change first). A failing TEST_ASSERT
/// (which returns from Run()) or a runtime then can't leak the change into later tests.
/// Returns `value`.
/datum/unit_test/proc/set_var(datum/target, name, value)
	if(!(name in target.vars))
		CRASH("set_var: [target.type] has no var [name]")
	var/already = FALSE
	for(var/list/entry as anything in saved_vars)
		if(entry[1] == target && entry[2] == name)
			already = TRUE
			break
	if(!already)
		LAZYADD(saved_vars, list(list(target, name, target.vars[name])))
	target.vars[name] = value
	return value

/// set_var() on GLOB: sets GLOB.<name> for the rest of this test.
/datum/unit_test/proc/set_global(name, value)
	return set_var(GLOB, name, value)

/// Sets a config entry (a /datum/config_entry path) for the rest of this test; restored like
/// set_var(). Returns `value`.
/datum/unit_test/proc/set_config(entry_type, value)
	if(!LAZYACCESS(saved_configs, entry_type))
		LAZYSET(saved_configs, entry_type, list(global.config.Get(entry_type)))
	global.config.Set(entry_type, value)
	return value

/// Calls `target`'s `proc_ref` with `...` when the test is torn down (last queued first, before
/// allocate()d things are deleted and set_var() changes restored, and before the block's leak check),
/// even if a TEST_ASSERT returned from Run() early or Run() runtimed. For cleanup that isn't a
/// qdel(): releasing a site, unregistering from a global list. A null target calls a global proc.
/datum/unit_test/proc/defer_cleanup(datum/target, proc_ref, ...)
	var/list/with = length(args) > 2 ? args.Copy(3) : null
	if(target)
		LAZYADD(deferred_cleanups, list(list(target, proc_ref, with)))
	else
		LAZYADD(deferred_cleanups, list(list(src, TYPE_PROC_REF(/datum/unit_test, run_global_cleanup), list(proc_ref) + with)))

/// A deferred cleanup that is a global proc taking no holder: defer_cleanup(null, GLOBAL_PROC_REF(x), args...).
/datum/unit_test/proc/run_global_cleanup(proc_ref, ...)
	call(proc_ref)(arglist(args.Copy(2)))

/datum/unit_test/proc/run_deferred_cleanups()
	var/list/pending = deferred_cleanups
	deferred_cleanups = null
	for(var/i in length(pending) to 1 step -1)
		try
			var/list/row = pending[i]
			holder_call(row[1], row[2], row[3])
		catch(var/exception/e)
			// Teardown runs after the test's result is logged: fail the run, not just the test.
			log_world("::error::UNIT TEST CLEANUP RUNTIME: [type]: [e.name] at [e.file]:[e.line]")
			GLOB.failed_any_test = TRUE

/// Puts back everything set_var()/set_global()/set_config() changed.
/datum/unit_test/proc/restore_test_overrides()
	for(var/i in length(saved_vars) to 1 step -1)
		var/list/entry = saved_vars[i]
		var/datum/target = entry[1]
		if(!QDELETED(target))
			target.vars[entry[2]] = entry[3]
	for(var/entry_type in saved_configs)
		var/list/box = saved_configs[entry_type]
		global.config.Set(entry_type, box[1])
	saved_vars = null
	saved_configs = null

/datum/unit_test/proc/Run()
	TEST_FAIL("[type]/Run() called parent or not implemented")

/// The reasons an E0 proof failed with, for the pending report (the "E1-E6 not implemented: ..." text).
/datum/unit_test/proc/pending_reasons()
	. = list()
	for(var/list/entry in fail_reasons)
		. += entry[1]

/datum/unit_test/proc/Fail(reason = "No reason", file = "OUTDATED_TEST", line = 1)
	succeeded = FALSE

	if(!istext(reason))
		reason = "FORMATTED: [reason != null ? reason : "NULL"]"

	// Seed on the first failure only -- later assertions in the same test
	// don't need it repeated, and it'd bury the actual failure text.
	if(!LAZYLEN(fail_reasons) && seed)
		reason = "[reason] (rng seed [seed]: dq_focused_test.sh reruns this test alone with the same seed)"

	LAZYADD(fail_reasons, list(list(reason, file, line)))

/// Lets `n` server ticks pass. The one place a test sleeps for time (doc/rewrite/kernel.md sec 1.7).
/datum/unit_test/proc/wait_ticks(n = 1)
	sleep(world.tick_lag * n)

/// Waits, a tick at a time, until `condition` (a callback) returns true or `timeout_ticks` pass. Returns
/// whether the condition held.
/datum/unit_test/proc/run_until(datum/callback/condition, timeout_ticks = 100)
	for(var/i in 1 to timeout_ticks)
		if(condition.Invoke())
			return TRUE
		sleep(world.tick_lag)
	return !!condition.Invoke()

/// Allocates an instance of the provided type, and places it somewhere in an available loc
/// Instances allocated through this proc will be destroyed when the test is over
/datum/unit_test/proc/allocate(type, ...)
	var/list/arguments = args.Copy(2)
	if(ispath(type, /atom))
		if (!arguments.len)
			arguments = list(run_loc_floor_bottom_left)
		else if (arguments[1] == null)
			arguments[1] = run_loc_floor_bottom_left
	var/datum/instance
	// Byond will throw an index out of bounds if arguments is empty in that arglist call. Sigh
	if(length(arguments))
		instance = new type(arglist(arguments))
	else
		instance = new type()
	// A type that deletes itself in Initialize() (INITIALIZE_HINT_QDEL: a lattice off open space)
	// is already gone: nothing to clean up, and a dying thing takes no new links.
	if(!QDELETED(instance))
		rel_add(src, nameof(allocated), instance)
	return instance

/// Hands something the test didn't allocate() but did cause (a construction product, a
/// built bot, a spawned effect) to the test, so it is deleted when the test is over.
/// Returns `thing`.
/datum/unit_test/proc/own(datum/thing)
	if(thing && !QDELETED(thing))
		rel_add(src, nameof(allocated), thing)
	return thing

/// own()s everything currently on `T` (landmarks excepted): for a test whose subject
/// deliberately leaves its products on the floor (deconstruction salvage, a finished build).
/datum/unit_test/proc/own_turf_contents(turf/T)
	for(var/atom/movable/AM as anything in contents_of(T))
		if(!istype(AM, /obj/effect/landmark))
			own(AM)

/// A floor turf on the map, for tests whose subject must be in the world.
/// allocate() defaults to run_loc_floor_bottom_left, which is null when the
/// unit-test room template isn't loaded.
/datum/unit_test/proc/test_floor()
	RETURN_TYPE(/turf)
	if(run_loc_floor_bottom_left)
		return run_loc_floor_bottom_left
	for(var/turf/simulated/floor/T in world)
		return T

/// Returns this world's shard of `types`, for a type-sweep test running
/// under a sharded dm-test run (`dm-test --shards=N`; see doc/testing.md
/// "Sharded sweeps"). Splits by round-robin index rather than a contiguous
/// range, so a shard's slice stays representative even when `types` is
/// clustered (e.g. many cheap subtypes of one branch followed by a few
/// costly ones from another) -- every shard ends up with a similar-cost
/// slice of THIS sweep automatically, without the runner having to bin-pack
/// what's inside it. With no sharding configured (a plain dm-test or
/// focused run, the default), returns `types` unchanged.
///
/// `types` is typically subtypesof()/typesof() of some root; pass it
/// straight through, e.g.:
///   for(var/atom/movable/path as anything in sweep_types(subtypesof(/atom/movable)))
/datum/unit_test/proc/sweep_types(list/types)
	// A normal-tier representative of an exhaustive sweep names its fixed
	// subset in curated_types(); the sweep then covers only those entries
	// (matched by text, so a list of type paths or of path strings both work).
	var/list/curated = curated_types()
	if(curated)
		var/list/wanted = list()
		for(var/entry in curated)
			wanted["[entry]"] = TRUE
		var/list/kept = list()
		for(var/entry in types)
			if(wanted["[entry]"])
				kept += entry
				LAZYSET(curated_matched, "[entry]", TRUE)
		types = kept
	// Only a sweep test (runs in every shard) takes a slice; anything else runs
	// in the one shard it was assigned to and must cover all of `types` there.
	if(GLOB.dq_test_shard_count <= 1 || !is_sweep_test)
		return types
	. = list()
	var/i = 0
	for(var/entry in types)
		if((i % GLOB.dq_test_shard_count) == GLOB.dq_test_shard_index)
			. += entry
		i++

/// Whether this world's shard owns work unit `index` (0-based) of a sweep test
/// that slices by its own counter rather than through sweep_types(). TRUE for
/// every unit when not sharded, or for a test that isn't a sweep.
/datum/unit_test/proc/sweep_owns(index)
	if(GLOB.dq_test_shard_count <= 1 || !is_sweep_test)
		return TRUE
	return (index % GLOB.dq_test_shard_count) == GLOB.dq_test_shard_index

/// Resets the air of our testing room to its default
/datum/unit_test/proc/restore_atmos()
	// Expedition release is deliberately asynchronous in production. Do not let
	// the next test start while a teardown job is still changing thousands of
	// turfs and publishing atmosphere topology.
	while(SSexpedition && length(SSexpedition.teardown_z))
		sleep(1)
	// DQ atmos integration tests operate on mapped turfs because the inherited
	// per-test reservation is not implemented. Restore every turf they snapshot
	// after each test so later tests and shuttles never inherit vacuum, test gas,
	// or temporary sealing geometry.
	dq_atmos_test_restore_state()

/datum/unit_test/proc/test_screenshot(name, icon/icon)
	if (!istype(icon))
		TEST_FAIL("[icon] is not an icon.")
		return

	var/path_prefix = replacetext(replacetext("[type]", "/datum/unit_test/", ""), "/", "_")
	name = replacetext(name, "/", "_")

	var/filename = "code/modules/unit_tests/screenshots/[path_prefix]_[name].png"

	if (fexists(filename))
		var/data_filename = "data/screenshots/[path_prefix]_[name].png"
		fcopy(icon, data_filename)
		log_test("\t[path_prefix]_[name] was found, putting in data/screenshots")
	else
#ifdef CIBUILDING
		// We are runing in real CI, so just pretend it worked and move on
		fcopy(icon, "data/screenshots_new/[path_prefix]_[name].png")

		log_test("\t[path_prefix]_[name] was put in data/screenshots_new")
#else
		// We are probably running in a local build
		fcopy(icon, filename)
		TEST_FAIL("Screenshot for [name] did not exist. One has been created.")
#endif

/// Helper for screenshot tests to take an image of an atom from all directions and insert it into one icon
/datum/unit_test/proc/get_flat_icon_for_all_directions(atom/thing, no_anim = TRUE)
	var/icon/output = icon('icons/effects/effects.dmi', "nothing")

	for (var/direction in GLOB.cardinal)
		var/icon/partial = getFlatIcon(thing, defdir = direction, no_anim = no_anim)
		output.Insert(partial, dir = direction)

	return output

/// Logs a test message. Will use GitHub action syntax found at https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
/datum/unit_test/proc/log_for_test(text, priority, file, line)
	var/map_name = SSmapping.current_map.name

	// Need to escape the text to properly support newlines.
	var/annotation_text = replacetext(text, "%", "%25")
	annotation_text = replacetext(annotation_text, "\n", "%0A")

	log_world("::[priority] file=[file],line=[line],title=[map_name]: [type]::[annotation_text]")

/**
 * Helper to perform a click
 *
 * * clicker: The mob that will be clicking
 * * clicked_on: The atom that will be clicked
 * * passed_params: A list of parameters to pass to the click
 */
/datum/unit_test/proc/click_wrapper(mob/living/clicker, atom/clicked_on, list/passed_params = list(LEFT_CLICK = 1, BUTTON = LEFT_CLICK))
	clicker.next_click = -1
	clicker.next_move = -1
	clicker.ClickOn(clicked_on, list2params(passed_params))

/// Tick usage while a test ran: how many MC ticks it spanned, how many overran
/// (usage above 100%) and the worst one. Recorded in data/unit_tests.json.
/proc/unit_test_tick_stats(start_index)
	var/list/usage = Kernel.perf_tick_usage
	if(start_index > usage.len)
		return list("samples" = 0, "overruns" = 0, "max" = 0)
	var/overruns = 0
	var/worst = 0
	for(var/i in start_index to usage.len)
		var/value = usage[i]
		worst = max(worst, value)
		if(value > 100)
			overruns++
	return list("samples" = usage.len - start_index + 1, "overruns" = overruns, "max" = worst)

/// Writes the proc profile gathered around one test to
/// data/logs/<log dir>/profile/<test path>.json and stops the profiler.
/proc/dq_test_write_profile(test_path)
	var/profile = world.Profile(PROFILE_REFRESH, null, "json")
	world.Profile(PROFILE_STOP)
	var/safe_name = replacetext(copytext("[test_path]", length("/datum/unit_test/") + 1), "/", "__")
	var/file_name = "[GLOB.log_directory]/profile/[safe_name].json"
	fdel(file_name)
	text2file(profile, file_name)
	log_test("Profile for [test_path] written to [file_name]")

/proc/RunUnitTest(datum/unit_test/test_path, list/test_results, current_index, total_tests)
	if(ispath(test_path, /datum/unit_test/focus_only))
		return

	if(initial(test_path.abstract_type) == test_path)
		return

	var/datum/unit_test/test = new test_path

	GLOB.current_test = test
	var/duration = 0
	var/tick_start_index = 0
	var/runtimes_before = GLOB.total_runtimes
	var/list/sites_before = SSexpedition?.sites?.Copy()
	var/list/globals_before = unit_test_globals_snapshot()
	var/list/gravity_before = unit_test_gravity_snapshot()
	var/list/tick_stats
	// Generated-station coverage is temporarily disabled while that subsystem is
	// being redesigned. Keep the cases compiled and visible as skipped so they
	// cannot silently disappear from the suite inventory.
	var/test_path_text = "[test_path]"
	var/generated_station_test = findtext(test_path_text, "/datum/unit_test/dq_generated_station") == 1 || findtext(test_path_text, "/datum/unit_test/dq_generated_room") == 1 || (test_path in list(
		/datum/unit_test/dq_expedition_generates_site,
		/datum/unit_test/dq_debug_station_initializes_complete_runtime,
		/datum/unit_test/dq_emergency_station_fallback_is_playable,
	))
	var/skip_test = generated_station_test || (test_path in SSmapping.current_map.skipped_tests)
	var/test_output_desc = "[test_path]"
	var/message = ""

	log_world("::group::([current_index]/[total_tests]) [test_path]")
	log_test("Running [current_index]/[total_tests]: [test_path]")

	if(skip_test)
		log_world("[TEST_OUTPUT_YELLOW("SKIPPED")] Skipped run on map [SSmapping.current_map.name].")

	else
		// dm-test --profile-tests: BYOND's proc profiler around each test, dumped
		// per test so a slow test's hot procs can be read without a one-off script.
		var/profiling = !!world.params?[TEST_PROFILE_PARAMETER]
		if(profiling)
			world.Profile(PROFILE_CLEAR)
			world.Profile(PROFILE_START)
		duration = REALTIMEOFDAY
		tick_start_index = Kernel.perf_samples_total + 1
		INVOKE_ASYNC(test, TYPE_PROC_REF(/datum/unit_test, RunWrapped))
		var/waited_ds = 0
		var/limit_ds = test.timeout SECONDS
		while(!test.run_finished && waited_ds < limit_ds)
			sleep(1)
			waited_ds += world.tick_lag
		if(!test.run_finished)
			log_world("UNIT TEST TIMEOUT: [test_path] did not return from Run() within [test.timeout]s; failing it and moving on. Its fiber may still be running in the background.")
			test.Fail("timed out after [test.timeout]s -- Run() never returned (stuck sleep, unmet wait_for_condition, or a hung external call)", "TIMEOUT", 0)
		test.restore_atmos()

		duration = REALTIMEOFDAY - duration
		if(profiling)
			dq_test_write_profile(test_path)
		tick_stats = unit_test_tick_stats(Kernel.perf_index_of(tick_start_index))
		GLOB.current_test = null
		GLOB.failed_any_test |= !test.succeeded

		var/list/log_entry = list()
		var/list/fail_reasons = test.fail_reasons

		for(var/reasonID in 1 to LAZYLEN(fail_reasons))
			var/text = fail_reasons[reasonID][1]
			var/file = fail_reasons[reasonID][2]
			var/line = fail_reasons[reasonID][3]

			test.log_for_test(text, "error", file, line)

			// Normal log message
			log_entry += "\tFAILURE #[reasonID]: [text] at [file]:[line]"

		if(length(log_entry))
			message = log_entry.Join("\n")
			log_test(message)

		test_output_desc += " [duration / 10]s"
		if (test.succeeded)
			log_world("[TEST_OUTPUT_GREEN("PASS")] [test_output_desc]")

	log_world("::endgroup::")

	if (!test.succeeded && !skip_test)
		log_world("::error::[TEST_OUTPUT_RED("FAIL")] [test_output_desc]")

	var/final_status = skip_test ? UNIT_TEST_SKIPPED : (test.succeeded ? UNIT_TEST_PASSED : UNIT_TEST_FAILED)
	if(initial(test.tier) == TEST_TIER_E0 && !skip_test)
		// An E0 proof is reported three ways, separately from the rest of the run: green, pending an engine, or failed.
		if(test.succeeded)
			GLOB.e0_proofs_passed++
		else if(test.pending_engine)
			GLOB.e0_proofs_pending++
			log_world("E0 PENDING [test_output_desc]: [jointext(test.pending_reasons(), "; ")]")
		else
			GLOB.e0_proofs_failed++

	var/datum/unit_test_block/block = test.test_block
	qdel(test)
	// A test must delete everything it creates (allocate(), or its own qdel()s). Whatever
	// is still on its block once `allocated` is gone fails the test.
	var/leak = release_unit_test_block(block, test)
	var/site_leak = unit_test_site_leak(sites_before, test_path)
	unit_test_globals_guard(globals_before, test_path)
	unit_test_gravity_guard(gravity_before, test_path)
	if(site_leak)
		leak = leak ? "[leak]\n\t[site_leak]" : site_leak
	if(leak && !skip_test)
		GLOB.failed_any_test = TRUE
		if(final_status == UNIT_TEST_PASSED)
			log_world("::error::[TEST_OUTPUT_RED("FAIL")] [test_output_desc] (leaked objects)")
		final_status = UNIT_TEST_FAILED
		message = message ? "[message]\n\t[leak]" : "\t[leak]"
		log_test("\t[leak]")

	test_results[test_path] = list("status" = final_status, "message" = message, "name" = test_path, "duration_ds" = duration, "runtimes" = GLOB.total_runtimes - runtimes_before, "ticks" = tick_stats)

/// GLOB vars the state guard ignores: run bookkeeping and counters that move on their own.
/proc/unit_test_globals_ignored()
	var/static/list/ignored = list(
		"vars" = TRUE, "type" = TRUE, "parent_type" = TRUE, "tag" = TRUE, "current_test" = TRUE, "failed_any_test" = TRUE,
		"total_runtimes" = TRUE, "total_runtimes_skipped" = TRUE, "boot_noise_count" = TRUE, "boot_unclean" = TRUE,
		"act_last_reason" = TRUE, "act_last_outcome" = TRUE, "e0_proofs_passed" = TRUE, "e0_proofs_pending" = TRUE, "e0_proofs_failed" = TRUE,
	)
	return ignored

/// The scalar GLOB vars (numbers, text, paths, null) before a test: the state guard compares them after it.
/proc/unit_test_globals_snapshot()
	. = list()
	var/list/ignored = unit_test_globals_ignored()
	for(var/name in GLOB.vars)
		if(ignored[name])
			continue
		var/value = GLOB.vars[name]
		if(isnull(value) || isnum(value) || istext(value) || ispath(value))
			.[name] = list(value)

/**
 * The state guard: a test that leaves a global flag changed poisons every later test in the run, a failure that
 * shows only in a long focused run and never alone (dq_rule_thresholds, vent_internal_check). After each test, a
 * scalar GLOB var that changed is logged in tests.log: "STATE LEAK" for a flag (null, 0 or 1 before and after, not
 * a counter or a lazy-init marker), "STATE LEAK?" for text and paths; numbers that are not flags are ignored. It
 * only flags, never restores: a lazy-init flag put back would rebuild what it guards. When a test fails only in a
 * long run, grep the run's tests.log for STATE LEAK before it (tools/dq_focused_test.sh prints them on a failure). Change shared state with set_global()/set_var() (restored in teardown) and the guard stays quiet.
 */
/proc/unit_test_globals_guard(list/before, test_path)
	var/list/ignored = unit_test_globals_ignored()
	var/static/regex/counter = regex(@"(built|initialized|ready|done|loaded|roundstat|count|next|total|_id$|^id_|gen$|_gen|serial|tick|time|last|seq|index|builds|cursor|stamp)", "i")
	for(var/name in GLOB.vars)
		if(ignored[name])
			continue
		var/value = GLOB.vars[name]
		var/list/box = before[name]
		if(!box)
			continue
		var/was = box[1]
		if(was == value)
			continue
		var/flag = (isnull(was) || was == 0 || was == 1) && (isnull(value) || value == 0 || value == 1)
		if(flag && !counter.Find(name))
			log_test("STATE LEAK: [test_path] left GLOB.[name] = [isnull(value) ? "null" : value] (was [isnull(was) ? "null" : was]). If a later test fails only in a long run, this is a suspect: change it with set_global() in the test.")
		else if(!(isnum(was) && isnum(value))) // a number that moved is a counter: quiet
			log_test("STATE LEAK?: [test_path] changed GLOB.[name]: [isnull(was) ? "null" : was] -> [isnull(value) ? "null" : value] (not restored)")

/// Every area's gravity, as area -> has_gravity: an area's gravity outlives the test that switched it (a gravity generator destroyed, a holodeck
/// program), and every later test's mobs then drift.
/proc/unit_test_gravity_snapshot()
	. = list()
	for(var/area/A in world)
		.[A] = A.has_gravity

/// Logs "STATE LEAK" for each area whose gravity the test changed (the state guard's rule: it flags, it does not restore).
/proc/unit_test_gravity_guard(list/before, test_path)
	for(var/area/A as anything in before)
		if(!QDELETED(A) && A.has_gravity != before[A])
			log_test("STATE LEAK: [test_path] left [A] ([A.type]) with has_gravity = [A.has_gravity] (was [before[A]]). Its mobs drift in every later test: put it back (gravitychange()) in the test.")

/// Expedition sites are global (each holds a whole z-level) and outlive the test block, so a test
/// that generates one must release it, through defer_cleanup() so a failing assert can't skip
/// it. Returns a leak message for sites still live that weren't before the test, releasing them so
/// later tests start without them.
/proc/unit_test_site_leak(list/sites_before, test_path)
	var/datum/system/expedition/service = SSexpedition
	if(!service)
		return
	var/list/leaked = list()
	for(var/key in service.sites)
		if(!(key in sites_before))
			leaked += key
	if(!length(leaked))
		return
	for(var/key in leaked)
		var/datum/expedition_site/site = service.sites[key]
		if(site)
			service.release_site(site, "unit test [test_path] leaked it")
	return "UNIT TEST LEAK: [test_path] left [length(leaked)] expedition site(s) live (z [leaked.Join(", ")]); release them with defer_cleanup()"

/// Builds (and returns) a list of atoms that we shouldn't initialize in generic testing, like Create and Destroy.
/// It is appreciated to add the reason why the atom shouldn't be initialized if you add it to this list.
/datum/unit_test/proc/build_list_of_uncreatables()
	RETURN_TYPE(/list)
	var/list/returnable_list = list()
	// The following are just generic, singular types.
	returnable_list = list(
		//Never meant to be created, errors out the ass for mobcode reasons
		/mob/living/carbon,
		//And another
		// NOT IMPLEMENTED: /obj/item/slimecross/recurring,
		//This should be obvious
		// NOT IMPLEMENTED: /obj/machinery/doomsday_device,
		//Yet more templates
		// NOT IMPLEMENTED: /obj/machinery/restaurant_portal,
		//Template type
		// /obj/machinery/power/turbine deleted with ZAS atmos.
		// NOT IMPLEMENTED: /obj/machinery/power/turbine,
		//Template type
		// NOT IMPLEMENTED: /obj/effect/mob_spawn,
		//Template type
		// NOT IMPLEMENTED: /obj/structure/holosign/robot_seat,
		//Singleton
		/mob/dview,
		//Template type
		// NOT IMPLEMENTED: /obj/item/bodypart,
		//This is meant to fail extremely loud every single time it occurs in any environment in any context, and it falsely alarms when this unit test iterates it. Let's not spawn it in.
		/obj/merge_conflict_marker,
		//briefcase launchpads erroring
		// NOT IMPLEMENTED: /obj/machinery/launchpad/briefcase,
		//Wings abstract path
		// NOT IMPLEMENTED: /obj/item/organ/wings,
		//Not meant to spawn without the machine wand
		// NOT IMPLEMENTED: /obj/effect/bug_moving,
		//The abstract grown item expects a seed, but doesn't have one
		// NOT IMPLEMENTED: /obj/item/food/grown,
		///Single use case holder atom requiring a user
		// NOT IMPLEMENTED: /atom/movable/looking_holder,
	)

	// Everything that follows is a typesof() check.

	//Say it with me now, type template
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/mapping_helpers)
	//This turf existing is an error in and of itself
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/baseturf_skipover)
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/baseturf_bottom)
	//This demands a borg, so we'll let if off easy
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/modular_computer/pda/silicon)
	//This one demands a computer, ditto
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/modular_computer/processor)
	//Very finiky, blacklisting to make things easier
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/poster/wanted)
	//Needs clients / mobs to observe it to exist. Also includes hallucinations.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/client_image_holder)
	//Same to above. Needs a client / mob / hallucination to observe it to exist.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/projectile/hallucination)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/hallucinated)
	//We don't have a pod
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/pod_landingzone_effect)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/pod_landingzone)
	//We have a baseturf limit of 10, adding more than 10 baseturf helpers will kill CI, so here's a future edge case to fix.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/baseturf_helper)
	//No tauma to pass in
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/eye/imaginary_friend)
	//No heart to give
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/structure/ethereal_crystal)
	//No linked console
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/eye/camera/remote/base_construction)
	//See above
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/eye/camera/remote/shuttle_docker)
	//Hangs a ref post invoke async, which we don't support. Could put a qdeleted check but it feels hacky
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/anomaly/grav/high)
	//See above
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/timestop)
	//Sparks can ignite a number of things, causing a fire to burn the floor away. Only you can prevent CI fires
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/particle_effect/sparks)
	//See above - These are one of those things.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/decal/cleanable/fuel_pool)
	//Invoke async in init, skippppp
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/living/silicon/robot/model)
	//This lad also sleeps
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/hilbertshotel)
	//this boi spawns turf changing stuff, and it stacks and causes pain. Let's just not
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/sliding_puzzle)
	//these can explode and cause the turf to be destroyed at unexpected moments
	returnable_list += typesof(/obj/effect/mine)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/spawner/random/contraband/landmine)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/minespawner)
	//Stacks baseturfs, can't be tested here
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/temp_visual/lava_warning)
	//Stacks baseturfs, can't be tested here
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/landmark/ctf)
	//Our system doesn't support it without warning spam from unregister calls on things that never registered
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/docking_port)
	//Asks for a shuttle that may not exist, let's leave it alone
	returnable_list += typesof(/obj/item/pinpointer/shuttle)
	//This spawns beams as a part of init, which can sleep past an async proc. This hangs a ref, and fucks us. It's only a problem here because the beam sleeps with CHECK_TICK
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/structure/alien/resin/flower_bud)
	//Needs a linked mecha
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/skyfall_landingzone)
	//Expects a mob to holderize, we have nothing to give
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/clothing/head/mob_holder)
	//Needs cards passed into the initilazation args
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/toy/cards/cardhand)
	//Needs a holodeck area linked to it which is not guarenteed to exist and technically is supposed to have a 1:1 relationship with computer anyway.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/machinery/computer/holodeck)
	//runtimes if not paired with a landmark
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/structure/transport/linear)
	// Runtimes if the associated machinery does not exist, but not the base type
	// NOT IMPLEMENTED: returnable_list += subtypesof(/obj/machinery/airlock_controller)
	// Always ought to have an associated escape menu. Any references it could possibly hold would need one regardless.
	// NOT IMPLEMENTED: returnable_list += subtypesof(/atom/movable/screen/escape_menu)
	// Can't spawn openspace above nothing, it'll get pissy at me
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/open/space/openspace)
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/open/openspace)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/robot_model) // These should never be spawned outside of a robot.

	// Lifecycle diagnostics fixtures: refuse to initialize, one runtimes in Destroy() on purpose (dq_lifecycle_diag_tests.dm).
	returnable_list += typesof(/obj/item/dq_diag_init_refuser)
	return returnable_list

/// Why the boot was not clean (the boot gate), or null. FinishTestRun() fails the run on it.
GLOBAL_VAR(boot_unclean)

/**
 * The boot gate (doc/rewrite/boot_gate.md): the world must boot with no runtime and no logged warning
 * ("## WARNING", a refused MOVE_INTO) before the first test starts. Whatever the boot logged is the boot's
 * fault, not the test's, so it is reported on its own: data/logs/<run>/boot_report.json, a loud line in
 * tests.log, and a failed run ("Boot was not clean") however the tests did. Every focused run checks it,
 * so whoever adds a boot runtime sees it in their next run.
 */
/proc/unit_test_boot_gate()
	var/runtimes = GLOB.total_runtimes
	var/noise = GLOB.boot_noise_count
	var/list/report = list(
		"runtimes" = runtimes,
		"warnings" = noise,
		"first_warnings" = GLOB.boot_noise_first.Copy(),
		"runtime_log" = "[GLOB.log_directory]/runtime-errors.log",
	)
	rustg_file_write(json_encode(report), "[GLOB.log_directory]/boot_report.json")
	if(!runtimes && !noise)
		log_test("Boot gate: clean (0 runtimes, 0 warnings before the first test).")
		return
	GLOB.boot_unclean = "Boot was not clean: [runtimes] runtime(s) and [noise] warning(s) before the first test (data/logs/<run>/boot_report.json, runtime-errors.log)"
	log_test("::error title=Boot gate::[GLOB.boot_unclean]")
	for(var/line in GLOB.boot_noise_first)
		log_test("  boot warning: [line]")

/// The round-start callback that starts the suite. The suite sleeps between tests (it waits on the kernel), and a
/// scheduler callback that sleeps is reported as "OM: SLEPT" and stalls its caller; this returns at once and the suite
/// runs on its own.
/proc/start_unit_tests()
	set waitfor = FALSE
	RunUnitTests()

/proc/RunUnitTests()
	#ifdef BENCHMARK
	RunBenchmarks()
	return
	#endif
	CHECK_TICK
	// Mapped patrol bots run independently of tests and can enqueue expensive
	// pathfinding while the suite is deliberately saturating the tick budget.
	// Tests that exercise bots allocate their own isolated instances.
	for(var/mob/living/bot/map_bot in world)
		qdel(map_bot)

	var/list/tests_to_run = subtypesof(/datum/unit_test)
	var/list/focused_tests = GLOB.focused_tests
	if(length(focused_tests))
		tests_to_run = focused_tests.Copy()

	// Sharded run: keep this shard's non-sweep tests (assigned here, or
	// unlisted and hashed here), plus every sweep test (it always runs -- see
	// is_sweep_test).
	var/list/assignment = GLOB.dq_test_shard_assignment
	if(assignment)
		var/list/sharded = list()
		var/unlisted = 0
		for(var/_test_to_run in tests_to_run)
			var/datum/unit_test/test_to_run = _test_to_run
			if(initial(test_to_run.is_sweep_test))
				sharded += test_to_run
				continue
			var/assigned = assignment[test_to_run]
			if(isnull(assigned))
				assigned = dq_test_shard_of_unlisted(test_to_run)
				if(assigned == GLOB.dq_test_shard_index)
					unlisted++
			if(assigned == GLOB.dq_test_shard_index)
				sharded += test_to_run
		log_test("Shard [GLOB.dq_test_shard_index + 1]/[GLOB.dq_test_shard_count]: [length(sharded)] test types ([unlisted] not in the assignment, placed by hash).")
		tests_to_run = sharded

	// dm-test --domains=/--tier=/--affected: an explicit selection, applied
	// to every test including sweeps (a domain filter can legitimately
	// exclude a sweep it has nothing to do with).
	if(GLOB.dq_test_select_names)
		var/list/selected = list()
		for(var/_test_to_run in tests_to_run)
			if(GLOB.dq_test_select_names[_test_to_run])
				selected += _test_to_run
		tests_to_run = selected

	// Tier: a plain run is the normal tier; "all" adds the exhaustive sweeps,
	// "exhaustive" runs only those. A focused run runs exactly what it named.
	if(!length(focused_tests))
		var/tier_param = world.params?[TEST_TIER_PARAMETER] || "normal"
		var/want_normal = tier_param != "exhaustive" && tier_param != "e0"
		var/want_exhaustive = tier_param == "all" || tier_param == "exhaustive"
		// The E0 proofs (TEST_TIER_E0) run only on `--tier=e0`: not in a plain run, not in `all`, so the normal suite stays green.
		var/want_e0 = tier_param == "e0"
		var/list/tiered = list()
		for(var/_test_to_run in tests_to_run)
			var/datum/unit_test/test_to_run = _test_to_run
			var/test_tier = initial(test_to_run.tier)
			if(test_tier == TEST_TIER_E0 ? want_e0 : (test_tier == TEST_TIER_EXHAUSTIVE ? want_exhaustive : want_normal))
				tiered += test_to_run
		log_test("Unit-test tier '[tier_param]': [length(tiered)] of [length(tests_to_run)] test types.")
		tests_to_run = tiered

	sortTim(tests_to_run, GLOBAL_PROC_REF(cmp_unit_test_priority))

	var/list/test_results = list()
	var/total_tests = length(tests_to_run)
	var/current_test_index = 0
	log_test("Unit-test suite starting: [total_tests] test types[LAZYLEN(focused_tests) ? " (focused run)" : ""].")
	unit_test_boot_gate()

	// Ownership framework checks (doc/rewrite/ownership.md): snapshot every frozen shared
	// definition and start the periodic owner-stamp audit before the first test. A finding is
	// reported as a runtime, which would otherwise unwind this proc and stop the suite silently
	// (the world then idles until the DreamDaemon watchdog): fail the run and carry on.
	var/list/framework_failures = list()
	try
		def_freeze_snapshot()
		own_audit_periodic()
	catch(var/exception/pre_e)
		framework_failures += "SUITE START: [pre_e.name] at [pre_e.file]:[pre_e.line]"
		log_test("OWNERSHIP FRAMEWORK CHECK at suite start: [pre_e.name] at [pre_e.file]:[pre_e.line] -- [pre_e.desc]")

	//Hell code, we're bound to end the round somehow so let's stop if from ending while we work
	SSticker.delay_end = TRUE
	for(var/unit_path in tests_to_run)
		CHECK_TICK //We check tick first because the unit test we run last may be so expensive that checking tick will lock up this loop forever
		current_test_index++
		// A runtime anywhere in RunUnitTest() outside the test's own Run()
		// (block release, cleanup of what the test left behind) would otherwise
		// unwind this loop into the OM trampoline's try/catch and stop the
		// suite silently. Fail the run and carry on with the next test.
		try
			RunUnitTest(unit_path, test_results, current_test_index, total_tests)
		catch(var/exception/e)
			GLOB.failed_any_test = TRUE
			GLOB.current_test = null
			log_world("::error::[TEST_OUTPUT_RED("FAIL")] [unit_path]: harness runtime: [e.name] at [e.file]:[e.line]")
			log_test("HARNESS RUNTIME in [unit_path]: [e.name] at [e.file]:[e.line] -- [e.desc]")
			test_results[unit_path] = list("status" = UNIT_TEST_FAILED, "message" = "harness runtime: [e.name] at [e.file]:[e.line]", "name" = unit_path, "duration_ds" = 0, "runtimes" = 1, "ticks" = null)
	SSticker.delay_end = FALSE
	// Ownership framework checks after the last test: a mutated shared definition or an
	// orphaned/stale owner stamp fails the run like a failed test, one line per finding.
	var/list/frozen = def_freeze_verify()
	var/list/orphans = own_audit(quiet = TRUE)
	for(var/line in frozen)
		framework_failures += "DEF FREEZE: [line]"
	for(var/line in orphans)
		framework_failures += "OWN AUDIT: [line]"
	for(var/line in framework_failures)
		GLOB.failed_any_test = TRUE
		log_world("::error::[TEST_OUTPUT_RED("FAIL")] [line]")
		log_test(line)
	if(length(framework_failures))
		test_results["ownership_framework_checks"] = list("status" = UNIT_TEST_FAILED, "message" = jointext(framework_failures, "\n"), "name" = "ownership_framework_checks", "duration_ds" = 0, "runtimes" = 0, "ticks" = null)
	if(length(GLOB.dq_refsearch_type_counts))
		var/list/searched = list()
		for(var/type in GLOB.dq_refsearch_type_counts)
			searched += "[type] x[GLOB.dq_refsearch_type_counts[type]][GLOB.dq_refsearch_skipped[type] ? " (+[GLOB.dq_refsearch_skipped[type]] skipped)" : ""]"
		log_test("Reference searches this run ([GLOB.dq_refsearch_spent_ds / 10]s): [jointext(searched, ", ")]")
	if(GLOB.e0_proofs_passed + GLOB.e0_proofs_pending + GLOB.e0_proofs_failed)
		log_test("E0 proofs: [GLOB.e0_proofs_passed] green, [GLOB.e0_proofs_pending] pending an engine (E1-E6 not implemented), [GLOB.e0_proofs_failed] failed for another reason.")
	log_test("Unit-test suite finished: [total_tests] test types, failures: [GLOB.failed_any_test ? "yes" : "no"].")

	// A sharded run gives each world its own results file (shard-tests-file's
	// world param sibling) so N concurrent worlds in one worktree don't
	// clobber each other's data/unit_tests.json; a plain run keeps the
	// well-known default path every existing caller reads.
	var/file_name = world.params[TEST_RESULTS_FILE_PARAMETER] || "data/unit_tests.json"
	fdel(file_name)
	file(file_name) << json_encode(test_results)

	SSticker.force_ending = ADMIN_FORCE_END_ROUND
	//We have to call this manually because del_text can preceed us, and SSticker doesn't fire in the post game
	SSticker.declare_completion()

/datum/map_template/unit_tests
	name = "Unit Tests Zone"
	mappath = "maps/templates/unit_tests.dmm"

/// Placeholder run when a test-focus file names no known test: fails loudly
/// instead of letting the world fall back to the full suite.
/datum/unit_test/dq_focus_named_nothing

/datum/unit_test/dq_focus_named_nothing/Run()
	if(!world.params?["test-focus"])
		return // the full suite: nothing to check
	TEST_FAIL("the test-focus file named no known /datum/unit_test type")
