/obj/machinery/atmospherics/unary
	dir = SOUTH
	initialize_directions = SOUTH
	construction_type = /obj/item/pipe/directional
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/datum/gas_mixture/air_contents

	var/datum/pipe_network/network
	/// Its one pipe neighbour (a relation view: it reads null once the neighbour is gone; disconnect() is the domain unlink).
	var/obj/machinery/atmospherics/node

/obj/machinery/atmospherics/unary/Initialize(mapload)
	. = ..()

	atmos_air_set(src, nameof(air_contents), new /datum/gas_mixture)
	air_contents.set_volume(200)

/obj/machinery/atmospherics/unary/init_dir()
	initialize_directions = dir

/// Joined to a pipe (its one node). A condition a device asks when it is used (a cryo cell taking someone in), and its own work's check.
/obj/machinery/atmospherics/unary/proc/piped(datum/act/op/A)
	return !!node

// Housekeeping and pipe network stuff below
/obj/machinery/atmospherics/unary/get_neighbor_nodes_for_init()
	return list(node)

/obj/machinery/atmospherics/unary/atmos_init()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,node_connect))
		if(can_be_node(target, 1))
			rel_set(src, nameof(node), target)
			break

	changed(src)
	update_underlays()

/obj/machinery/atmospherics/unary/return_network(obj/machinery/atmospherics/reference)
	if(reference==node)
		return network

	return null

/obj/machinery/atmospherics/unary/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
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
	if(reference==node)
		rust_release_network_wrapper(network)
		rel_clear(src, nameof(node))

	changed(src)
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

// ---- an area air device's wrench (a vent, a scrubber) ----

MSG_DEF_SELF(air_device/plating, "You must remove the plating first.")
MSG_DEF_SELF(air_device/welded, "You cannot unwrench it, it is welded down firmly.")

/// The wrench that takes a vent or a scrubber off its pipe: refused while it runs, while the floor covers its pipe, while it is welded and while its
/// pipe holds too much pressure.
/proc/air_device_unwrench()
	return list(op("unwrench", tool(TOOL_WRENCH), wait(4 SECONDS),
		needs(req_bool(TYPE_PROC_REF(/obj/machinery/atmospherics, pipe_device_idle), because = MSG(pipe_device/running)),
			req_bool(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, pipe_reachable), because = MSG(air_device/plating)),
			req_bool(TYPE_PROC_REF(/obj/machinery/atmospherics/unary, not_welded), because = MSG(air_device/welded)),
			req_bool(TYPE_PROC_REF(/obj/machinery/atmospherics, unwrench_safe), because = MSG(pipe_device/exerted))),
		says(MSG(pipe_device/unfastened)),
		then(TYPE_PROC_REF(/obj/machinery/atmospherics, unfastened))))

/obj/machinery/atmospherics/unary/proc/pipe_reachable(datum/act/A)
	var/turf/T = loc // ALLOW(reads): asked when the wrench is used, never from a cached menu; a pipe on a floor stays where it was built
	return !(node && node.level == 1 && isturf(T) && !T.is_plating()) // ALLOW(reads): a pipe's level is fixed by its type; the node is the pipe network's link

/obj/machinery/atmospherics/unary/proc/not_welded(datum/act/A)
	return !weld_shut_welded(src, null)

CAPABILITIES(/obj/machinery/atmospherics/unary)
	ref_one(nameof(node))
	owns_one(nameof(air_contents), on_destroy = ON_DESTROY_PRIVATE_COPY)
	pipe_device_switch()
	extend("power_toggle", when(PROC_REF(ctrl_power_offered)))

/// A port bound in Rust: a device edge that names it can be published now.
/obj/machinery/atmospherics/unary/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	rust_device_dirty()
