SUBSYSTEM_DEF(profiler)
	name = "Profiler"
	init_stage = INITSTAGE_FIRST
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	wait = 30 SECONDS
	var/fetch_cost = 0
	var/write_cost = 0
	/// Monotonic identifier for compact diagnostic snapshots. This profiler is
	/// intentionally independent of BYOND's expensive full proc serializer.
	var/diagnostic_sequence = 0

/datum/controller/subsystem/profiler/stat_entry(msg)
	msg += "F:[round(fetch_cost,1)]ms"
	msg += "|W:[round(write_cost,1)]ms"
	return msg

/datum/controller/subsystem/profiler/Initialize()
	if(CONFIG_GET(flag/auto_profile))
		StartProfiling()
	else
		StopProfiling() //Stop the early start profiler
	wait = CONFIG_GET(number/profiler_interval)
	// AUTO_PROFILE controls full world.Profile collection only. Compact subsystem
	// diagnostics are cheap, bounded, and must continue even when it is disabled.
	can_fire = TRUE
	return SS_INIT_SUCCESS

/datum/controller/subsystem/profiler/OnConfigLoad()
	if(CONFIG_GET(flag/auto_profile))
		StartProfiling()
	else
		StopProfiling()
	can_fire = TRUE
	wait = CONFIG_GET(number/profiler_interval)

/datum/controller/subsystem/profiler/fire()
	// Full BYOND profile serialization is synchronous and can itself overrun a tick.
	// Periodic collection therefore records only the inexpensive native diagnostics;
	// profile dumps are requested explicitly or by the MC drift outlier detector.
	SSmachines.request_adaptive_profile()
	var/list/atmos_arena = vg_auxmos_diagnostics()
	var/list/rust_allocator = vg_verdigris_allocator_diagnostics()
	// Every Rust metric (allocator tags, jobs, ...) in one call.
	var/list/rust_metrics = verdigris_metrics_list()
	var/list/subsystems = list(
		"atmos" = subsystem_diagnostics(SSair),
		"machines" = subsystem_diagnostics(SSmachines),
		"material_exposure" = subsystem_diagnostics(SSmaterial_services),
		"mobs" = subsystem_diagnostics(SSmobs),
		"objects" = subsystem_diagnostics(SSobj),
		"garbage" = subsystem_diagnostics(SSgarbage),
		"shuttles" = subsystem_diagnostics(SSshuttles),
		"radiation" = subsystem_diagnostics(SSradiation),
		"explosions" = subsystem_diagnostics(SSexplosions),
		"reactor" = subsystem_diagnostics(SSreactor),
	)
	subsystems["material_exposure"] += SSmaterial_services.performance_diagnostics()
	var/list/material_graphs = list()
	for(var/datum/powernet/network as anything in SSmachines.powernets)
		var/datum/material_power_graph/graph = network.material_graph
		if(graph)
			material_graphs += list(list("cables" = length(network.cables), "vertices" = length(graph.vertices), "core" = length(graph.core_vertices), "edges" = length(graph.edges), "iterations" = graph.iterations, "solve_ms" = graph.solve_ms, "deposit_ms" = graph.deposit_ms, "resistance_ms" = graph.resistance_ms))
	subsystems["machines"] += list("material_graphs" = material_graphs)
	subsystems["atmos"] += list(
		"dm_stage_average_ms" = list(
			"hotspots" = SSair.cost_hotspots,
			"high_pressure" = SSair.cost_highpressure,
			"superconductivity" = SSair.cost_superconductivity,
			"pipenets" = SSair.cost_pipenets,
			"rebuilds" = SSair.cost_rebuilds,
			"adjacent" = SSair.cost_adjacent,
			"callback_finalize" = SSair.cost_finalize,
		),
		"rust_worker_last" = list(
			"generation" = SSair.async_generation,
			"total_ms" = SSair.async_compute_cost,
			"selection_ms" = SSair.async_selection_cost,
			"snapshot_ms" = SSair.async_snapshot_cost,
			"fdm_ms" = SSair.async_fdm_cost,
			"equalize_ms" = SSair.async_equalize_cost,
			"publication_ms" = SSair.async_publication_cost,
			"post_process_ms" = SSair.cost_post_process,
			"seed_limit" = SSair.async_seed_limit,
			"cancelled" = SSair.async_cancelled,
			"pressure_urgency_kpa" = SSair.async_pressure_urgency,
			"active_turfs" = SSair.async_active_turfs,
			"seed_turfs" = SSair.async_seed_turfs,
			"retained_turfs" = SSair.async_retained_turfs,
			"retained_temperature_turfs" = SSair.async_retained_temperature_turfs,
			"retained_mole_turfs" = SSair.async_retained_mole_turfs,
			"pending_turfs" = SSair.async_pending_turfs,
			"pending_urgent_turfs" = SSair.async_pending_urgent_turfs,
			"pending_fresh_turfs" = SSair.async_pending_fresh_turfs,
			"pending_frontier_turfs" = SSair.async_pending_frontier_turfs,
			"snapshot_mixtures" = SSair.async_snapshot_mixtures,
			"published_mixtures" = SSair.async_published_mixtures,
			"rejected_generations" = SSair.async_rejected_generations,
			"conservation_rejections" = SSair.async_conservation_rejections,
			"closed_components" = SSair.async_closed_components,
			"conservation_violation_components" = SSair.async_conservation_violation_components,
			"conservation_worst_component_mixtures" = SSair.async_conservation_worst_component_mixtures,
			"conservation_max_gas_delta" = SSair.async_conservation_max_gas_delta,
			"conservation_max_energy_delta" = SSair.async_conservation_max_energy_delta,
		),
		"queues" = list(
			"hotspots" = length(SSair.hotspots),
			"pressure_deltas" = length(SSair.high_pressure_delta),
			"pipenets" = length(SSair.networks),
			"rebuild" = length(SSair.rebuild_queue),
			"expansion" = length(SSair.expansion_queue),
			"adjacent" = length(SSair.adjacent_rebuild),
		),
	)
	subsystems["machines"] += list(
		"stage_average_ms" = list("machinery" = SSmachines.cost_machinery, "powernets" = SSmachines.cost_powernets, "power_objects" = SSmachines.cost_power_objects),
		"stage_last_logical_run_ms" = list("machinery" = SSmachines.last_cost_machinery, "powernets" = SSmachines.last_cost_powernets, "power_objects" = SSmachines.last_cost_power_objects),
		"pump_commit" = list("active_ms" = SSmachines.last_pump_commit_ms, "wall_ms" = SSmachines.last_pump_commit_wall_ms, "suspended_ms" = SSmachines.last_pump_commit_suspended_ms, "operations" = SSmachines.last_pump_commit_operations, "turfs" = SSmachines.last_pump_commit_turfs),
		"topology" = list("jobs" = length(SSmachines.powernet_topology_jobs), "work" = SSmachines.powernet_topology_last_work, "active_ms" = SSmachines.powernet_topology_last_ms),
		"counts" = list("processing" = length(SSmachines.processing_machines), "all" = length(SSmachines.all_machines), "powernets" = length(SSmachines.powernets), "active_powernets" = length(SSmachines.active_powernets), "power_objects" = length(SSmachines.powerobjs), "hibernating_vents" = length(SSmachines.hibernating_vents), "reactive_sleepers" = length(SSmachines.reactive_sleepers)),
		"gas_wakes" = list("dirty" = SSmachines.gas_dirty_last, "subscribers_checked" = SSmachines.gas_wake_subscribers_last, "scan_ms" = SSmachines.gas_wake_scan_last_ms, "woken" = SSmachines.gas_woken_last, "dead" = SSmachines.gas_dead_last, "pending" = length(SSmachines.pending_dirty_gas_mixtures)),
	)
	subsystems["mobs"] += list("counts" = list("world" = length(GLOB.mob_list), "current" = length(SSmobs.currentrun), "slept" = SSmobs.slept_mobs, "deaths_pending" = length(SSmobs.death_list)))
	subsystems["objects"] += list("counts" = list("processing" = length(SSobj.processing), "current" = length(SSobj.currentrun)))
	subsystems["garbage"] += SSgarbage.performance_diagnostics()
	subsystems["shuttles"] += SSshuttles.performance_diagnostics()
	subsystems["radiation"] += SSradiation.performance_diagnostics()
	subsystems["explosions"] += SSexplosions.performance_diagnostics()
	// Wakes by type and reason class, continuous-lane cost, timer counts, dispatch time.
	subsystems["reactor"] += SSreactor.performance_diagnostics()
	var/list/profile = list(
		"sequence" = ++diagnostic_sequence,
		"world_time_ds" = world.time,
		"players" = length(GLOB.clients),
		"map_cpu" = world.cpu,
		"map_tick_usage" = world.tick_usage,
		"subsystems" = subsystems,
		"atmos_arena" = atmos_arena,
		"rust_allocator" = rust_allocator,
		"rust_metrics" = rust_metrics,
	)
	log_runtime("PERF_PROFILE [json_encode(profile)]")
	// Keep the stable specialized records consumed by existing benchmark tools.
	log_runtime("ATMOS_PROFILE [json_encode(atmos_arena)]")
	log_runtime("RUST_ALLOC_PROFILE [json_encode(rust_allocator)]")

/datum/controller/subsystem/profiler/proc/subsystem_diagnostics(datum/controller/subsystem/target)
	if(!target)
		return list("missing" = TRUE)
	return list(
		"name" = target.name,
		"active_ema_ms" = target.cost,
		"wall_ema_ms" = target.wall_cost,
		"last_wall_ms" = target.wall_cost_last,
		"last_active_ms" = target.active_cost_last,
		"last_suspended_ms" = target.suspended_cost_last,
		"last_slices" = target.run_slices_last,
		"tick_usage" = target.tick_usage,
		"tick_overrun" = target.tick_overrun,
		"allocation_last" = target.tick_allocation_last,
		"allocation_average" = target.tick_allocation_avg,
		"completed_runs" = target.times_fired,
		"paused_ticks" = target.paused_ticks,
		"slept_count" = target.slept_count,
		"postponed_fires" = target.postponed_fires,
		"state" = target.state,
	)

/datum/controller/subsystem/profiler/Shutdown()
	if(CONFIG_GET(flag/auto_profile))
		DumpFile(allow_yield = FALSE)
		world.Profile(PROFILE_CLEAR, type = "sendmaps")
	return ..()

/datum/controller/subsystem/profiler/proc/StartProfiling()
	world.Profile(PROFILE_START)
	world.Profile(PROFILE_START, type = "sendmaps")

/datum/controller/subsystem/profiler/proc/StopProfiling()
	world.Profile(PROFILE_STOP)
	world.Profile(PROFILE_STOP, type = "sendmaps")

/datum/controller/subsystem/profiler/proc/DumpFile(allow_yield = TRUE)
	var/timer = TICK_USAGE_REAL
	var/current_profile_data = world.Profile(PROFILE_REFRESH, format = "json")
	var/current_sendmaps_data = world.Profile(PROFILE_REFRESH, type = "sendmaps", format="json")
	fetch_cost = MC_AVERAGE(fetch_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
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
	write_cost = MC_AVERAGE(write_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))

/// Every Rust metric (counters, gauges, histograms; see verdigris/ffi/src/metrics.rs)
/// from one verdigris call, decoded, or null if the library did not answer.
/proc/verdigris_metrics_list()
	var/text = vg_verdigris_metrics()
	if(!istext(text) || !length(text))
		return null
	var/list/decoded
	try
		decoded = json_decode(text)
	catch
		return null
	return decoded
