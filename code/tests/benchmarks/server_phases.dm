// One boot, four phases, CPU and memory in each: startup, idle, a supermatter-sized blast, and what the world looks like after it.
//   DQ_BENCH_CONFIG_DIR=config/example tools/build/build.sh bench --scenario=server_phases -DCITESTING_FULL_MAP [--arg=idle=300] [--arg=post=300] [--profile]
//   python tools/ci/bench_phases_report.py [run.json]
// A blast defaults to the numbers of a minimum-power delamination (explode_effects() in supermatter.dm: 6/12/24/48), since the live map has no crystal to detonate.

/datum/benchmark/server_phases
	id = "server_phases"
	description = "Startup, idle, supermatter-sized explosion and post-explosion, each with CPU, machine load and memory"
	/// CPU seconds and wall time at the start of the open phase, from the runner's sampler.
	var/phase_cpu = 0
	var/phase_real = 0
	var/phase_world_time = 0
	/// work_counts() when the phase opened.
	var/list/phase_work

/datum/benchmark/server_phases/proc/sample_field(field, default_value = 0)
	var/list/process = benchmark_process_memory()
	if(!islist(process) || isnull(process[field]))
		return default_value
	return process[field]

/datum/benchmark/server_phases/proc/open_phase()
	GLOB.churn_census.take()
	phase_work = work_counts()
	phase_cpu = sample_field("cpu_seconds")
	phase_real = REALTIMEOFDAY
	phase_world_time = world.time

/// The world's CPU share (100 = one core, all threads), the machine's load and the time dilation since open_phase().
/datum/benchmark/server_phases/proc/close_phase(prefix)
	work_metrics(prefix, phase_work)
	var/real_ds = max(REALTIMEOFDAY - phase_real, 1)
	metric("[prefix]_dd_cpu_pct", (sample_field("cpu_seconds") - phase_cpu) * 1000 / real_ds, "%")
	metric("[prefix]_machine_cpu_pct", sample_field("machine_cpu_pct"), "%", "none")
	metric("[prefix]_tidi_pct", max(0, 100 - (world.time - phase_world_time) * 100 / real_ds), "%")
	metric("[prefix]_private_mb", sample_field("private_mb"), "MB")
	metric("[prefix]_working_set_mb", sample_field("working_set_mb"), "MB")
	var/list/rust = vg_verdigris_allocator_diagnostics()
	if(islist(rust))
		count_metric("[prefix]_rust_heap_mb", rust[1] / 1048576, "MB")

/datum/benchmark/server_phases/proc/census_metrics(prefix)
	var/list/census = benchmark_census(param("top", 40))
	count_metric("[prefix]_instances_total", census["total"], "instances")
	for(var/root in census["by_root"])
		count_metric("[prefix]_instances_[root]", census["by_root"][root], "instances")
	detail("[prefix]_census_top", census["top_types"])
	return census

/datum/benchmark/server_phases/proc/blast_center()
	var/area_name = param("area", "Central Hallway")
	for(var/area/A in world)
		if(!findtext(A.name, area_name))
			continue
		var/list/turfs = list()
		for(var/turf/T in A)
			turfs += T
		if(length(turfs))
			return turfs[round(length(turfs) / 2) + 1]
	return null

/datum/benchmark/server_phases/Run()
	// Startup. The world has reached here without ever yielding to a benchmark, so the sampler's numbers so far are the boot's.
	work_metrics("startup", null)
	metric("startup_launch_to_ready_s", sample_field("t"), "s")
	metric("startup_cpu_s", sample_field("cpu_seconds"), "s")
	metric("startup_peak_private_mb", sample_field("peak_private_mb"), "MB")
	metric("startup_machine_cpu_pct", sample_field("mean_machine_cpu_pct"), "%", "none")
	metric("startup_init_s", Kernel.initializations_seconds, "s")
	// Before init: the spawn stamp (launch_tod, set by the harness), global variables, then the compiled map, then world/New().
	var/launch_tod = text2num(world.params?["launch_tod"] || "0")
	if(launch_tod && boot_globals_started_tod)
		metric("startup_spawn_to_globals_s", (boot_globals_started_tod - launch_tod) / 10, "s")
		metric("startup_globals_s", (boot_globals_done_tod - boot_globals_started_tod) / 10, "s")
		metric("startup_globals_to_world_new_s", (boot_world_new_tod - boot_globals_done_tod) / 10, "s")
	for(var/step in Kernel.boot_tail_ds)
		metric("startup_tail_[step]_s", Kernel.boot_tail_ds[step] / 10, "s")
	detail("early_notes", benchmark_early_notes)
	var/list/systems = benchmark_subsystem_init_times()
	for(var/name in systems)
		metric("startup_init_ms_[name]", systems[name], "ms")
	wait_for_assets()
	wait_fires(SSair, 10)
	open_phase()
	wait_seconds(param("settle", 60))
	close_phase("settled")
	census_metrics("settled")

	// What one log entry's world state costs, called apart from the file write: every log line pays it.
	var/probe_start = TICK_USAGE
	for(var/i in 1 to 200)
		world.get_world_state_for_logging()
	metric("log_world_state_us", TICK_USAGE_TO_MS(probe_start) * 1000 / 200, "us")
	probe_start = TICK_USAGE
	for(var/i in 1 to 200)
		logger.human_readable_timestamp()
	metric("log_timestamp_us", TICK_USAGE_TO_MS(probe_start) * 1000 / 200, "us")

	// Idle: tick cost, TiDi, memory growth.
	mark("idle_start")
	var/idle_seconds = param("idle", 300)
	var/list/series = list()
	var/idle_first_mb = sample_field("private_mb")
	var/waited = 0
	// --arg=attribute=1: where the idle time goes, by system and by timer callback. The census adds a little cost to each timer, so its runs are not baselines.
	var/attribute = param("attribute", 0)
	if(attribute)
		GLOB.census_on = TRUE
		census_report(TRUE)
		km_meter().live.reset()
	open_phase()
	begin_window()
	while(waited < idle_seconds)
		wait_seconds(30)
		waited += 30
		series += list(list("t" = waited, "private_mb" = sample_field("private_mb")))
	var/list/idle_tick = end_window("idle")
	close_phase("idle")
	if(attribute)
		GLOB.census_on = FALSE
		var/list/km_report = km_diagnostics(GLOB.om_live_sched)
		km_report["elapsed_s"] = km_meter().live.elapsed_seconds()
		detail("idle_km_systems", km_report["systems"])
		detail("idle_km_elapsed_s", km_report["elapsed_s"])
		detail("idle_census", census_report(TRUE))
	mark("idle_end")
	metric("idle_growth_mb_per_min", (sample_field("private_mb") - idle_first_mb) * 60 / idle_seconds, "MB/min")
	detail("idle_memory_series", series)

	// Explosion: wall time to settle, the longest gap between two ticks of this loop, the worst tick.
	var/turf/center = blast_center()
	if(!center)
		fail("no area to centre the blast on")
	detail("site", list("x" = center.x, "y" = center.y, "z" = center.z, "area" = "[get_area(center)]"))
	census_metrics("before")
	var/before_mb = sample_field("private_mb")
	var/peak_mb = before_mb
	var/list/heap_before = vg_verdigris_allocator_diagnostics()
	var/list/garbage_before = SSgarbage.performance_diagnostics()["totals"]
	open_phase()
	begin_window()
	var/start = REALTIMEOFDAY
	var/last = start
	var/stall = 0
	var/power = param("power", 12)
	explosion(center, power / 2, power, power * 2, power * 4, 1)
	var/deadline = start + 600 SECONDS
	var/next_sample = 0
	while((explosions_awake() || SSexplosions.pending_blast_count()) && REALTIMEOFDAY < deadline)
		stoplag()
		stall = max(stall, REALTIMEOFDAY - last)
		last = REALTIMEOFDAY
		// The sampler writes once a second: reading its file every tick would be this bench's own stall.
		if(REALTIMEOFDAY >= next_sample)
			next_sample = REALTIMEOFDAY + 1 SECONDS
			peak_mb = max(peak_mb, sample_field("private_mb"))
	metric("explosion_settle_s", (REALTIMEOFDAY - start) * 0.1, "s")
	metric("explosion_longest_stall_s", stall * 0.1, "s")
	count_metric("explosion_settled", explosions_awake() ? 0 : 1, "")
	end_window("explosion")
	close_phase("explosion")
	detail("explosion_profile", SSexplosions.performance_diagnostics())

	// Post-explosion: seconds until two 5 s slices run at or under 1.25x the idle mean, then the same window length as idle.
	var/target = max(idle_tick["avg"] * 1.25, idle_tick["avg"] + 1)
	var/recovery_start = REALTIMEOFDAY
	var/good = 0
	var/list/slices = list()
	while(good < 2 && REALTIMEOFDAY < recovery_start + 300 SECONDS)
		var/slice_position = Kernel.perf_samples_total + 1
		wait_seconds(5)
		var/list/slice = Kernel.performance_window(5, Kernel.perf_index_of(slice_position))
		slices += slice["avg"]
		good = slice["avg"] <= target ? good + 1 : 0
		peak_mb = max(peak_mb, sample_field("private_mb"))
	metric("post_recovery_s", (REALTIMEOFDAY - recovery_start) * 0.1, "s")
	detail("post_recovery_slices", slices)
	open_phase()
	begin_window()
	wait_seconds(param("post", 300))
	end_window("post")
	close_phase("post")
	var/after_mb = sample_field("private_mb")
	metric("post_peak_private_mb", max(peak_mb, after_mb), "MB")
	metric("post_retained_mb", after_mb - before_mb, "MB")
	if(islist(heap_before))
		count_metric("post_rust_retained_mb", (vg_verdigris_allocator_diagnostics()[1] - heap_before[1]) / 1048576, "MB")
	census_metrics("post")
	var/list/garbage = SSgarbage.performance_diagnostics()
	count_metric("post_gc_collected", garbage["totals"]["collected"] - garbage_before["collected"], "datums", "none")
	count_metric("post_hard_deletes", garbage["totals"]["hard_delete_count"] - garbage_before["hard_delete_count"], "deletes")
	detail("garbage", garbage)
	if(param("second_blast", 0))
		second_blast(center, power)

/// The same blast one deck up, then the same wait: what grows again is per-blast, what does not was made once. A leak shows as the second delta matching the first.
/datum/benchmark/server_phases/proc/second_blast(turf/first, power)
	var/turf/center = param("second_same", 0) ? first : locate(first.x, first.y, first.z + 1)
	if(!center)
		fail("no deck above the first blast")
	census_metrics("second_before")
	var/before_mb = sample_field("private_mb")
	var/start = REALTIMEOFDAY
	explosion(center, power / 2, power, power * 2, power * 4, 1)
	var/deadline = start + 600 SECONDS
	while((explosions_awake() || SSexplosions.pending_blast_count()) && REALTIMEOFDAY < deadline)
		stoplag()
	metric("second_settle_s", (REALTIMEOFDAY - start) * 0.1, "s")
	wait_seconds(param("post", 300))
	metric("second_retained_mb", sample_field("private_mb") - before_mb, "MB")
	census_metrics("second_post")
