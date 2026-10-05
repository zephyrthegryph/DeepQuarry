/obj/machinery/atmospherics/unary
	dir = SOUTH
	initialize_directions = SOUTH
	construction_type = /obj/item/pipe/directional
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/datum/gas_mixture/air_contents

	var/datum/pipe_network/network

	/// Change mask this device cares about on both mixtures it watches while hibernating
	/// (code/datums/om/watch.dm om_watch_arm_revision(); most unary devices only ever act on
	/// a pressure change, so that's the default).
	var/gas_dependency_mask = GAS_DEPENDENCY_PRESSURE

/obj/machinery/atmospherics/unary/Initialize(mapload)
	. = ..()

	atmos_air_set(src, nameof(air_contents), new /datum/gas_mixture)
	air_contents.set_volume(200)

/// Arms this device's own eligibility rule (code/datums/om/watch.dm om_watch_arm_condition()):
/// gas_wake_condition() re-evaluated whenever one of gas_wake_mixtures() publishes a change in
/// gas_dependency_mask, firing only on the edge where it becomes TRUE -- a sleeping device wakes
/// when it can act, not on every revision. Re-arming replaces the previous watch.
/obj/machinery/atmospherics/unary/proc/register_gas_dependencies()
	var/list/mixture_ids = list()
	for(var/datum/gas_mixture/air as anything in gas_wake_mixtures())
		var/id = air?.arena_id()
		if(!isnull(id))
			mixture_ids |= id
	om_watch_arm_condition(src, "gas", mixture_ids, gas_dependency_mask, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))

/// Its one pipe neighbour. A field: connecting or disconnecting raises CHANGE_MACHINE_SETTINGS, so
/// a device whose declared work depends on being connected re-evaluates.
OM_FIELD_VIEW(/obj/machinery/atmospherics/unary, obj/machinery/atmospherics, node, CHANGE_MACHINE_SETTINGS)

/obj/machinery/atmospherics/unary/proc/unregister_gas_dependencies()
	om_watch_disarm(src, "gas")

/// Mixtures whose changes can make gas_wake_condition() true. Its own pipe contents by default.
/obj/machinery/atmospherics/unary/proc/gas_wake_mixtures()
	return list(air_contents)

/// TRUE when process() would have work to do. The base unary device has no DM-side work.
/obj/machinery/atmospherics/unary/proc/gas_wake_condition()
	return FALSE

/// The wake action for both watches armed above: re-enter process() the same way the deleted
/// gas_dependency_changed()/wake_gas_subscriber() pair used to.
/obj/machinery/atmospherics/unary/proc/wake_from_gas()
	unregister_gas_dependencies()
	MACHINE_WAKE(src)

/obj/machinery/atmospherics/unary/proc/invalidate_gas_dependencies()
	om_watch_invalidate(src)

/obj/machinery/atmospherics/unary/set_use_power(new_use_power)
	if(use_power == new_use_power)
		return
	invalidate_gas_dependencies()
	return ..()

/obj/machinery/atmospherics/unary/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/init_dir()
	initialize_directions = dir

// Housekeeping and pipe network stuff below
/obj/machinery/atmospherics/unary/get_neighbor_nodes_for_init()
	return list(node)

/obj/machinery/atmospherics/unary/atmos_init()
	invalidate_gas_dependencies()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,node_connect))
		if(can_be_node(target, 1))
			rel_set(src, nameof(node), target)
			break

	update_icon()
	update_underlays()

/obj/machinery/atmospherics/unary/return_network(obj/machinery/atmospherics/reference)
	if(reference==node)
		return network

	return null

/obj/machinery/atmospherics/unary/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	invalidate_gas_dependencies()
	if(network == old_network)
		rel_set(src, nameof(network), new_network)

	return 1

/obj/machinery/atmospherics/unary/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	if(network == reference)
		results += air_contents

	return results

/obj/machinery/atmospherics/unary/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network == reference)
		atmos_air_set(src, nameof(air_contents), network_air)

/obj/machinery/atmospherics/unary/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network == reference && air_contents == network_air)
		atmos_air_set(src, nameof(air_contents), detached_pipenet_air(network_air, 200, network_volume))

/obj/machinery/atmospherics/unary/disconnect(obj/machinery/atmospherics/reference)
	invalidate_gas_dependencies()
	if(reference==node)
		rust_release_network_wrapper(network)
		rel_clear(src, nameof(node))

	update_icon()
	update_underlays()
	rust_device_dirty() // a device edge that named the node is withdrawn
	return null

// Check if there are any other atmos machines in the same turf that will block this machine from initializing.
// Intended for use when a frame-constructable machine (i.e. not made from pipe fittings) wants to wrench down and connect.
// Returns TRUE if something is blocking, FALSE if its okay to continue.
/obj/machinery/atmospherics/unary/proc/check_for_obstacles()
	for(var/obj/machinery/atmospherics/M in contents_of(loc))
		if(M == src) continue
		if((M.pipe_flags & pipe_flags & PIPING_ONE_PER_TURF))	//Only one dense/requires density object per tile, eg connectors/cryo/heater/coolers.
			visible_message(span_warning("\The [src]'s cannot be connected, something is hogging the tile!"))
			return TRUE
		if((M.piping_layer != piping_layer) && !((M.pipe_flags | flags) & PIPING_ALL_LAYER)) // Pipes on different layers can't block each other unless they are ALL_LAYER
			continue
		if(M.get_init_dirs() & get_init_dirs())	// matches at least one direction on either type of pipe
			visible_message(span_warning("\The [src]'s connector can't be connected, there is already a pipe at that location!"))
			return TRUE
	return FALSE

// ---- the ctrl-click power switch ----

/// A ctrl-click switches a powered unary device (a heater, a freezer) on or off for someone its access lets in. Not a vent, a scrubber or an
/// injector: the air alarm (or the injector's own switch) drives those.
/obj/machinery/atmospherics/unary/proc/ctrl_power_offered(datum/act/op/A)
	return !isnull(power_rating) && !(pipe_state in list("scrubber", "uvent", "injector")) // ALLOW(reads): power_rating and pipe_state are fixed by the type

/obj/machinery/atmospherics/unary/proc/actor_allowed(datum/act/op/A)
	return allowed(A.actor)

/obj/machinery/atmospherics/unary/proc/ctrl_power_toggled(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	set_use_power(!use_power)
	add_fingerprint(user)
	to_chat(user, span_notice("You toggle the [name] [use_power ? "on" : "off"]."))
	return OP_OK

// ---- an area air device's wrench (a vent, a scrubber) ----

MSG_DEF_SELF(air_device/running, "You cannot unwrench it, turn it off first.")
MSG_DEF_SELF(air_device/plating, "You must remove the plating first.")
MSG_DEF_SELF(air_device/welded, "You cannot unwrench it, it is welded down firmly.")
MSG_DEF_SELF(air_device/exerted, "You cannot unwrench it, it is too exerted due to internal pressure.")
MSG_DEF(air_device/unfastened, "You have unfastened %T%.", "%U% unfastens %T%.")

/// The wrench that takes a vent or a scrubber off its pipe: refused while it runs, while the floor covers its pipe, while it is welded and while its
/// pipe holds too much pressure.
/proc/air_device_unwrench()
	return list(op("unwrench", tool(TOOL_WRENCH), wait(4 SECONDS),
		needs(req(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, not_running), because = MSG(air_device/running)),
			req(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, pipe_reachable), because = MSG(air_device/plating)),
			req(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, not_welded), because = MSG(air_device/welded)),
			req(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, unwrench_safe), because = MSG(air_device/exerted))),
		says(MSG(air_device/unfastened)),
		then(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, unfastened))))

/obj/machinery/atmospherics/unary/proc/not_running(datum/act/A)
	return has_stat(NOPOWER) || !use_power

/obj/machinery/atmospherics/unary/proc/pipe_reachable(datum/act/A)
	var/turf/T = loc // ALLOW(reads): asked when the wrench is used, never from a cached menu; a pipe on a floor stays where it was built
	return !(node && node.level == 1 && isturf(T) && !T.is_plating()) // ALLOW(reads): a pipe's level is fixed by its type; the node is the pipe network's link

/obj/machinery/atmospherics/unary/proc/not_welded(datum/act/A)
	return !weld_shut_welded(src, null)

/obj/machinery/atmospherics/unary/proc/unwrench_safe(datum/act/A)
	return can_unwrench()

/obj/machinery/atmospherics/unary/proc/unfastened(datum/act/op/A)
	atom_deconstruct()
	return OP_OK

/obj/machinery/atmospherics/unary/step_has_work()
	return gas_wake_condition()

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/atmospherics/unary/arm_wakes()
	..()
	register_gas_dependencies()


CAPABILITIES(/obj/machinery/atmospherics/unary)
	owns_one(nameof(air_contents), on_destroy = ON_DESTROY_PRIVATE_COPY)
	op("power_toggle", hand(), gesture(GESTURE_CTRL), label("Toggle power"), wait(0), when(PROC_REF(ctrl_power_offered)),
		needs(req(PROC_REF(actor_allowed), because = MSG(lock/denied))), then(PROC_REF(ctrl_power_toggled)))

/// A port bound in Rust: a device edge that names it can be published now.
/obj/machinery/atmospherics/unary/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	rust_device_dirty()
