/datum/system/air/proc/is_initialized()
	return initialized

/datum/system/air/proc/completed_steps()
	return times_fired

/datum/system/air/proc/profile_name()
	return name

/datum/system/air/proc/initialization_time_ms()
	return init_time_ms

/datum/system/air/proc/initialization_phase_timings()
	return init_phase_ms.Copy()

/// A single coherent numeric snapshot; no caller receives mutable queues.
/datum/system/air/proc/performance_snapshot()
	return list(
		"cost_turfs" = cost_turfs, "cost_gas_events" = cost_gas_events,
		"cost_highpressure" = cost_highpressure, "cost_superconductivity" = cost_superconductivity,
		"cost_pipenets" = cost_pipenets, "cost_rebuilds" = cost_rebuilds,
		"gas_frames" = gas_frames, "gas_events_last" = gas_events_last,
		"gas_reactions_last" = gas_reactions_last, "gas_visuals_last" = gas_visuals_last,
		"gas_pressure_last" = gas_pressure_last, "networks" = length(networks),
		"high_pressure_delta" = length(high_pressure_delta), "rebuild_queue" = length(rebuild_queue),
		"expansion_queue" = length(expansion_queue), "fire_cost" = fire_cost,
		"ticks" = ticks, "tick_overrun" = tick_overrun, "num_group_turfs_processed" = num_group_turfs_processed,
		"num_equalize_processed" = num_equalize_processed, "low_pressure_turfs" = low_pressure_turfs,
		"high_pressure_turfs" = high_pressure_turfs)

/datum/system/air/proc/processing_enabled()
	return can_fire

/datum/system/air/proc/toggle_processing()
	can_fire = !can_fire

/datum/system/air/proc/set_pipe_topology_dirty(enabled)
	rust_pipe_topology_dirty = enabled

/datum/system/air/proc/start_processing_pipenet(datum/pipe_network/network)
	if(!(network.datum_flags & DF_ISPROCESSING))
		rel_add(src, nameof(networks), network)
		network.datum_flags |= DF_ISPROCESSING

/datum/system/air/proc/stop_processing_pipenet(datum/pipe_network/network)
	rel_remove(src, nameof(networks), network)
	network.datum_flags &= ~DF_ISPROCESSING
	currentrun.Remove(network)

/// Native dispatch counts every event, even one whose turf has already gone.
/datum/system/air/proc/note_gas_event()
	gas_events_last++

/datum/system/air/proc/note_gas_reaction()
	gas_reactions_last++

/datum/system/air/proc/note_gas_visual()
	gas_visuals_last++

/datum/system/air/proc/note_gas_pressure()
	gas_pressure_last++
