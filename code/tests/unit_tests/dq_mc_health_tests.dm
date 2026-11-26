// The MC Health panel's data (code/content/client/mc_health.dm): every section the panel draws is there, the subsystems' usage is a share of
// the tick and not the old hard-coded 0, the churn read leaves the churn source's window alone, and the build is cheap.

/datum/unit_test/dq_mc_health_data
/datum/unit_test/dq_mc_health_data/Run()
	mc_health_data() // warm: the census and the lazy tables
	var/started = TICK_USAGE_REAL
	var/list/data = mc_health_data()
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	for(var/key in list("window_5s", "window_30s", "window_5m", "ticks", "outliers", "subsystems", "kernel", "gc", "entities", "churn", "runtime", "attribution", "attribution_rest"))
		TEST_ASSERT(!isnull(data[key]), "the panel data has [key]")
	TEST_ASSERT(length(data["ticks"]) <= 120, "at most 120 recent ticks")
	var/list/census = data["entities"]["census"]
	TEST_ASSERT(census["turfs"] == world.maxx * world.maxy * world.maxz, "the census counts every turf")
	TEST_ASSERT(census["areas"] > 0, "and the areas")
	var/fired = FALSE
	for(var/list/S as anything in data["subsystems"])
		if(S["cost"] > 0)
			fired = TRUE
			TEST_ASSERT(S["usage"] > 0, "[S["name"]] costs [S["cost"]] ms a fire, so its usage is not 0")
	TEST_ASSERT(fired, "some system has a measured cost")
	TEST_NOTICE(src, "MC Health data: built in [round(ms, 0.01)] ms, [length(json_encode(data))] bytes, census [census["ms"]] ms")

/datum/unit_test/dq_mc_health_churn_peek_keeps_window
/datum/unit_test/dq_mc_health_churn_peek_keeps_window/Run()
	var/datum/churn_census/census = GLOB.churn_census
	census.draws["dq_peek_test"] = (census.draws["dq_peek_test"] || 0) + 3
	var/list/top = mc_health_churn()["draw"]
	var/found = FALSE
	for(var/list/row as anything in top)
		if(row[1] == "dq_peek_test")
			found = TRUE
	TEST_ASSERT(found || length(top) == 5, "the peek lists the busiest draw keys")
	TEST_ASSERT_EQUAL(census.draws["dq_peek_test"], 3, "reading the churn for the panel leaves the window's counts in place")
	census.draws -= "dq_peek_test"

/// The panel's own Rust read (vg_verdigris_metrics_panel(), sampled gauges refreshed) carries the process memory and the frame histogram, with
/// no help from the server metrics source.
/datum/unit_test/dq_mc_health_rust_values
/datum/unit_test/dq_mc_health_rust_values/Run()
	test_driver_begin()
	test_time(2 SECONDS) // a few native frames
	var/list/rust = mc_health_rust()
	TEST_ASSERT_NOTNULL(rust, "the native library answered the panel's read")
	if(!rust)
		test_driver_end()
		return
	TEST_ASSERT(rust["process.working_set_bytes"] > 0, "the server process's memory reaches the payload ([rust["process.working_set_bytes"]])")
	var/list/frames = rust["frame.total_us"]
	TEST_ASSERT(islist(frames) && frames["count"] > 0, "the frame-time histogram reaches the payload")
	TEST_ASSERT(islist(frames) && length(frames["buckets"]) == length(frames["bounds"]) + 1, "with its buckets and bounds")
	TEST_ASSERT(!isnull(rust["alloc.heap.current_bytes"]), "the refreshed native heap total is there")
	var/fields = 0
	for(var/name in rust)
		if(findtext(name, "world.awake.field_") == 1)
			fields++
	TEST_ASSERT(fields > 0, "the fields' awake counts reach the payload, kept by the fields as they step")
	test_driver_end()

/// The Advanced links name a controller; the server resolves the name, and nothing else.
/datum/unit_test/dq_mc_health_vv_names
/datum/unit_test/dq_mc_health_vv_names/Run()
	TEST_ASSERT_EQUAL(mc_health_vv_target("kernel"), Kernel, "kernel names the kernel")
	TEST_ASSERT_EQUAL(mc_health_vv_target("globals"), GLOB, "globals names GLOB")
	TEST_ASSERT_EQUAL(mc_health_vv_target("config"), config, "config names the configuration")
	TEST_ASSERT_NULL(mc_health_vv_target("[REF(Kernel)]"), "a ref is not a name")
	TEST_ASSERT_NULL(mc_health_vv_target("anything"), "nor is anything else")

/// Where a build of the panel data goes: each group built in full, alone, and what one client's send costs (MC_HEALTH_COST lines).
/datum/unit_test/dq_mc_health_cost
/datum/unit_test/dq_mc_health_cost/Run()
	test_driver_begin()
	test_time(3 SECONDS)
	mc_health_data() // warm: the census and the lazy tables
	var/n = 10
	var/list/timings = list()
	for(var/group in GLOB.mc_health_groups)
		var/datum/mc_health_build/B = new
		B.systems = km_panel_data()["systems"]
		var/started = TICK_USAGE_REAL
		for(var/i in 1 to n)
			B.begin_group(group, TIME_NOW(CLOCK_WORLD))
			while(!mc_health_unit(B, INFINITY))
				;
		timings["group [group] in full"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/datum/mc_health_build/whole = new
	mc_health_build_all(whole)
	var/send_started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		whole.client_update(list(), "coord")
	timings["one client's whole send (the pieces joined)"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - send_started) / n
	TEST_NOTICE(src, "MC_HEALTH_COST bytes: whole payload [length(json_encode(whole.values))]")
	for(var/key in timings)
		TEST_NOTICE(src, "MC_HEALTH_COST [key]: [round(timings[key], 0.01)] ms")
	test_driver_end()

/// The staged build: pumped a fire at a time it finishes every group, no pump runs past its budget by more than one unit's overshoot, the slow groups are
/// walked in slices (the work counters show it), and a build with nothing due does nothing.
/datum/unit_test/dq_mc_health_pump_is_bounded
/datum/unit_test/dq_mc_health_pump_is_bounded/Run()
	test_driver_begin()
	test_time(2 SECONDS)
	var/datum/mc_health_build/B = new
	var/groups = length(GLOB.mc_health_groups)
	var/guard = 0
	var/long_pumps = 0
	while(B.groups_built < groups && guard++ < 600)
		var/spent = mc_health_pump(B)
		if(spent > MC_HEALTH_PUMP_MS + 6)
			long_pumps++
	TEST_ASSERT_EQUAL(B.groups_built, groups, "every group was built within [guard] pumps")
	// A native call or a stall of the machine can pass the budget, never most pumps: the cap is on the work (the slices), not on one clock reading.
	TEST_ASSERT(long_pumps * 10 <= guard, "[long_pumps] of [guard] pumps ran more than 6 ms past the [MC_HEALTH_PUMP_MS] ms budget")
	TEST_ASSERT(B.units <= guard * 40, "the units a pump runs are bounded ([B.units] units in [guard] pumps)")
	TEST_ASSERT(B.slices >= 5, "the walks ran in slices ([B.slices])")
	for(var/section in list("ticks", "header", "window_5s", "stalls", "window_30s", "window_5m", "outliers", "subsystems", "kernel", "ledger", "runtime", "attribution", "attribution_rest", "gc", "churn", "entities", "rust"))
		TEST_ASSERT(section in B.versions, "the section [section] was published")
	TEST_ASSERT_EQUAL(B.versions[1], "ticks", "the tick graph is the first section")
	TEST_NOTICE(src, "MC_HEALTH_PUMP: [guard] pumps, [B.units] units, [B.slices] slices walking [B.walked] rows or samples, dearest pump [round(B.max_pump_ms, 0.01)] ms, dearest unit [round(B.max_unit_ms, 0.01)] ms, dearest group [round(B.group_max_ms, 0.01)] ms")
	// Nothing is due right after: a pump does no work.
	var/units_before = B.units
	mc_health_pump(B)
	TEST_ASSERT_EQUAL(B.units, units_before, "a build with nothing due runs no unit")
	// A second later the fast group is due again, and only it.
	B.started_at[MC_GROUP_FAST] -= MC_HEALTH_FAST_EVERY + 1
	var/groups_before = B.groups_built
	mc_health_pump(B, 1000)
	TEST_ASSERT_EQUAL(B.groups_built, groups_before + 1, "after the fast period only the fast group is rebuilt")
	test_driver_end()

/// A client's turn: the first send is every section, joined from the pieces made when they were built and valid JSON; the next with nothing changed sends nothing;
/// a rebuilt section is the only one sent again; and a send costs far under MC_HEALTH_TURN_MS.
/datum/unit_test/dq_mc_health_client_send_is_cheap
/datum/unit_test/dq_mc_health_client_send_is_cheap/Run()
	var/datum/mc_health_build/B = new
	mc_health_build_all(B)
	var/list/sent = list()
	var/started = TICK_USAGE_REAL
	var/list/update = B.client_update(sent, "(1, 2, 3)")
	var/first_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT_NOTNULL(update, "a client that holds nothing is sent the panel")
	TEST_ASSERT(update["whole"], "whole")
	TEST_ASSERT_EQUAL(update["sections"], length(B.versions), "with every section")
	var/list/decoded = json_decode(url_decode(update["payload"]))
	TEST_ASSERT(islist(decoded) && islist(decoded["mc_metrics"]), "the payload is JSON with the sections")
	TEST_ASSERT_EQUAL(decoded["partial"], FALSE, "not partial")
	TEST_ASSERT_EQUAL(decoded["coord_entry"], "(1, 2, 3)", "with the client's coordinates")
	for(var/section in B.versions)
		TEST_ASSERT(!isnull(decoded["mc_metrics"][section]) || section == "rust", "[section] is in the payload")
	TEST_ASSERT(first_ms < MC_HEALTH_TURN_MS, "the whole first send took [round(first_ms, 0.01)] ms, over [MC_HEALTH_TURN_MS] ms")
	TEST_ASSERT_NULL(B.client_update(sent, "(1, 2, 3)"), "with nothing changed there is nothing to send")
	B.publish("header", list("tidi" = 0))
	started = TICK_USAGE_REAL
	update = B.client_update(sent, "(1, 2, 3)")
	var/next_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT_EQUAL(update["sections"], 1, "a rebuilt section is the only one sent again")
	TEST_ASSERT(!update["whole"], "and the send is partial")
	TEST_ASSERT(next_ms < MC_HEALTH_TURN_MS, "the partial send took [round(next_ms, 0.01)] ms, over [MC_HEALTH_TURN_MS] ms")
	update = B.client_update(sent, "(4, 5, 6)")
	TEST_ASSERT_EQUAL(update["sections"], 0, "a moved eye alone sends the coordinates only")
	// Another admin's send reuses the same pieces: no section is encoded again.
	var/version_before = B.version
	B.client_update(list(), "(1, 2, 3)")
	TEST_ASSERT_EQUAL(B.version, version_before, "a second client's send encodes nothing")
	TEST_NOTICE(src, "MC_HEALTH_SEND: whole [round(first_ms, 0.01)] ms, partial [round(next_ms, 0.01)] ms")

/// The attribution walk is cut by row, not by owner type: one type with thousands of rows is walked in slices that each end near their budget, every row is
/// visited exactly once, and the heaviest rows come out as a whole walk would find them.
/datum/unit_test/dq_mc_health_attribution_walk_is_sliced
/datum/unit_test/dq_mc_health_attribution_walk_is_sliced/Run()
	var/datum/km_attr/attr = new
	var/callback_rows = KA_MAX_ROWS - 40
	for(var/i in 1 to callback_rows)
		attr.note(KA_KIND_CALLBACK, KM_SYS_SCHED_CORE, "/datum/one_big_type", "proc_[i]", i / 1000)
	for(var/i in 1 to 30)
		attr.note(KA_KIND_DRAW, KM_SYS_APPEARANCE, "/obj/redrawn_[i]", "run", i)
	var/total_rows = callback_rows + 30
	var/datum/km_attr_sys_walk/W = attr.sys_walk_begin(5, list("[KM_SYS_SCHED_CORE]" = list("sched_core", 1)))
	// A spent budget (0 ms) ends a slice at the next check: the work of a slice is at most KA_WALK_CHECK_ROWS rows, however long the clock says it took.
	var/steps = 0
	var/most_rows = 0
	var/max_ms = 0
	var/done = FALSE
	while(!done && steps < 5000)
		var/visited_before = W.visited
		var/started = TICK_USAGE_REAL
		done = attr.sys_walk_step(W, 0)
		max_ms = max(max_ms, TICK_DELTA_TO_MS(TICK_USAGE_REAL - started))
		most_rows = max(most_rows, W.visited - visited_before)
		steps++
	TEST_ASSERT(done, "the walk ends")
	TEST_ASSERT_EQUAL(W.visited, total_rows, "every row is visited once")
	TEST_ASSERT(steps >= total_rows / KA_WALK_CHECK_ROWS, "one big type is walked in many slices ([steps])")
	TEST_ASSERT(most_rows <= KA_WALK_CHECK_ROWS, "a slice walked [most_rows] rows, past [KA_WALK_CHECK_ROWS]")
	TEST_NOTICE(src, "MC_HEALTH_ATTR_SLICES: [steps] slices of at most [most_rows] rows, the longest took [round(max_ms, 0.01)] ms")
	var/list/best = W.best["[KM_SYS_SCHED_CORE]"]
	TEST_ASSERT_EQUAL(length(best), 5, "five rows are kept")
	TEST_ASSERT_EQUAL(best[1][KA_B], "proc_[callback_rows]", "the heaviest is first")
	// The profiler's walk of the same table finds the same heaviest callback.
	var/datum/km_attr_walk/P = attr.walk_begin(5)
	var/profiler_steps = 0
	while(!attr.walk_step(P, 0) && profiler_steps < 5000)
		profiler_steps++
	TEST_ASSERT(profiler_steps >= total_rows / KA_WALK_CHECK_ROWS - 1, "the profiler's walk is sliced by row as well ([profiler_steps] slices)")
	TEST_ASSERT_EQUAL(P.visited, total_rows, "and visits every row once")
	TEST_ASSERT_EQUAL(P.call_best[1][KA_B], "proc_[callback_rows]", "and finds the heaviest callback")
	var/list/redrawn = attr.walk_result(P)["redrawn_types"]
	TEST_ASSERT_EQUAL(length(redrawn), 5, "the five heaviest redrawn types are ranked")
	TEST_ASSERT_EQUAL(redrawn[1]["type"], "/obj/redrawn_30", "heaviest first")
	TEST_ASSERT_EQUAL(redrawn[5]["type"], "/obj/redrawn_26", "and the fifth is the fifth")

/// The sample window walked in slices reads what performance_window() reads in one call.
/datum/unit_test/dq_mc_health_window_walk_matches_window
/datum/unit_test/dq_mc_health_window_walk_matches_window/Run()
	test_driver_begin()
	test_time(2 SECONDS)
	var/list/whole = Kernel.performance_window(30)
	var/datum/perf_window_walk/W = Kernel.performance_walk_begin(30)
	TEST_ASSERT_NOTNULL(W, "the kernel has samples")
	var/steps = 0
	while(!Kernel.performance_walk_step(W, 0) && steps < 10000)
		steps++
	TEST_ASSERT(steps >= whole["samples"] / 64 - 1, "a window is read 64 samples a slice at most ([steps] slices for [whole["samples"]] samples)")
	var/list/sliced = Kernel.performance_walk_result(W)
	TEST_ASSERT_EQUAL(sliced["samples"], whole["samples"], "the same number of samples")
	TEST_ASSERT_EQUAL(sliced["max"], whole["max"], "the same maximum")
	TEST_ASSERT_EQUAL(sliced["overruns"], whole["overruns"], "the same overruns")
	TEST_ASSERT_EQUAL(sliced["p95"], whole["p95"], "the same 95th percentile")
	TEST_NOTICE(src, "MC_HEALTH_WINDOW: [sliced["samples"]] samples in [steps + 1] slices")
	test_driver_end()

/// The churn read in slices finds what a whole read finds.
/datum/unit_test/dq_mc_health_churn_walk_is_sliced
/datum/unit_test/dq_mc_health_churn_walk_is_sliced/Run()
	var/datum/churn_census/census = GLOB.churn_census
	for(var/i in 1 to 200)
		census.draws["dq_slice_test_[i]"] = 1000000 + i // under 2^24, where a DM number still tells neighbours apart
	var/datum/mc_churn_walk/W = new
	W.kinds = census.peek()
	for(var/kind in W.kinds)
		W.names += kind
	var/steps = 0
	while(!mc_health_churn_step(W, 0) && steps < 1000)
		steps++
	TEST_ASSERT(steps >= 200 / KA_WALK_CHECK_ROWS - 1, "the keys are read in slices ([steps])")
	var/list/top = W.out["draw"]
	TEST_ASSERT_EQUAL(length(top), MC_HEALTH_CHURN_TOP, "the busiest keys are listed")
	TEST_ASSERT_EQUAL(top[1][1], "dq_slice_test_200", "heaviest first")
	TEST_ASSERT(W.visited >= 200, "every key was visited ([W.visited])")
	for(var/i in 1 to 200)
		census.draws -= "dq_slice_test_[i]"

/// A sample of the profiler is built in turns that are each short: none ends past the cap by more than one native call, and the native reads and the log writes
/// are a turn each.
/datum/unit_test/dq_profiler_sample_turns_are_capped
/datum/unit_test/dq_profiler_sample_turns_are_capped/Run()
	var/datum/system/profiler/P = SSprofiler
	rel_clear(P, nameof(P.building))
	rel_set(P, nameof(P.building), new /datum/profile_sample)
	var/datum/profile_sample/S = P.building
	S.started_real = REALTIMEOFDAY
	var/guard = 0
	var/worst = 0
	var/worst_stage = 0
	var/long_turns = 0
	while(S.stage <= PROFILE_STAGE_WRITE && guard++ < 1000)
		var/started = TICK_USAGE_REAL
		var/turn_stage = S.stage
		var/done = P.sample_stage(S)
		var/turn_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		if(turn_ms > worst)
			worst = turn_ms
			worst_stage = turn_stage
		if(turn_ms > PROFILE_TURN_CAP_MS * 3)
			long_turns++
		if(done)
			S.stage++
	rel_clear(P, nameof(P.building))
	TEST_ASSERT(S.stage > PROFILE_STAGE_WRITE, "the sample finished within [guard] turns")
	// A stall of the machine can lengthen a turn; most turns are within the cap.
	TEST_ASSERT(long_turns * 10 <= guard, "[long_turns] of [guard] turns took over [PROFILE_TURN_CAP_MS * 3] ms (the dearest, [round(worst, 0.01)] ms, was stage [worst_stage])")
	TEST_ASSERT(guard >= PROFILE_STAGE_WRITE + 4, "the native reads and the log writes are a turn each ([guard] turns)")
	TEST_NOTICE(src, "PROFILER_TURNS: [guard] turns, dearest [round(worst, 0.01)] ms (stage [worst_stage]), [long_turns] over [PROFILE_TURN_CAP_MS * 3] ms")
