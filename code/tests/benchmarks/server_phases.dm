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

/datum/benchmark/server_phases/proc/sample_field(field, default_value = 0)
	var/list/process = benchmark_process_memory()
	if(!islist(process) || isnull(process[field]))
		return default_value
	return process[field]

/datum/benchmark/server_phases/proc/open_phase()
	phase_cpu = sample_field("cpu_seconds")
	phase_real = REALTIMEOFDAY
	phase_world_time = world.time

/// The world's CPU share (100 = one core, all threads), the machine's load and the time dilation since open_phase().
/datum/benchmark/server_phases/proc/close_phase(prefix)
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
	metric("startup_launch_to_ready_s", sample_field("t"), "s")
	metric("startup_cpu_s", sample_field("cpu_seconds"), "s")
	metric("startup_peak_private_mb", sample_field("peak_private_mb"), "MB")
	metric("startup_machine_cpu_pct", sample_field("mean_machine_cpu_pct"), "%", "none")
	metric("startup_init_s", Kernel.initializations_seconds, "s")
	var/list/systems = benchmark_subsystem_init_times()
	for(var/name in systems)
		metric("startup_init_ms_[name]", systems[name], "ms")
	wait_for_assets()
	wait_fires(SSair, 10)
	open_phase()
	wait_seconds(param("settle", 60))
	close_phase("settled")
	census_metrics("settled")

	// Idle: tick cost, TiDi, memory growth.
	var/idle_seconds = param("idle", 300)
	var/list/series = list()
	var/idle_first_mb = sample_field("private_mb")
	var/waited = 0
	open_phase()
	begin_window()
	while(waited < idle_seconds)
		wait_seconds(30)
		waited += 30
		series += list(list("t" = waited, "private_mb" = sample_field("private_mb")))
	var/list/idle_tick = end_window("idle")
	close_phase("idle")
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
	while((explosions_awake() || SSexplosions.pending_blast_count()) && REALTIMEOFDAY < deadline)
		stoplag()
		stall = max(stall, REALTIMEOFDAY - last)
		last = REALTIMEOFDAY
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
