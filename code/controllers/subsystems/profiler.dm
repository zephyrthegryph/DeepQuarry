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
	var/run_idle_benchmark = fexists("data/benchmark_idle")
	var/run_sm_benchmark = fexists("data/benchmark_sm")
	var/run_type_profile = fexists("data/benchmark_type_profile")
	if(run_idle_benchmark)
		fdel("data/benchmark_idle")
	if(run_sm_benchmark)
		fdel("data/benchmark_sm")
	if(run_type_profile)
		fdel("data/benchmark_type_profile")
	if(run_idle_benchmark || run_sm_benchmark)
		Master.sleep_offline_after_initializations = FALSE
		SSticker.start_immediately = TRUE
	if(run_type_profile)
		SSmachines.profile_machine_types = TRUE
		SSexplosions.profile_atom_types = TRUE
	if(run_sm_benchmark)
		SSticker.OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(schedule_sm_benchmark)))
	return SS_INIT_SUCCESS

/proc/schedule_sm_benchmark()
	log_runtime("ATMOS_BENCHMARK scheduled four supermatter-scale explosions at 60-second intervals")
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(run_sm_benchmark), 1, 4), 60 SECONDS)

/proc/run_sm_benchmark(iteration, total)
	if(iteration < total)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(run_sm_benchmark), iteration + 1, total), 60 SECONDS)
	else
		// The last pressure curve ends forty seconds after detonation (ten seconds
		// before opening the breach plus thirty seconds of samples). Give damaged
		// machinery and topology another full minute to settle before declaring the
		// workload complete, so the final subsystem snapshot is true recovery state.
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(begin_sm_benchmark_recovery)), 40 SECONDS)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(log_sm_benchmark_recovery_checkpoint)), 100 SECONDS)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(log_sm_benchmark_long_recovery_checkpoint)), 220 SECONDS)
		// The GC check queue intentionally retains destroyed objects for five
		// minutes. Keep the bounded server alive beyond that horizon so an explosion
		// soak can prove soft collection instead of reporting only a young queue.
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(finish_sm_benchmark)), 360 SECONDS)
	for(var/obj/machinery/power/supermatter/SM in world)
		var/area/affected_area = get_area(SM)
		var/turf/epicenter = get_turf(SM)
		var/epicenter_x = epicenter.x
		var/epicenter_y = epicenter.y
		var/epicenter_z = epicenter.z
		log_runtime("ATMOS_BENCHMARK [iteration]/[total] detonating [SM] at [SM.x],[SM.y],[SM.z]")
		SM.explode()
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(begin_atmos_breach_benchmark), affected_area, "blast-[iteration]", epicenter_x, epicenter_y, epicenter_z), 10 SECONDS)
		return
	var/list/station_areas = get_station_areas(list())
	while(length(station_areas))
		var/area/target_area = pick_n_take(station_areas)
		var/list/open_turfs = list()
		for(var/turf/open/T in target_area)
			open_turfs += T
		if(!length(open_turfs))
			continue
		var/turf/open/epicenter = pick(open_turfs)
		var/epicenter_x = epicenter.x
		var/epicenter_y = epicenter.y
		var/epicenter_z = epicenter.z
		log_runtime("ATMOS_BENCHMARK [iteration]/[total] detonating fallback bomb at [epicenter.x],[epicenter.y],[epicenter.z]")
		explosion(epicenter, 8, 16, 24, 32, TRUE)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(begin_atmos_breach_benchmark), target_area, "blast-[iteration]", epicenter_x, epicenter_y, epicenter_z), 10 SECONDS)
		return
	log_runtime("ATMOS_BENCHMARK could not find a valid station turf")

/proc/force_atmos_benchmark_breach(epicenter_x, epicenter_y, epicenter_z)
	var/turf/epicenter = locate(epicenter_x, epicenter_y, epicenter_z)
	if(!epicenter)
		return
	if(!istype(epicenter, /turf/space))
		epicenter.ChangeTurf(/turf/space)

/proc/begin_atmos_breach_benchmark(area/affected_area, label, epicenter_x, epicenter_y, epicenter_z)
	force_atmos_benchmark_breach(epicenter_x, epicenter_y, epicenter_z)
	schedule_atmos_benchmark_pressure_samples(affected_area, label, epicenter_x, epicenter_y, epicenter_z)

/proc/schedule_atmos_benchmark_pressure_samples(area/affected_area, label, epicenter_x, epicenter_y, epicenter_z)
	if(!affected_area)
		return
	for(var/delay in list(1 SECOND, 5 SECONDS, 15 SECONDS, 30 SECONDS))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(log_atmos_benchmark_pressure), affected_area, label, delay, epicenter_x, epicenter_y, epicenter_z), delay)

/proc/log_atmos_benchmark_pressure(area/affected_area, label, delay, epicenter_x, epicenter_y, epicenter_z)
	if(!affected_area)
		return
	var/turf/open/epicenter = locate(epicenter_x, epicenter_y, epicenter_z)
	if(!istype(epicenter) || get_area(epicenter) != affected_area)
		log_runtime("ATMOS_DRAIN [label] delay=[delay / 10]s area=\"[affected_area.name]\" connected_cells=0 origin_missing=1")
		return
	// Area datums are reused for disconnected map fragments, so averaging every
	// turf in an area can make a successfully spaced room look half pressurized.
	// Measure exactly the atmosphere-connected component containing the blast.
	var/list/turfs_to_scan = list(epicenter)
	var/list/connected_turfs = list()
	connected_turfs[epicenter] = TRUE
	var/scan_index = 1
	while(scan_index <= length(turfs_to_scan))
		var/turf/open/current = turfs_to_scan[scan_index++]
		for(var/turf/open/neighbor as anything in current.atmos_adjacent_turfs)
			if(get_area(neighbor) != affected_area || connected_turfs[neighbor])
				continue
			connected_turfs[neighbor] = TRUE
			turfs_to_scan += neighbor
	var/count = 0
	var/vacuum = 0
	var/total_pressure = 0
	var/min_pressure = INFINITY
	var/max_pressure = 0
	for(var/turf/open/turf as anything in connected_turfs)
		var/datum/gas_mixture/air = turf.return_air()
		if(!air)
			continue
		var/pressure = air.return_pressure()
		count++
		total_pressure += pressure
		min_pressure = min(min_pressure, pressure)
		max_pressure = max(max_pressure, pressure)
		if(pressure < 5)
			vacuum++
	log_runtime("ATMOS_DRAIN [label] delay=[delay / 10]s area=\"[affected_area.name]\" connected_cells=[count] avg_kpa=[count ? round(total_pressure / count, 0.01) : 0] min_kpa=[count ? round(min_pressure, 0.01) : 0] max_kpa=[round(max_pressure, 0.01)] vacuum=[vacuum]")

/proc/begin_sm_benchmark_recovery()
	// Discard the destruction interval. The completion dump must represent only
	// the following quiet minute, otherwise expensive machines that already
	// hibernated remain at the top of a misleading cumulative profile.
	if(SSmachines.profile_machine_types)
		SSmachines.dump_machine_profile()
	log_runtime("ATMOS_BENCHMARK RECOVERY WINDOW START")

/proc/log_sm_benchmark_recovery_checkpoint()
	log_runtime("ATMOS_BENCHMARK RECOVERY 60S CHECKPOINT")
	if(SSmachines.profile_machine_types)
		SSmachines.dump_machine_profile()
	SSprofiler.fire()

/proc/log_sm_benchmark_long_recovery_checkpoint()
	log_runtime("ATMOS_BENCHMARK RECOVERY 180S CHECKPOINT")
	if(SSmachines.profile_machine_types)
		SSmachines.dump_machine_profile()
	SSprofiler.fire()

/proc/finish_sm_benchmark()
	log_runtime("ATMOS_BENCHMARK RECOVERY 320S COMPLETE")
	if(SSmachines.profile_machine_types)
		SSmachines.dump_machine_profile()
	SSprofiler.fire()
	log_runtime("ATMOS_BENCHMARK COMPLETE")

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
	var/list/atmos_arena = SSair.auxmos_diagnostics()
	var/list/rust_allocator = SSair.verdigris_allocator_diagnostics()
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
	)
	subsystems["material_exposure"] += list("pending" = length(SSmaterial_services.scheduled), "current" = length(SSmaterial_services.currentrun))
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
		"pump_commit" = list("ms" = SSmachines.last_pump_commit_ms, "operations" = SSmachines.last_pump_commit_operations, "turfs" = SSmachines.last_pump_commit_turfs),
		"counts" = list("processing" = length(SSmachines.processing_machines), "all" = length(SSmachines.all_machines), "powernets" = length(SSmachines.powernets), "power_objects" = length(SSmachines.powerobjs), "hibernating_vents" = length(SSmachines.hibernating_vents), "reactive_sleepers" = length(SSmachines.reactive_sleepers)),
		"gas_wakes" = list("dirty" = SSmachines.gas_dirty_last, "subscribers_checked" = SSmachines.gas_wake_subscribers_last, "scan_ms" = SSmachines.gas_wake_scan_last_ms, "woken" = SSmachines.gas_woken_last, "dead" = SSmachines.gas_dead_last, "pending" = length(SSmachines.pending_dirty_gas_mixtures)),
	)
	subsystems["mobs"] += list("counts" = list("world" = length(GLOB.mob_list), "current" = length(SSmobs.currentrun), "slept" = SSmobs.slept_mobs, "deaths_pending" = length(SSmobs.death_list)))
	subsystems["objects"] += list("counts" = list("processing" = length(SSobj.processing), "current" = length(SSobj.currentrun)))
	subsystems["garbage"] += SSgarbage.performance_diagnostics()
	subsystems["shuttles"] += SSshuttles.performance_diagnostics()
	subsystems["radiation"] += SSradiation.performance_diagnostics()
	subsystems["explosions"] += SSexplosions.performance_diagnostics()
	var/list/profile = list(
		"sequence" = ++diagnostic_sequence,
		"world_time_ds" = world.time,
		"players" = length(GLOB.clients),
		"map_cpu" = world.cpu,
		"map_tick_usage" = world.tick_usage,
		"subsystems" = subsystems,
		"atmos_arena" = atmos_arena,
		"rust_allocator" = rust_allocator,
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
