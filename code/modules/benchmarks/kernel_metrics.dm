// Benchmark side of the kernel measurement (code/controllers/measure/): every scenario reports the same tick,
// per-system and input numbers, so a change can be judged by what it did to each system and to input latency.
//
//   tick_p50 / tick_p95 / tick_p99, overruns, overrun_ratio       whole-tick usage over the scenario's run
//   system.<id>.ms_per_s / .p99_ms / .late_max / .breaches        per system (the ids are km_systems keys)
//   input_p99 / input_p99_ticks / verb_queue_p99_ms / ...         player input wait (ms and ticks)
//
// RunBenchmarks() records them over each scenario's whole Run() (record_scenario_kernel_metrics()); a window
// (begin_window()/end_window()) records the same tick numbers under its own prefix.
// `bench-compare` gates on input_p99 and every .breaches (tools/build/lib/bench.ts).

/// Records the tick, per-system and input metrics of `stats_set` under `prefix` ("" for the scenario level).
/// `tick` is the performance_window() of the same span.
/datum/benchmark/proc/record_kernel_metrics(datum/km_stats_set/stats_set, list/tick, prefix = "")
	var/pre = prefix ? "[prefix]_" : ""
	metric("[pre]tick_p50", tick["p50"], "%")
	metric("[pre]tick_p95", tick["p95"], "%")
	metric("[pre]tick_p99", tick["p99"], "%")
	metric("[pre]overruns", tick["overruns"], "ticks")
	metric("[pre]overrun_ratio", tick["samples"] ? tick["overruns"] / tick["samples"] : 0, "ratio")
	var/list/systems = km_report_systems(stats_set, GLOB.om_live_sched)
	for(var/list/row as anything in systems)
		if(!row["ticks"] && !row["runs"])
			continue
		var/name = "[pre]system.[row["key"]]"
		metric("[name].ms_per_s", row["ms_per_s"], "ms/s")
		metric("[name].p99_ms", row["p99_ms"], "ms")
		metric("[name].late_max", row["late_max_ds"], "ds")
		metric("[name].breaches", row["breaches"], "breaches")
	var/list/input = km_report_input(stats_set)
	metric("[pre]input_p99", input["wait_p99_ms"], "ms")
	metric("[pre]input_p99_ticks", input["wait_p99_ticks"], "ticks")
	metric("[pre]input_p50", input["wait_p50_ms"], "ms")
	metric("[pre]click_wait_p99_ms", input["click_p99_ms"], "ms")
	metric("[pre]verb_queue_p99_ms", input["verb_p99_ms"], "ms")
	metric("[pre]input_run_depth_p95", input["depth_p95"], "%")
	metric("[pre]input_queue_hwm", input["queue_hwm"], "verbs")
	metric("[pre]input_samples", input["samples"], "inputs", "none")
	detail("[pre]kernel_systems", systems)
	detail("[pre]kernel_input", input)

/// The scenario-level record: `stats_set` and the tick samples from `run_start_position` on cover the whole Run().
/datum/benchmark/proc/record_scenario_kernel_metrics(datum/km_stats_set/stats_set, run_start_position, run_start_real)
	var/elapsed_seconds = max((REALTIMEOFDAY - run_start_real) * 0.1, 0.1)
	var/list/tick = Master.performance_window(elapsed_seconds, Master.perf_index_of(run_start_position))
	record_kernel_metrics(stats_set, tick)

/// Waits `seconds` of wall clock like wait_seconds(), and every tick of it sends `clicks` real clicks from a ghost
/// and queues `verbs` verbs, so the input latency record has data on a world with no clients.
/datum/benchmark/proc/wait_seconds_with_input(seconds, clicks = 2, verbs = 2)
	var/turf/floor = locate(/turf/simulated/floor)
	var/mob/observer/dead/clicker = new(floor)
	var/until = REALTIMEOFDAY + seconds * 10
	while(REALTIMEOFDAY < until)
		for(var/i in 1 to clicks)
			km_synthetic_click(clicker, floor)
		for(var/i in 1 to verbs)
			km_synthetic_verb()
		stoplag()
	qdel(clicker)
	count_metric("synthetic_verbs_run", GLOB.km_synthetic.verbs_run, "verbs", "none")

/// Writes the flight recorder (the last minute of ticks: usage, maptick, input cost, top systems) of the scenario that
/// just ran to data/bench/kernel_ticks/<scenario>.json, where `bench` collects it into data/bench/profiles/ so a
/// regression can be opened tick by tick.
/proc/km_write_tick_series(scenario_id)
	var/list/rows = list()
	for(var/list/entry as anything in km_meter().recorded_entries())
		var/list/row = list("tick" = entry[1], "time" = entry[2], "usage" = round(entry[3], 0.01), "maptick" = round(entry[4], 0.01))
		row["input_ms"] = round(entry[5], 0.001)
		row["streak"] = entry[6]
		row["top"] = entry[7]
		row["top_ms"] = entry[8]
		rows += list(row)
	var/path = "data/bench/kernel_ticks/[scenario_id].json"
	fdel(path)
	text2file(json_encode(rows), path)

/// What the measurement itself costs, so a change to it (or to the number of systems) is visible:
/// one charge(), one TICK_USAGE read pair, one histogram add, and one end_tick() over a busy tick.
/datum/benchmark/kernel_overhead
	id = "kernel_overhead"
	description = "Cost of the kernel measurement: a charge, a tick usage read pair, a histogram add, a closed tick"

/datum/benchmark/kernel_overhead/Run()
	var/calls = param("calls", 200000)
	var/datum/tick_meter/meter = new(KM_RING_LEN)
	var/idx = km_systems().index_for("km_overhead_bench", KM_KIND_OM, LANE_SIMULATION)
	var/timer_id = "km-overhead-bench"

	rustg_time_reset(timer_id)
	for(var/i in 1 to calls)
		var/sink = i
		sink++
	var/empty_us = rustg_time_microseconds(timer_id)

	rustg_time_reset(timer_id)
	for(var/i in 1 to calls)
		var/start = TICK_USAGE
		var/spent = TICK_USAGE_TO_MS(start)
		spent++
	var/reads_us = rustg_time_microseconds(timer_id) - empty_us

	rustg_time_reset(timer_id)
	for(var/i in 1 to calls)
		meter.charge(idx, 0.05)
		if(!(i % 40))
			// The tick's charges stay in the fixed lists; closing it clears them, as the MC does every tick.
			meter.end_tick(20, 0)
	var/charge_us = rustg_time_microseconds(timer_id) - empty_us

	var/datum/km_hist/hist = new
	rustg_time_reset(timer_id)
	for(var/i in 1 to calls)
		hist.add(i % 50 * 0.1)
	var/hist_us = rustg_time_microseconds(timer_id) - empty_us

	// A busy tick: every registered system charged once, then closed.
	var/systems = km_systems().count()
	var/ticks = max(round(calls / max(systems, 1) / 10), 200)
	rustg_time_reset(timer_id)
	for(var/i in 1 to ticks)
		for(var/system in 1 to systems)
			meter.charge(system, 0.5)
		meter.end_tick(60, 1)
	var/busy_us = rustg_time_microseconds(timer_id)

	metric("tick_usage_read_pair_ns", reads_us * 1000 / calls, "ns")
	metric("charge_ns", charge_us * 1000 / calls, "ns")
	metric("histogram_add_ns", hist_us * 1000 / calls, "ns")
	metric("busy_tick_us", busy_us / ticks, "us")
	metric("busy_tick_systems", systems, "systems", "none", "count")
	qdel(hist)
	qdel(meter)
