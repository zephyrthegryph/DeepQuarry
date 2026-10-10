SYSTEM_DEF(profiler)
	name = "Profiler"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	init_stage = INITSTAGE_FIRST
	periodic_runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	wait = 1 MINUTES
	var/fetch_cost = 0
	var/write_cost = 0
	/// Monotonic identifier for compact diagnostic snapshots. This profiler is
	/// intentionally independent of BYOND's expensive full proc serializer.
	var/diagnostic_sequence = 0

/datum/system/profiler/stat_entry(msg)
	msg += "F:[round(fetch_cost,1)]ms"
	msg += "|W:[round(write_cost,1)]ms"
	return msg

/datum/system/profiler/initialize()
	#ifdef BENCHMARK
	// `bench --profile`: profile the rest of boot too (Profiler initializes in
	// INITSTAGE_FIRST, before map load); boot_profile dumps it.
	var/bench_profile = text2num(world.params?["bench_profile"] || "0")
	#else
	var/bench_profile = FALSE
	#endif
	if(CONFIG_GET(flag/auto_profile) || bench_profile)
		StartProfiling()
	else
		StopProfiling() //Stop the early start profiler
	apply_interval()
	// AUTO_PROFILE controls full world.Profile collection only. Compact subsystem
	// diagnostics are cheap, bounded, and must continue even when it is disabled.
	can_fire = TRUE
	return

/datum/system/profiler/OnConfigLoad()
	if(CONFIG_GET(flag/auto_profile))
		StartProfiling()
	else
		StopProfiling()
	can_fire = TRUE
	apply_interval()

/// The compact diagnostics record (phase K, one run per `wait`: the item is declared at the default and takes the configured
/// interval at boot and on a config reload).
/datum/system/profiler/reactions()
	. = ..()
	. += every(1 MINUTES, PROC_REF(sample), phase = KERNEL_PHASE_K, when = PROC_REF(work_ready), lane = LANE_URGENT)

/// Applies the configured sample interval to the work item.
/datum/system/profiler/proc/apply_interval()
	wait = CONFIG_GET(number/profiler_interval)
	set_work_interval(PROC_REF(sample), wait)

/datum/system/profiler/proc/sample(dt)
	// Full BYOND profile serialization is synchronous and can itself overrun a tick.
	// Periodic collection therefore records only the inexpensive native diagnostics;
	// profile dumps are requested explicitly or by the MC drift outlier detector.
	var/list/atmos_arena = vg_auxmos_diagnostics()
	var/list/rust_allocator = vg_verdigris_allocator_diagnostics()
	// Every Rust metric (allocator tags, jobs, ...) in one call.
	var/list/rust_metrics = verdigris_metrics_list()
	var/list/subsystems = list(
		"atmos" = system_diagnostics(SSair),
		"machines" = system_diagnostics(SSmachines),
		"mobs" = system_diagnostics(SSmobs),
		"garbage" = system_diagnostics(SSgarbage),
		"shuttles" = system_diagnostics(SSshuttles),
		"radiation" = system_diagnostics(SSradiation),
		"explosions" = system_diagnostics(SSexplosions),
	)
	var/list/material_graphs = list()
	for(var/id in machines_power_material_overlays())
		var/datum/material_power_overlay/overlay = machines_power_material_overlays()[id]
		var/datum/material_power_graph/graph = overlay.material_graph
		if(graph)
			material_graphs += list(list("cables" = length(overlay.cables), "vertices" = length(graph.vertices), "core" = length(graph.core_vertices), "edges" = length(graph.edges), "iterations" = graph.iterations, "solve_ms" = graph.solve_ms, "deposit_ms" = graph.deposit_ms, "resistance_ms" = graph.resistance_ms))
	subsystems["machines"] += list("material_graphs" = material_graphs)
	subsystems["atmos"] += list(
		"dm_stage_average_ms" = list(
			"high_pressure" = air_profile_cost_highpressure(),
			"superconductivity" = air_profile_cost_superconductivity(),
			"pipenets" = air_profile_cost_pipenets(),
			"pipe_commit" = air_profile_cost_pipe_commit(),
			"pipe_devices" = air_profile_cost_pipe_devices(),
			"rebuilds" = air_profile_cost_rebuilds(),
			"gas_tick" = air_profile_cost_turfs(),
			"gas_events" = air_profile_cost_gas_events(),
		),
		"gas_field" = vg_gas_stats(),
		"gas_last_fire" = list(
			"events" = air_profile_gas_events_last(),
			"reactions" = air_profile_gas_reactions_last(),
			"visuals" = air_profile_gas_visuals_last(),
			"pressure_pushes" = air_profile_gas_pressure_last(),
		),
		"queues" = list(
			"hotspots" = length(SSair.hotspots),
			"pressure_deltas" = length(SSair.high_pressure_delta),
			"pipenets" = length(SSair.networks),
			"pipe_devices" = air_profile_rust_pipe_device_count(),
			"pipe_devices_reported" = native_system().pipe_devices_last,
			"rebuild" = length(SSair.rebuild_queue),
			"expansion" = length(SSair.expansion_queue),
		),
	)
	subsystems["machines"] += list(
		"stage_average_ms" = list("machinery" = machine_profile_cost_machinery(), "powernets" = machine_profile_cost_powernets()),
		"stage_last_logical_run_ms" = list("machinery" = machine_profile_last_cost_machinery(), "powernets" = machine_profile_last_cost_powernets()),
		"pump_commit" = list("active_ms" = machine_profile_last_pump_commit_ms(), "wall_ms" = machine_profile_last_pump_commit_wall_ms(), "suspended_ms" = machine_profile_last_pump_commit_suspended_ms(), "operations" = machine_profile_last_pump_commit_operations(), "turfs" = machine_profile_last_pump_commit_turfs()),
		"power" = list("regions" = length(machines_power_grids())),
		"counts" = list("all" = length(REGISTRY_MEMBERS(REGISTRY_MACHINES)), "powernets" = length(machines_power_grids())),
		"gas_wakes" = list("dirty" = machine_profile_gas_dirty_last(), "subscribers_checked" = machine_profile_gas_wake_subscribers_last(), "scan_ms" = machine_profile_gas_wake_scan_last_ms(), "woken" = machine_profile_gas_woken_last(), "dead" = machine_profile_gas_dead_last(), "pending" = length(machines_pending_dirty_gas_mixtures())),
	)
	subsystems["mobs"] += list("counts" = list("world" = REGISTRY_COUNT(REGISTRY_MOBS), "parked" = members_total(sequence_def(/datum/sequence/life).parked_key), "deaths_pending" = length(mobs_death_list())))
	subsystems["periodic"] = periodic_diagnostics()
	subsystems["garbage"] += SSgarbage.performance_diagnostics()
	subsystems["shuttles"] += SSshuttles.performance_diagnostics()
	subsystems["radiation"] += SSradiation.performance_diagnostics()
	subsystems["explosions"] += SSexplosions.performance_diagnostics()
	// Rust world wakes (timers, keys, rate crossings, native watches) on the OM scheduler.
	subsystems["world_step"] = om_world_diagnostics()
	var/list/profile = list(
		"sequence" = ++diagnostic_sequence,
		"world_time_ds" = EXPIRY_AT(src, CLOCK_WORLD, 0),
		"players" = length(GLOB.clients),
		// world.cpu / world.tick_usage are the whole server tick (DM code). The map
		// send cost (appearance/turf/obj changes pushed to clients) is world.map_cpu
		// only; with no clients it is ~0. Earlier profiles logged world.cpu and
		// world.tick_usage under the map_* names, which read as idle map churn.
		"cpu" = world.cpu,
		"tick_usage" = world.tick_usage,
		"map_cpu" = world.map_cpu,
		"initialized" = Kernel.initializations_seconds > 0,
		"sleep_offline" = world.sleep_offline,
		"subsystems" = subsystems,
		"atmos_arena" = atmos_arena,
		"rust_allocator" = rust_allocator,
		"rust_metrics" = rust_metrics,
	)
	log_runtime("PERF_PROFILE [json_encode(profile)]")
	// Keep the stable specialized records consumed by existing benchmark tools.
	log_runtime("ATMOS_PROFILE [json_encode(atmos_arena)]")
	log_runtime("RUST_ALLOC_PROFILE [json_encode(rust_allocator)]")

/// The diagnostics readout of a missing subsystem or service (shared; only encoded).
GLOBAL_LIST_INIT(profiler_missing_diagnostics, list("missing" = TRUE))

/// The readout of a system that runs periodic work (the counters the kernel keeps for it; the rest read 0).
/datum/system/profiler/proc/system_diagnostics(datum/system/target)
	if(!target)
		return GLOB.profiler_missing_diagnostics
	return list(
		"name" = target.name,
		"active_ema_ms" = target.fire_cost,
		"wall_ema_ms" = target.fire_cost,
		"last_wall_ms" = target.run_ms,
		"last_active_ms" = target.run_ms,
		"last_suspended_ms" = 0,
		"last_slices" = target.ticks,
		"tick_usage" = 0,
		"tick_overrun" = target.tick_overrun,
		"allocation_last" = 0,
		"allocation_average" = 0,
		"completed_runs" = target.times_fired,
		"paused_ticks" = 0,
		"slept_count" = 0,
		"postponed_fires" = 0,
		"state" = null,
	)

/datum/system/profiler/on_shutdown()
	if(CONFIG_GET(flag/auto_profile))
		DumpFile(allow_yield = FALSE)
		world.Profile(PROFILE_CLEAR, type = "sendmaps")
	return ..()

/datum/system/profiler/proc/StartProfiling()
	world.Profile(PROFILE_START)
	world.Profile(PROFILE_START, type = "sendmaps")

/datum/system/profiler/proc/StopProfiling()
	world.Profile(PROFILE_STOP)
	world.Profile(PROFILE_STOP, type = "sendmaps")

/datum/system/profiler/proc/DumpFile(allow_yield = TRUE)
	var/timer = TICK_USAGE_REAL
	var/current_profile_data = world.Profile(PROFILE_REFRESH, format = "json")
	var/current_sendmaps_data = world.Profile(PROFILE_REFRESH, type = "sendmaps", format="json")
	fetch_cost = KERNEL_AVERAGE(fetch_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
	if(allow_yield)
		CHECK_TICK

	if(!length(current_profile_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, profiling stopped manually before dump.")
	var/prof_file = file("[GLOB.log_directory]/profiler/profiler-[round(world.time * 0.1, 10)].json")
	if(fexists(prof_file))
		fdel(prof_file)
	if(!length(current_sendmaps_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, sendmaps profiling stopped manually before dump.")
	var/sendmaps_file = file("[GLOB.log_directory]/profiler/sendmaps-[round(world.time * 0.1, 10)].json")
	if(fexists(sendmaps_file))
		fdel(sendmaps_file)

	timer = TICK_USAGE_REAL
	WRITE_FILE(prof_file, current_profile_data)
	WRITE_FILE(sendmaps_file, current_sendmaps_data)
	write_cost = KERNEL_AVERAGE(write_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))

/// Every Rust metric (counters, gauges, histograms; see verdigris/ffi/src/metrics.rs)
/// from one verdigris call, decoded, or null if the library did not answer.
/proc/verdigris_metrics_list()
	var/text = vg_verdigris_metrics()
	if(!istext(text) || !length(text))
		return null
	var/list/decoded
	try
		decoded = json_decode(text)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
		return null
	// DM-side counters ride along: deliveries through native_changed() and errors per bind.
	if(islist(decoded))
		var/list/deliveries = native_delivery_stats()
		for(var/name in deliveries)
			decoded[name] = deliveries[name]
		for(var/bind in GLOB.vg_bind_errors)
			decoded["dm.errors.[bind]"] = GLOB.vg_bind_errors[bind]
	return decoded
