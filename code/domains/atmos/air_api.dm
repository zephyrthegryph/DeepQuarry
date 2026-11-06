// The air system's API (code/ATMOSPHERICS/SSair.dm declares the system). Other folders reach its state through these procs and the
// SYSTEM_ACCESSOR reads in code/contracts/accessors/accessors.dm (air_*), never through its vars.
//
//   SSair.add_pipenet(net) / remove_pipenet(net)       a pipe network joins or leaves the processing list
//   SSair.pipenet_count() / high_pressure_delta_count() / rebuild_queue_count() / expansion_queue_count()   diagnostics counts
//   SSair.set_pipe_topology_dirty(dirty)               whether Rust's pipe topology needs a commit
//   SSair.count_gas_event() / count_gas_reaction() / count_gas_visual() / count_gas_pressure()   per-frame native event counters

/// A pipe network starts being processed by the air system.
/datum/system/air/proc/add_pipenet(datum/pipe_network/net)
	rel_add(src, nameof(networks), net)

/// A pipe network stops being processed (also dropped from this tick's run list).
/datum/system/air/proc/remove_pipenet(datum/pipe_network/net)
	rel_remove(src, nameof(networks), net)
	currentrun.Remove(net)

/datum/system/air/proc/pipenet_count()
	return length(networks)

/datum/system/air/proc/high_pressure_delta_count()
	return length(high_pressure_delta)

/datum/system/air/proc/rebuild_queue_count()
	return length(rebuild_queue)

/datum/system/air/proc/expansion_queue_count()
	return length(expansion_queue)

/// Marks (or clears) the pending Rust pipe topology commit.
/datum/system/air/proc/set_pipe_topology_dirty(dirty)
	rust_pipe_topology_dirty = dirty

/datum/system/air/proc/count_gas_event()
	gas_events_last++

/datum/system/air/proc/count_gas_reaction()
	gas_reactions_last++

/datum/system/air/proc/count_gas_visual()
	gas_visuals_last++

/datum/system/air/proc/count_gas_pressure()
	gas_pressure_last++

/// Pauses or resumes the air system's periodic work (admin toggle); returns the new state.
/datum/system/air/proc/toggle_processing()
	set_can_fire(!can_fire)
	return can_fire

/// How many times the system has fired.
/datum/system/air/proc/cycles_run()
	return times_fired

/// Whether the system finished initializing.
/datum/system/air/proc/is_initialized()
	return initialized

/// The system's display name (benchmark reports key on it).
/datum/system/air/proc/display_name()
	return name

/// How long initialize() took, in milliseconds.
/datum/system/air/proc/init_time()
	return init_time_ms

/datum/system/air/proc/profile_fire_cost()
	return fire_cost

/datum/system/air/proc/profile_ticks()
	return ticks

/datum/system/air/proc/profile_tick_overrun()
	return tick_overrun
