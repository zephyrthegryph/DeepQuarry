//
// Base type of pipes
//
/obj/machinery/atmospherics/pipe

	var/datum/gas_mixture/air_temporary // used when reconstructing a pipeline that broke
	var/datum/pipeline/parent
	var/volume = 0
	var/leaking = FALSE // Do not set directly, use set_leaking(TRUE/FALSE)
	var/damaged_leak = FALSE
	/// Pipelines which cache this pipe as a boundary edge. A pipe can be an edge
	/// of several foreign pipelines, so `parent` alone is not sufficient ownership.
	// ALLOW(object_keyed_lists): many-to-many atmos topology roster, cleared symmetrically by lifecycle_unbind()/Destroy()
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

/obj/machinery/atmospherics/pipe/drain_power()
	return -1

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
			parent.leaks |= src
		else
			parent.leaks -= src
		if(parent.network)
			if(leaking)
				parent.network.leaks |= src
			else
				parent.network.leaks -= src
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
	qdel(src)

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
	qdel(line)

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
	var/list/old_edge_pipelines = edge_pipelines
	edge_pipelines = null
	for(var/datum/pipeline/edge_owner as anything in old_edge_pipelines)
		edge_owner.remove_edge(src, FALSE)
	if(rust_owned_parent)
		// Rust already captured this port's exact volume share in the queued
		// remove-to-mixture transaction. The persistent-region commit retires the
		// old compatibility wrapper once for the whole topology batch. Attempting
		// to qdel that shared wrapper from every exploded pipe was deliberately
		// rejected by QDEL_HINT_LETMELIVE and dominated large explosion cost.
		if(!QDELETED(old_parent))
			old_parent.members -= src
			old_parent.leaks -= src
		parent = null
	else
		// Legacy wrappers still own their own gas and teardown semantics.
		QDEL_NULL(parent)
	if(air_temporary)
		loc.assume_air(air_temporary)
		QDEL_NULL(air_temporary)

/obj/machinery/atmospherics/pipe/proc/register_edge_pipeline(datum/pipeline/edge_owner)
	LAZYOR(edge_pipelines, edge_owner)

/obj/machinery/atmospherics/pipe/proc/unregister_edge_pipeline(datum/pipeline/edge_owner)
	LAZYREMOVE(edge_pipelines, edge_owner)

/// Arms its eligibility rule (code/datums/om/watch.dm om_watch_arm_condition()) over both
/// mixtures either side of the leak: it wakes only once they no longer match, which is when the
/// network's leak transaction has something to move. A leaking pipe whose network is intact
/// batches its wake into that network's own dirty transaction (wake_from_leak()).
/obj/machinery/atmospherics/pipe/proc/hibernate_stable_leak()
	clear_leak_gas_dependencies()
	var/datum/gas_mixture/environment = loc?.return_air()
	var/datum/gas_mixture/pipe_air = parent?.air
	var/list/mixture_ids = list()
	for(var/datum/gas_mixture/air as anything in list(environment, pipe_air))
		var/id = air?.arena_id()
		if(!isnull(id))
			mixture_ids |= id
	om_watch_arm_condition(src, "leak", mixture_ids, GAS_DEPENDENCY_ALL, CALLBACK(src, PROC_REF(leak_wake_condition)), wake_callback = CALLBACK(src, PROC_REF(wake_from_leak)))

/obj/machinery/atmospherics/pipe/proc/leak_wake_condition()
	return leaking && leak_needs_equalization(parent?.air, loc?.return_air())

/obj/machinery/atmospherics/pipe/proc/clear_leak_gas_dependencies()
	om_watch_disarm(src, "leak")

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
	parent.mingle_with_turf(loc, volume)
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
		released.set_temperature(material_sorbed_thermal_energy / released_capacity)
	environment.merge(released)
	qdel(released)
	material_sorbed_moles = 0
	material_sorbed_thermal_energy = 0

/obj/machinery/atmospherics/pipe/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/pipe_painter_passthrough,
	)
	..()

/// Old attackby: for non-tank pipes, a pipe painter did nothing here (didn't call ..()),
/// letting the painter's own afterattack recolor the pipe without the default hit message.
/datum/interaction/machine_item/pipe_painter_passthrough
	id = "pipe_painter_passthrough"
	name = "Paint"
	held_type = /obj/item/pipe_painter
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/pipe/proc/not_a_tank, null))
	consumes_input = FALSE
	effect = /atom/proc/interaction_swallow

/obj/machinery/atmospherics/pipe/proc/not_a_tank(mob/actor, atom/target, obj/item/held)
	return !istype(target, /obj/machinery/atmospherics/pipe/tank)

/obj/machinery/atmospherics/pipe/welder_act(mob/user, obj/item/W)
	if(!damaged_leak)
		return NONE
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WELDER, amount = 1, volume = 50, message_self = "You begin welding the fatigue crack in \the [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/pipe/proc/welder_act_tool_done(mob/user)
	if(!(damaged_leak))
		return
	damaged_leak = FALSE
	handle_leaking()
	to_chat(user, span_notice("You seal the fatigue crack in \the [src]."))

/obj/machinery/atmospherics/pipe/wrench_act(mob/user, obj/item/W)
	if(istype(src, /obj/machinery/atmospherics/pipe/tank))
		return NONE
	var/turf/T = src.loc
	if (level==1 && isturf(T) && !T.is_plating())
		to_chat(user, span_warning("You must remove the plating first."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING

	//potential yeet
	var/datum/gas_mixture/int_air = return_air()
	var/datum/gas_mixture/env_air = loc.return_air()
	var/unsafe_wrenching = FALSE
	var/internal_pressure = int_air.return_pressure()-env_air.return_pressure()

	if (internal_pressure > 2*ONE_ATMOSPHERE)
		to_chat(user, span_warning("As you begin unwrenching \the [src] a gush of air blows in your face... maybe you should reconsider?"))
		unsafe_wrenching = TRUE //here we go
	else
		to_chat(user, span_notice("You begin to unfasten \the [src]..."))

	use_tool(user, W, src, delay = 10, volume = 50, receiver = src, job_type = /datum/om/task/timed/tool_job/pipe_unwrench, job_params = list("unsafe" = unsafe_wrenching, "pressure" = internal_pressure))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/pipe/proc/wrench_act_tool_done(mob/user, unsafe_wrenching, internal_pressure)
	user.visible_message( \
		span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
		span_notice("You have unfastened \the [src]."), \
		span_hear("You hear a ratchet."))
	if(unsafe_wrenching)
		unsafe_pressure_release(user, internal_pressure)
	atom_deconstruct()

/obj/machinery/atmospherics/pipe/proc/change_color(new_color)
	//only pass valid pipe colors please ~otherwise your pipe will turn invisible
	if(!pipe_color_check(new_color))
		return

	pipe_color = new_color
	update_icon()

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
	update_icon()

DECLARE_REF(/obj/machinery/atmospherics/pipe, "air_temporary", HELD, null)
DECLARE_REF(/obj/machinery/atmospherics/pipe, "parent", HELD, null)
DECLARE_REF(/obj/machinery/atmospherics/pipe, "edge_pipelines", HELD, null)
