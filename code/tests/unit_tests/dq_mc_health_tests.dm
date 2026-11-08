// The MC Health panel's data (code/content/client/mc_health.dm): every section the panel draws is there, the subsystems' usage is a share of
// the tick and not the old hard-coded 0, the churn read leaves the churn source's window alone, and the build is cheap.

/datum/unit_test/dq_mc_health_data
/datum/unit_test/dq_mc_health_data/Run()
	var/started = TICK_USAGE_REAL
	var/list/data = mc_health_data()
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	for(var/key in list("window_5s", "window_30s", "window_5m", "ticks", "outliers", "subsystems", "kernel", "gc", "entities", "churn", "runtime", "attribution"))
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
	test_driver_end()

/// The Advanced links name a controller; the server resolves the name, and nothing else.
/datum/unit_test/dq_mc_health_vv_names
/datum/unit_test/dq_mc_health_vv_names/Run()
	TEST_ASSERT_EQUAL(mc_health_vv_target("kernel"), Kernel, "kernel names the kernel")
	TEST_ASSERT_EQUAL(mc_health_vv_target("globals"), GLOB, "globals names GLOB")
	TEST_ASSERT_EQUAL(mc_health_vv_target("config"), config, "config names the configuration")
	TEST_ASSERT_NULL(mc_health_vv_target("[REF(Kernel)]"), "a ref is not a name")
	TEST_ASSERT_NULL(mc_health_vv_target("anything"), "nor is anything else")

/// Where a build of the panel data goes: each section timed alone, then a whole build (MC_HEALTH_COST lines).
/datum/unit_test/dq_mc_health_cost
/datum/unit_test/dq_mc_health_cost/Run()
	test_driver_begin()
	test_time(3 SECONDS)
	mc_health_data() // warm: the census and the lazy tables
	var/n = 10
	var/list/timings = list()
	var/started
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		Kernel.performance_window(5)
		Kernel.performance_window(30)
	timings["windows 5s+30s"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		Kernel.performance_window(300)
	timings["window 5m"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		mc_health_recent_ticks()
	timings["recent ticks"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		mc_health_subsystems()
	timings["subsystems"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/list/kernel_data
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		kernel_data = km_panel_data()
	timings["kernel systems"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/list/systems = kernel_data["systems"]
	var/list/shown = systems.Copy(1, min(length(systems), 8) + 1)
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		mc_health_attribution(shown)
	timings["attribution"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		mc_health_gc()
		mc_health_entities()
		mc_health_churn()
	timings["gc+entities+churn"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		mc_health_rust()
	timings["rust"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/list/fast
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		fast = mc_health_fast()
	timings["per-second build (fast sections; the slow ones kept)"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		json_encode(fast)
	timings["json of the per-second send"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	for(var/group in GLOB.mc_health_slow_groups)
		started = TICK_USAGE_REAL
		for(var/i in 1 to n)
			mc_health_slow_group(group)
		timings["slow group [group] (one per send, each every 5 s)"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		mc_health_attribution(shown)
	timings["attribution again"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		km_panel_data(8)
	timings["km_panel_data(8)"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/list/slow = mc_health_slow()
	TEST_NOTICE(src, "MC_HEALTH_COST bytes: per-second send [length(json_encode(fast))], slow sections [length(json_encode(slow))]")
	for(var/key in timings)
		TEST_NOTICE(src, "MC_HEALTH_COST [key]: [round(timings[key], 0.01)] ms")
	test_driver_end()
