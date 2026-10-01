/obj/machinery/atmospherics/unary
	dir = SOUTH
	initialize_directions = SOUTH
	construction_type = /obj/item/pipe/directional
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/datum/gas_mixture/air_contents

	var/datum/pipe_network/network

	var/welded = FALSE //defining this here for ventcrawl stuff
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

// Keybinds for EVEEERYTHING* (* = not everything))
/obj/machinery/atmospherics/unary/click_ctrl(mob/user)
	if((power_rating != null) && !(pipe_state in list("scrubber", "uvent", "injector"))) //TODO: Add compatibility with air alarm. When not disabled, overrides air alarm state and doesn't tell the air alarm that. Injectors have their own, different bind for enabling.
		user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
		if(allowed(user))
			invalidate_gas_dependencies()
			set_use_power(!use_power)
			add_fingerprint(user)
			if(use_power)
				to_chat(user, span_notice("You toggle the [name] on."))
			else
				to_chat(user, span_notice("You toggle the [name] off."))

		else
			to_chat(user, span_warning("Access denied."))

/obj/machinery/atmospherics/unary/step_has_work()
	return gas_wake_condition()

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/atmospherics/unary/arm_wakes()
	..()
	register_gas_dependencies()


/obj/machinery/atmospherics/unary/ownership()
	. = ..()
	. += rel_one(nameof(air_contents), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)

TRACKED_BRIDGED(/obj/machinery/atmospherics/unary, welded, CHANGE_MACHINE_SETTINGS)
