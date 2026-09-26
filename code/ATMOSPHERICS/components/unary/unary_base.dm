/obj/machinery/atmospherics/unary
	dir = SOUTH
	initialize_directions = SOUTH
	construction_type = /obj/item/pipe/directional
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF
	//layer = TURF_LAYER+0.1

	var/datum/gas_mixture/air_contents

	var/obj/machinery/atmospherics/node

	var/datum/pipe_network/network

	var/welded = FALSE //defining this here for ventcrawl stuff
	/// Change mask this device cares about on both mixtures it watches while hibernating
	/// (code/datums/om/watch.dm om_watch_arm_revision(); most unary devices only ever act on
	/// a pressure change, so that's the default).
	var/gas_dependency_mask = GAS_DEPENDENCY_PRESSURE

/obj/machinery/atmospherics/unary/Initialize(mapload)
	. = ..()

	air_contents = new
	air_contents.set_volume(200)

/// Arms a "wake on any change" watch on both mixtures this device cares about (its turf and its
/// own pipe contents) and stops polling. Re-arming always replaces the previous watch, so a
/// caller never needs to diff the mixture id itself first.
/obj/machinery/atmospherics/unary/proc/register_gas_dependencies()
	var/datum/gas_mixture/environment = return_air()
	om_watch_arm_revision(src, "turf", environment?.arena_id(), gas_dependency_mask, wake_callback = CALLBACK(src, PROC_REF(wake_from_gas)), current_revision = environment?.revision())
	om_watch_arm_revision(src, "pipe", air_contents?.arena_id(), gas_dependency_mask, wake_callback = CALLBACK(src, PROC_REF(wake_from_gas)), current_revision = air_contents?.revision())

/obj/machinery/atmospherics/unary/proc/unregister_gas_dependencies()
	om_watch_disarm(src, "turf")
	om_watch_disarm(src, "pipe")

/// The wake action for both watches armed above: re-enter process() the same way the deleted
/// gas_dependency_changed()/wake_gas_subscriber() pair used to.
/obj/machinery/atmospherics/unary/proc/wake_from_gas()
	unregister_gas_dependencies()
	START_MACHINE_PROCESSING(src)

/obj/machinery/atmospherics/unary/proc/invalidate_gas_dependencies()
	om_watch_invalidate(src)

/obj/machinery/atmospherics/unary/update_use_power(new_use_power)
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

/obj/machinery/atmospherics/unary/Destroy()
	rust_unregister_pipe_topology()
	// om_watch_disarm_all() (called from /obj/machinery/Destroy() below, via ..()) removes
	// every watch this device holds keyed by its own ref string (code/datums/om/watch.dm) --
	// no weakref needed, so unlike the old subscribe_gas_dependency() transport this doesn't
	// race qdel() setting gc_destroyed before Destroy() runs.
	SSmachines.hibernating_vents -= REF(src)
	// Disconnect/qdel BEFORE ..() so node deref is valid.
	var/datum/pipe_network/old_network = network
	if(old_network?.normal_members)
		old_network.normal_members -= src
		unregister_network_membership(old_network)
	if(node)
		node.disconnect(src)
		rust_release_network_wrapper(old_network)

	node = null
	network = null
	return ..()

/obj/machinery/atmospherics/unary/atmos_init()
	invalidate_gas_dependencies()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,node_connect))
		if(can_be_node(target, 1))
			node = target
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
		network = new_network

	return 1

/obj/machinery/atmospherics/unary/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	if(network == reference)
		results += air_contents

	return results

/obj/machinery/atmospherics/unary/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network == reference)
		air_contents = network_air

/obj/machinery/atmospherics/unary/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network == reference && air_contents == network_air)
		air_contents = detached_pipenet_air(network_air, 200, network_volume)

/obj/machinery/atmospherics/unary/disconnect(obj/machinery/atmospherics/reference)
	invalidate_gas_dependencies()
	if(reference==node)
		rust_release_network_wrapper(network)
		node = null

	update_icon()
	update_underlays()

	return null

// Check if there are any other atmos machines in the same turf that will block this machine from initializing.
// Intended for use when a frame-constructable machine (i.e. not made from pipe fittings) wants to wrench down and connect.
// Returns TRUE if something is blocking, FALSE if its okay to continue.
/obj/machinery/atmospherics/unary/proc/check_for_obstacles()
	for(var/obj/machinery/atmospherics/M in loc)
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

// Keybinds for EVEEERYTHING* (* = not everything))
/obj/machinery/atmospherics/unary/click_ctrl(mob/user)
	if((power_rating != null) && !(pipe_state in list("scrubber", "uvent", "injector"))) //TODO: Add compatibility with air alarm. When not disabled, overrides air alarm state and doesn't tell the air alarm that. Injectors have their own, different bind for enabling.
		user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
		if(allowed(user))
			invalidate_gas_dependencies()
			update_use_power(!use_power)
			update_icon()
			add_fingerprint(user)
			if(use_power)
				to_chat(user, span_notice("You toggle the [name] on."))
			else
				to_chat(user, span_notice("You toggle the [name] off."))

		else
			to_chat(user, span_warning("Access denied."))
