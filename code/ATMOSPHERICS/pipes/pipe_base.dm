//
// Base type of pipes
//
/obj/machinery/atmospherics/pipe

	var/datum/gas_mixture/air_temporary // used when reconstructing a pipeline that broke
	var/datum/pipeline/parent
	var/volume = 0
	var/leaking = FALSE // Do not set directly, use set_leaking(TRUE/FALSE)
	var/damaged_leak = FALSE
	/// Pipelines which cache this pipe as a boundary edge (two-sided with their `edges`).
	/// A pipe can be an edge of several foreign pipelines.
	var/list/datum/pipeline/edge_pipelines

	layer = PIPES_LAYER
	use_power = USE_POWER_OFF

	pipe_flags = 0 // Does not have PIPING_DEFAULT_LAYER_ONLY flag.

	var/alert_pressure = 80*ONE_ATMOSPHERE
	var/maximum_pressure = 70*ONE_ATMOSPHERE
	var/fatigue_pressure = 55*ONE_ATMOSPHERE
	var/in_stasis = FALSE
		//minimum pressure before check_pressure(...) should be called

	can_buckle = TRUE
	buckle_require_restraints = 1
	buckle_lying = -1

	/// The watches a stable leak sleeps on (its pipe's gas and the room's): either changing wakes the leak.
	var/list/datum/native_watch/gas/leak_watches

MSG_DEF_SELF(pipe/plating, "You must remove the plating first.")
MSG_DEF_SELF(pipe/exerted, "You cannot unwrench it, it is too exerted due to internal pressure.")
MSG_DEF(pipe/unfastened, "You have unfastened %T%.", "%U% unfastens %T%.")
MSG_DEF_SELF(pipe/gush, "As you begin unwrenching it a gush of air blows in your face... maybe you should reconsider?")
MSG_DEF(pipe/sealed, "You seal the fatigue crack in %T%.", "%U% seals the fatigue crack in %T%.")
MSG_DEF_SELF(pipe/not_cracked, "It has no crack to seal.")

CAPABILITIES(/obj/machinery/atmospherics/pipe)
	owns_one(nameof(air_temporary), /datum/gas_mixture)
	owns_many(nameof(leak_watches), /datum/native_watch/gas)
	op("unwrench", tool(TOOL_WRENCH), wait(1 SECOND), when(PROC_REF(wrenchable)),
		needs(req(PROC_REF(floor_clear), because = MSG(pipe/plating)), req(PROC_REF(unwrench_safe), because = MSG(pipe/exerted))),
		begins(PROC_REF(unwrench_warning)), says(MSG(pipe/unfastened)), then(PROC_REF(pipe_unwrenched)))
	op("seal", tool(TOOL_WELDER), wait(4 SECONDS), needs(req(PROC_REF(cracked), because = MSG(pipe/not_cracked))), says(MSG(pipe/sealed)), then(PROC_REF(crack_sealed)))

/obj/machinery/atmospherics/pipe/drain_power()
	return -1

// ALLOW(init/INSTANCE_STATE): level taken from where this instance is placed
/obj/machinery/atmospherics/pipe/Initialize(mapload)
	if(istype(get_turf(src), /turf/simulated/wall) || istype(get_turf(src), /turf/simulated/shuttle/wall) || istype(get_turf(src), /turf/unsimulated/wall))
		level = 1
	. = ..()

/obj/machinery/atmospherics/pipe/hides_under_flooring()
	return level != 2

/obj/machinery/atmospherics/pipe/proc/set_leaking(new_leaking)
	new_leaking = !!new_leaking
	if(leaking == new_leaking)
		return
	clear_leak_gas_dependencies()
	leaking = new_leaking
	wake_automatic_shutoff_valves(parent?.network)
	if(parent)
		if(leaking)
			rel_add(parent, nameof(parent.leaks), src)
		else
			rel_remove(parent, nameof(parent.leaks), src)
		if(parent.network)
			if(leaking)
				rel_add(parent.network, nameof(/datum/pipe_network::leaks), src)
			else
				rel_remove(parent.network, nameof(/datum/pipe_network::leaks), src)
			parent.network.mark_leak_dirty()
	// Without a network yet, network construction (rust_pipenets.dm) collects leaking pipes itself.

/obj/machinery/atmospherics/pipe/proc/handle_leaking()	// Used specifically to update leaking status on different pipes.
	set_leaking(damaged_leak)

/obj/machinery/atmospherics/pipe/pipeline_expansion() // was proc/; base in xgm_compat_shim now
	return null

// For pipes this is the same as pipeline_expansion()
/obj/machinery/atmospherics/pipe/get_neighbor_nodes_for_init()
	return pipeline_expansion()

/obj/machinery/atmospherics/pipe/proc/check_pressure(pressure)
	var/datum/gas_mixture/environment = loc.return_air()
	var/pressure_difference = pressure - (environment?.return_pressure() || 0)
	var/internal_temperature = parent?.air?.return_temperature() || T20C
	var/effective_maximum = material_environment_pressure_limit(maximum_pressure, MATERIAL_PIPE_REFERENCE_RADIUS, MATERIAL_PIPE_REFERENCE_THICKNESS, internal_temperature)
	var/load_ratio = abs(pressure_difference) / max(effective_maximum, ONE_ATMOSPHERE)
	material_service_event(MATERIAL_EVENT_PRESSURE, load_ratio)
	material_service_event(MATERIAL_EVENT_CORROSION, material_gas_corrosion_load(parent?.air))
	if(pressure_difference > effective_maximum)
		burst_from_pressure()
		return FALSE
	return TRUE

/obj/machinery/atmospherics/pipe/material_environment_repaired()
	damaged_leak = FALSE
	set_leaking(FALSE)
	return ..()

/obj/machinery/atmospherics/pipe/material_environment_begin_leak()
	..()
	if(!damaged_leak)
		damaged_leak = TRUE
		set_leaking(TRUE)
		visible_message(span_warning("Gas begins hissing from a fatigue crack in \the [src]."))
		play_sfx(src, SFX_EFFECTS_SPRAY2, 0.35, extrarange = 0)

/obj/machinery/atmospherics/pipe/material_environment_owns_leak()
	return TRUE

/obj/machinery/atmospherics/pipe/material_environment_rupture()
	burst_from_pressure()

/obj/machinery/atmospherics/pipe/proc/burst_from_pressure()
	visible_message(span_danger("\The [src] bursts!"))
	play_sfx(src, SFX_EFFECTS_BANG, 0.5)
	destroyed(src)

/obj/machinery/atmospherics/pipe/return_air()
	if(QDELETED(src))
		return
	return parent?.air || rust_pipe_port_air(1)

/// A neighboring pipe disappeared. Rust owns the connected-region transition
/// and will retire/rebind the shared compatibility pipeline exactly once at
/// commit. Legacy pipelines retain their former eager invalidation behavior.
/obj/machinery/atmospherics/pipe/proc/rust_invalidate_pipeline_wrapper(datum/pipeline/line)
	if(!line || QDELETED(line))
		return
	if(line.network?.rust_authoritative)
		return
	spent(line)

/obj/machinery/atmospherics/pipe/return_network(obj/machinery/atmospherics/reference)
	if(QDELETED(src))
		return
	return parent?.network

/// Phase 1 (unbind), on top of the atmos topology: the pipe's pipeline and
/// leak watches let go, and its gas goes back to the room.
/obj/machinery/atmospherics/pipe/lifecycle_unbind()
	var/datum/pipeline/old_parent = parent
	var/rust_owned_parent = old_parent?.network?.rust_authoritative
	. = ..()
	clear_leak_gas_dependencies()
	wake_automatic_shutoff_valves(old_parent?.network)
	release_sorbed_material_gas()
	// `parent` and `edge_pipelines` are two-sided relations: the framework clears both ends.
	if(rust_owned_parent)
		// Rust already captured this port's exact volume share in the queued
		// remove-to-mixture transaction. The persistent-region commit retires the
		// old compatibility wrapper once for the whole topology batch. Attempting
		// to qdel that shared wrapper from every exploded pipe was deliberately
		// rejected by QDEL_HINT_LETMELIVE and dominated large explosion cost.
		if(!QDELETED(old_parent))
			rel_remove(old_parent, nameof(old_parent.leaks), src)
	else
		// Legacy wrappers still own their own gas and teardown semantics: destroy the line.
		spent(old_parent)
	if(air_temporary)
		loc.assume_air(air_temporary)
		rel_clear(src, nameof(air_temporary))

/// A stable leak sleeps: it watches both mixtures either side of it (Rust reports their changes) and wakes only once they no longer match,
/// which is when the network's leak transaction has something to move.
/obj/machinery/atmospherics/pipe/proc/hibernate_stable_leak()
	gas_watch_many(src, nameof(leak_watches), list(loc?.return_air(), parent?.air), GAS_DEPENDENCY_ALL, PROC_REF(leak_heard))

/// Rust reported a change of one side of a sleeping leak.
/obj/machinery/atmospherics/pipe/proc/leak_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	if(leak_wake_condition())
		wake_from_leak()

/obj/machinery/atmospherics/pipe/proc/leak_wake_condition()
	return leaking && leak_needs_equalization(parent?.air, loc?.return_air())

/obj/machinery/atmospherics/pipe/proc/clear_leak_gas_dependencies()
	gas_watch_many_clear(src, nameof(leak_watches))

/obj/machinery/atmospherics/pipe/proc/wake_from_leak()
	clear_leak_gas_dependencies()
	if(leaking && parent?.network)
		parent.network.mark_leak_dirty()

/obj/machinery/atmospherics/pipe/proc/leak_needs_equalization(datum/gas_mixture/pipe_air, datum/gas_mixture/environment)
	if(!pipe_air || !environment)
		return TRUE
	if(abs(pipe_air.return_pressure() - environment.return_pressure()) > 0.1)
		return TRUE
	if(abs(pipe_air.return_temperature() - environment.return_temperature()) > 0.5)
		return TRUE
	var/pipe_moles = pipe_air.total_moles()
	var/environment_moles = environment.total_moles()
	if(pipe_moles < MINIMUM_MOLES_TO_PUMP || environment_moles < MINIMUM_MOLES_TO_PUMP)
		return (pipe_moles >= MINIMUM_MOLES_TO_PUMP) != (environment_moles >= MINIMUM_MOLES_TO_PUMP)
	var/list/gases = pipe_air.gas_ids() | environment.gas_ids()
	for(var/gas_id in gases)
		var/gas_type = pipe_air.get_xgm_id_for_gas(gas_id)
		if(gas_type && abs(pipe_air.get_moles(gas_type) / pipe_moles - environment.get_moles(gas_type) / environment_moles) > 0.001)
			return TRUE
	return FALSE

/// One network-owned leak transaction. Individual pipe objects merely publish
/// topology/settings changes; the pipenet processes all open faces together.
/obj/machinery/atmospherics/pipe/proc/process_network_leak()
	if(!leaking || !parent || !loc)
		return FALSE
	var/datum/gas_mixture/environment = loc.return_air()
	if(!environment)
		return FALSE
	parent.leak_into(loc, volume)
	if(!leak_needs_equalization(parent.air, environment))
		hibernate_stable_leak()
		return FALSE
	return TRUE

/obj/machinery/atmospherics/pipe/proc/release_sorbed_material_gas(datum/gas_mixture/release_target)
	if(material_sorbed_moles <= 0)
		return
	var/datum/gas_mixture/environment = release_target
	if(!environment)
		var/turf/turf = get_turf(src)
		environment = turf?.return_air()
	if(!environment)
		return
	var/datum/gas_mixture/released = new(1)
	released.adjust_moles(/datum/gas/plasma, material_sorbed_moles)
	var/released_capacity = released.heat_capacity()
	if(released_capacity > 0 && material_sorbed_thermal_energy > 0)
		heat_set(released, material_sorbed_thermal_energy / released_capacity)
	environment.merge(released)
	spent(released)
	material_sorbed_moles = 0
	material_sorbed_thermal_energy = 0

// ---- the wrench and the welder ----

/// A tank is not taken off with a wrench.
/obj/machinery/atmospherics/pipe/proc/wrenchable(datum/act/op/A)
	return !istype(src, /obj/machinery/atmospherics/pipe/tank)

/// Its floor does not cover it.
/obj/machinery/atmospherics/pipe/proc/floor_clear(datum/act/A)
	var/turf/T = loc // ALLOW(reads): asked when the wrench is used, never from a cached menu; a pipe stays where it was built
	return !(level == 1 && isturf(T) && !T.is_plating()) // ALLOW(reads): a pipe's level is fixed by where it was built; asked when the wrench is used

/// What it holds above the room, kPa.
/obj/machinery/atmospherics/pipe/proc/overpressure()
	var/datum/gas_mixture/int_air = parent?.air
	var/datum/gas_mixture/env_air = loc?.return_air()
	return (int_air ? int_air.return_pressure() : 0) - (env_air ? env_air.return_pressure() : 0)

/// The warning as the wrench starts: a pipe far above the room blows gas in the worker's face.
/obj/machinery/atmospherics/pipe/proc/unwrench_warning(datum/act/A)
	return overpressure() > 2 * ONE_ATMOSPHERE ? /datum/msg/pipe/gush : null

/// The wrench took it off: a pipe still far above the room throws its worker; it becomes its fitting.
/obj/machinery/atmospherics/pipe/proc/pipe_unwrenched(datum/act/op/A)
	var/pressure = overpressure()
	if(pressure > 2 * ONE_ATMOSPHERE)
		unsafe_pressure_release(A.actor, pressure)
	atom_deconstruct()
	return OP_OK

/obj/machinery/atmospherics/pipe/proc/cracked(datum/act/A)
	return damaged_leak // ALLOW(reads): asked when the welder is used, never from a cached menu

/obj/machinery/atmospherics/pipe/proc/crack_sealed(datum/act/op/A)
	damaged_leak = FALSE
	handle_leaking()
	return OP_OK

/obj/machinery/atmospherics/pipe/proc/change_color(new_color)
	//only pass valid pipe colors please ~otherwise your pipe will turn invisible
	if(!pipe_color_check(new_color))
		return

	set_pipe_color(new_color)

/obj/machinery/atmospherics/pipe/color_cache_name(obj/machinery/atmospherics/node)
	if(istype(src, /obj/machinery/atmospherics/pipe/tank))
		return ..()

	if(istype(node, /obj/machinery/atmospherics/pipe/manifold) || istype(node, /obj/machinery/atmospherics/pipe/manifold4w))
		if(pipe_color == node.pipe_color)
			return node.pipe_color
		else
			return null
	else if(istype(node, /obj/machinery/atmospherics/pipe/simple))
		return node.pipe_color
	else
		return pipe_color

/obj/machinery/atmospherics/pipe/hide(i)
	if(istype(loc, /turf/simulated))
		invisibility = i ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
