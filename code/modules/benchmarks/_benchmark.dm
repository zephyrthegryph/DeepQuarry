// Benchmark framework. Compiled only under -DBENCHMARK (the `bench` build
// target; see doc/testing.md). A benchmark build boots like a unit-test build,
// but RunUnitTests() hands over to RunBenchmarks(), which runs the scenarios
// named in the `bench` world parameter and writes data/bench/scenarios.json.
//
// Scenarios are /datum/benchmark subtypes with an `id`. Each reports numbers
// through metric() and structured context through detail(); the framework adds
// tick/overrun statistics, subsystem costs, memory readings and runtimes.
// Process memory comes from the external runner (tools/build/lib/bench.ts),
// which samples DreamDaemon and keeps data/bench/process.json current.

#define BENCHMARK_RESULTS_FILE "data/bench/scenarios.json"
#define BENCHMARK_PROCESS_FILE "data/bench/process.json"

/datum/benchmark
	/// Scenario name used on the command line. Types without an id are abstract.
	var/id
	var/description = ""
	/// Included when `bench` runs without a scenario list.
	var/default_scenario = FALSE
	var/list/metrics = list()
	var/list/details = list()
	var/list/phases
	/// World parameters for this run; scenario options are `bench_<name>=value`.
	var/list/params
	/// Set by `bench_profile=1`: wrap each window in the BYOND proc profiler.
	var/profiling = FALSE
	var/window_start_position
	var/window_start_time
	var/list/window_subsystem_fires
	/// SSreactor.total_wakes when the window began.
	var/window_reactor_wakes = 0

/// The scenario body. Call fail() to abort with a reason.
/datum/benchmark/proc/Run()
	return

/// Records a scalar measurement. `better` is "lower", "higher" or "none"; it
/// drives regression detection in `bench-compare`.
/datum/benchmark/proc/metric(name, value, unit = "", better = "lower")
	metrics[name] = list("value" = value, "unit" = unit, "better" = better)

/// Records structured context that isn't compared (tables, breakdowns).
/datum/benchmark/proc/detail(name, value)
	details[name] = value

/// Reads a scenario option from the `bench_<name>` world parameter.
/datum/benchmark/proc/param(name, default_value)
	var/value = params?["bench_[name]"]
	if(isnull(value))
		return default_value
	if(isnum(default_value))
		var/number = text2num(value)
		return isnull(number) ? default_value : number
	return value

/datum/benchmark/proc/fail(reason)
	CRASH("benchmark [id] failed: [reason]")

/// Waits for deferred asset generation so it isn't measured as scenario work.
/datum/benchmark/proc/wait_for_assets(timeout_seconds = 120)
	var/waited = 0
	while((length(SSasset_loading.generate_queue) || SSasset_loading.assets_generating || SSasset_loading.last_queue_len) && waited++ < world.fps * timeout_seconds)
		stoplag()
	if(waited >= world.fps * timeout_seconds)
		fail("deferred assets did not settle within [timeout_seconds]s")

/// Sleeps until `subsystem` has fired `count` more times.
/datum/benchmark/proc/wait_fires(datum/controller/subsystem/subsystem, count, timeout_seconds = 300)
	var/target = subsystem.times_fired + count
	var/deadline = REALTIMEOFDAY + timeout_seconds * 10
	while(subsystem.times_fired < target)
		if(REALTIMEOFDAY > deadline)
			fail("[subsystem.name] fired [count - (target - subsystem.times_fired)]/[count] times in [timeout_seconds]s")
		stoplag()

/datum/benchmark/proc/wait_seconds(seconds)
	var/until = REALTIMEOFDAY + seconds * 10
	while(REALTIMEOFDAY < until)
		stoplag()

/// Starts a measurement window. Pair with end_window().
/datum/benchmark/proc/begin_window()
	stoplag() // start on a fresh tick so setup work isn't counted
	Master.perf_outliers.Cut()
	Master.perf_worst_tick = list()
	window_start_position = Master.perf_samples_total + 1
	window_start_time = REALTIMEOFDAY
	window_subsystem_fires = list()
	window_reactor_wakes = SSreactor.total_wakes
	for(var/datum/controller/subsystem/subsystem as anything in Master.subsystems)
		window_subsystem_fires[subsystem] = subsystem.times_fired
	if(profiling)
		world.Profile(PROFILE_CLEAR) // each window's dump covers only that window
		world.Profile(PROFILE_CLEAR, type = "sendmaps")
		SSprofiler.StartProfiling()

/// Ends a window and records tick, overrun and subsystem statistics under `prefix`.
/datum/benchmark/proc/end_window(prefix = "window")
	var/elapsed_seconds = max((REALTIMEOFDAY - window_start_time) * 0.1, 0.1)
	var/list/tick = Master.performance_window(elapsed_seconds, Master.perf_index_of(window_start_position))
	metric("[prefix]_seconds", elapsed_seconds, "s", "none")
	metric("[prefix]_tick_avg", tick["avg"], "%")
	metric("[prefix]_tick_p95", tick["p95"], "%")
	metric("[prefix]_tick_p99", tick["p99"], "%")
	metric("[prefix]_tick_max", tick["max"], "%")
	metric("[prefix]_overruns", tick["overruns"], "ticks")
	metric("[prefix]_overrun_ratio", tick["samples"] ? tick["overruns"] / tick["samples"] : 0, "ratio")
	metric("[prefix]_tps", tick["tps"], "tps", "higher")
	var/list/subsystems = list()
	for(var/datum/controller/subsystem/subsystem as anything in window_subsystem_fires)
		var/fires = subsystem.times_fired - window_subsystem_fires[subsystem]
		if(!fires)
			continue
		subsystems[subsystem.name] = list(
			"fires" = fires,
			"avg_cost_ms" = subsystem.cost,
			"estimated_total_ms" = subsystem.cost * fires,
			"tick_usage" = subsystem.tick_usage,
			"tick_overrun" = subsystem.tick_overrun,
		)
	detail("[prefix]_subsystems", subsystems)
	// Reactor wake reasons by type (cumulative since boot) and this window's wake count.
	var/list/reactor = SSreactor.performance_diagnostics()
	reactor["window_wakes"] = SSreactor.total_wakes - window_reactor_wakes
	metric("[prefix]_reactor_wakes", reactor["window_wakes"], "wakes", "lower")
	detail("[prefix]_reactor", reactor)
	detail("[prefix]_outliers", Master.perf_outliers.Copy())
	detail("[prefix]_worst_tick", LAZYCOPY(Master.perf_worst_tick))
	if(profiling)
		SSprofiler.StopProfiling()
		SSprofiler.DumpFile(allow_yield = FALSE)
	return tick

/// Records a named point in time with process memory and every Rust metric.
/datum/benchmark/proc/mark(name)
	var/list/process = benchmark_process_memory()
	var/list/rust = verdigris_metrics_list()
	LAZYADD(phases, list(list()
		"name" = name,
		"world_time" = world.time,
		"realtime" = REALTIMEOFDAY,
		"process" = process,
		"rust" = rust,
	))
	if(islist(process) && !isnull(process["private_mb"]))
		metric("[name]_private_mb", process["private_mb"], "MB")
	if(!islist(rust))
		return
	if(!isnull(rust["alloc.heap.current_bytes"]))
		metric("[name]_rust_heap_mb", rust["alloc.heap.current_bytes"] / (1024 * 1024), "MB")
		metric("[name]_rust_heap_peak_mb", rust["alloc.heap.peak_bytes"] / (1024 * 1024), "MB")
	// Per-domain Rust heap from the allocator tags (alloc.<tag>.current_bytes).
	for(var/key in rust)
		if(findtext(key, "alloc.") != 1 || findtext(key, ".current_bytes") != length(key) - 13)
			continue
		var/tag = copytext(key, 7, length(key) - 13)
		if(tag == "heap" || tag == "total" || !rust[key])
			continue
		metric("[name]_rust_[tag]_mb", rust[key] / (1024 * 1024), "MB")

/// Latest DreamDaemon memory sample written by the runner, or null.
/proc/benchmark_process_memory()
	if(!fexists(BENCHMARK_PROCESS_FILE))
		return null
	var/text = file2text(BENCHMARK_PROCESS_FILE)
	if(!length(text))
		return null
	var/list/decoded
	try
		decoded = json_decode(text)
	catch
		return null
	return decoded

/// Counts live instances by type. Walking every datum takes seconds on the
/// full map, so only memory scenarios call this.
/proc/benchmark_census(top = 40)
	var/list/by_type = list()
	var/total = 0
	for(var/datum/thing)
		total++
		by_type[thing.type]++
		CHECK_TICK
	for(var/atom/thing in world)
		total++
		by_type[thing.type]++
		CHECK_TICK
	var/list/by_root = list("area" = 0, "turf" = 0, "obj" = 0, "mob" = 0, "other_movable" = 0, "datum" = 0)
	for(var/path in by_type)
		var/count = by_type[path]
		if(ispath(path, /area))
			by_root["area"] += count
		else if(ispath(path, /turf))
			by_root["turf"] += count
		else if(ispath(path, /obj))
			by_root["obj"] += count
		else if(ispath(path, /mob))
			by_root["mob"] += count
		else if(ispath(path, /atom/movable))
			by_root["other_movable"] += count
		else
			by_root["datum"] += count
	var/list/top_types = list()
	for(var/path in by_type)
		var/count = by_type[path]
		var/insert_at = 1
		while(insert_at <= length(top_types) && by_type[top_types[insert_at]] >= count)
			insert_at++
		if(insert_at > top)
			continue
		top_types.Insert(insert_at, path)
		if(length(top_types) > top)
			top_types.Cut(top + 1)
	var/list/top_counts = list()
	for(var/path in top_types)
		top_counts["[path]"] = by_type[path]
	return list("total" = total, "distinct_types" = length(by_type), "by_root" = by_root, "top_types" = top_counts)

/// Counts the distinct lists held in instance vars, by owning type and var.
/// Built-in lists (contents, overlays, verbs...) are skipped. A list shared by
/// several instances counts once, against the first holder seen.
/proc/benchmark_var_lists(top = 60)
	var/static/list/skip = list("vars" = TRUE, "contents" = TRUE, "overlays" = TRUE, "underlays" = TRUE, "verbs" = TRUE, "vis_contents" = TRUE, "vis_locs" = TRUE, "locs" = TRUE, "filters" = TRUE, "screen" = TRUE, "images" = TRUE, "group" = TRUE, "client_images" = TRUE, "transform" = TRUE)
	var/list/seen = list()
	var/list/by_key = list()
	var/total = 0
	var/empty = 0
	var/entries = 0
	var/list/holders = list()
	for(var/datum/thing)
		holders += thing
	for(var/atom/thing in world)
		holders += thing
	for(var/datum/thing as anything in holders)
		for(var/name in thing.vars)
			if(skip[name])
				continue
			var/list/value = thing.vars[name]
			if(!islist(value))
				continue
			var/key = ref(value)
			if(seen[key])
				continue
			seen[key] = TRUE
			total++
			var/len = length(value)
			entries += len
			if(!len)
				empty++
			by_key["[thing.type].[name]"]++
		CHECK_TICK
	holders.Cut()
	by_key = sortTim(by_key, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(by_key) > top)
		by_key.Cut(top + 1)
	return list("total" = total, "empty" = empty, "entries" = entries, "top" = by_key)

/// Compiled type counts; every type costs memory whether or not it's instanced.
/proc/benchmark_type_counts()
	var/atoms = length(typesof(/atom))
	return list(
		"area" = length(typesof(/area)),
		"turf" = length(typesof(/turf)),
		"obj" = length(typesof(/obj)),
		"mob" = length(typesof(/mob)),
		"atom" = atoms,
		"datum" = length(typesof(/datum)) - atoms,
	)

/proc/benchmark_subsystem_init_times()
	var/list/times = list()
	for(var/datum/controller/subsystem/subsystem as anything in Master.subsystems)
		if(subsystem.init_time_ms)
			times[subsystem.name] = subsystem.init_time_ms
	return times

/proc/RunBenchmarks()
	CHECK_TICK
	// Same isolation as RunUnitTests: mapped patrol bots add unrelated load.
	for(var/mob/living/bot/map_bot in world)
		qdel(map_bot)
	SSticker.delay_end = TRUE

	var/list/params = world.params
	var/list/available = list()
	for(var/datum/benchmark/path as anything in subtypesof(/datum/benchmark))
		if(initial(path.id))
			available[initial(path.id)] = path

	var/list/requested = list()
	var/requested_text = params["bench"]
	if(!length(requested_text) || requested_text == "default")
		for(var/scenario_id in available)
			var/datum/benchmark/path = available[scenario_id]
			if(initial(path.default_scenario))
				requested += scenario_id
	else if(requested_text == "all")
		requested = available.Copy()
	else
		requested = splittext(requested_text, ",")

	var/list/results = list()
	var/list/unit_results = list()
	log_test("Benchmark run starting: [jointext(requested, ", ")]")
	for(var/scenario_id in requested)
		var/datum/benchmark/path = available[scenario_id]
		var/list/result = list("id" = scenario_id)
		if(!path)
			result["status"] = "unknown"
			result["error"] = "No benchmark with id '[scenario_id]'. Available: [jointext(available, ", ")]"
			GLOB.failed_any_test = TRUE
			log_test("::error::Unknown benchmark '[scenario_id]'")
		else
			var/datum/benchmark/scenario = new path
			scenario.params = params
			scenario.profiling = !!text2num(params["bench_profile"] || "0")
			result["description"] = scenario.description
			var/runtimes_before = GLOB.total_runtimes
			var/start = REALTIMEOFDAY
			log_test("Benchmark [scenario_id]: running")
			try
				scenario.Run()
				result["status"] = "passed"
			catch(var/exception/error)
				result["status"] = "failed"
				result["error"] = "[error.name] ([error.file]:[error.line])"
				GLOB.failed_any_test = TRUE
				log_test("::error::Benchmark [scenario_id] failed: [error.name]")
			result["duration_seconds"] = (REALTIMEOFDAY - start) / 10
			result["runtimes"] = GLOB.total_runtimes - runtimes_before
			result["metrics"] = scenario.metrics
			result["details"] = scenario.details
			result["phases"] = (scenario.phases || list())
			log_test("Benchmark [scenario_id]: [result["status"]] in [result["duration_seconds"]]s, [length(scenario.metrics)] metrics")
			qdel(scenario)
		results[scenario_id] = result
		unit_results["/datum/benchmark/[scenario_id]"] = list(
			"status" = result["status"] == "passed" ? UNIT_TEST_PASSED : UNIT_TEST_FAILED,
			"message" = result["error"] || "",
			"name" = "/datum/benchmark/[scenario_id]",
			"duration_ds" = (result["duration_seconds"] || 0) * 10,
		)
	SSticker.delay_end = FALSE

	var/list/document = list(
		"byond_version" = "[world.byond_version].[world.byond_build]",
		"map" = using_map?.name,
		"world" = list("maxx" = world.maxx, "maxy" = world.maxy, "maxz" = world.maxz, "fps" = world.fps),
		"init_seconds" = Master.initializations_seconds,
		"subsystem_init_ms" = benchmark_subsystem_init_times(),
		"total_runtimes" = GLOB.total_runtimes,
		"scenarios" = results,
	)
	fdel(BENCHMARK_RESULTS_FILE)
	text2file(json_encode(document), BENCHMARK_RESULTS_FILE)
	// The runner's watchdog waits on unit_tests.json, as for dm-test.
	fdel("data/unit_tests.json")
	file("data/unit_tests.json") << json_encode(unit_results)
	log_test("Benchmark run finished.")
	SSticker.force_ending = ADMIN_FORCE_END_ROUND
	SSticker.declare_completion()

#undef BENCHMARK_RESULTS_FILE
#undef BENCHMARK_PROCESS_FILE
