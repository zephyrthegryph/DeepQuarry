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
	/// Arena dependencies captured while this device is absent from SSmachines.
	var/sleeping_turf_mixture_id
	var/sleeping_turf_revision = -1
	var/sleeping_turf_pressure = 0
	var/sleeping_turf_moles = 0
	var/sleeping_pipe_mixture_id
	var/sleeping_pipe_revision = -1
	var/sleeping_pipe_pressure = 0
	var/sleeping_pipe_moles = 0
	var/gas_dependency_mask = GAS_DEPENDENCY_PRESSURE

/obj/machinery/atmospherics/unary/Initialize(mapload)
	. = ..()

	air_contents = new
	air_contents.set_volume(200)

/obj/machinery/atmospherics/unary/proc/register_gas_dependencies(datum/weakref/WR)
	var/datum/gas_mixture/environment = return_air()
	var/new_turf_mixture_id = environment?.arena_id()
	if(sleeping_turf_mixture_id != new_turf_mixture_id)
		SSmachines.unsubscribe_gas_dependency(sleeping_turf_mixture_id, WR)
		sleeping_turf_mixture_id = new_turf_mixture_id
		SSmachines.subscribe_gas_dependency(sleeping_turf_mixture_id, WR)
	if(environment)
		sleeping_turf_revision = environment.revision()
		sleeping_turf_pressure = environment.return_pressure()
		sleeping_turf_moles = environment.total_moles()
	else
		sleeping_turf_revision = -1
		sleeping_turf_pressure = 0
		sleeping_turf_moles = 0
	var/new_pipe_mixture_id = air_contents?.arena_id()
	if(sleeping_pipe_mixture_id != new_pipe_mixture_id)
		SSmachines.unsubscribe_gas_dependency(sleeping_pipe_mixture_id, WR)
		sleeping_pipe_mixture_id = new_pipe_mixture_id
		SSmachines.subscribe_gas_dependency(sleeping_pipe_mixture_id, WR)
	if(air_contents)
		sleeping_pipe_revision = air_contents.revision()
		sleeping_pipe_pressure = air_contents.return_pressure()
		sleeping_pipe_moles = air_contents.total_moles()
	else
		sleeping_pipe_revision = -1
		sleeping_pipe_pressure = 0
		sleeping_pipe_moles = 0

/obj/machinery/atmospherics/unary/proc/unregister_gas_dependencies(datum/weakref/WR)
	SSmachines.unsubscribe_gas_dependency(sleeping_turf_mixture_id, WR)
	SSmachines.unsubscribe_gas_dependency(sleeping_pipe_mixture_id, WR)
	sleeping_turf_mixture_id = null
	sleeping_turf_revision = -1
	sleeping_turf_pressure = 0
	sleeping_turf_moles = 0
	sleeping_pipe_mixture_id = null
	sleeping_pipe_revision = -1
	sleeping_pipe_pressure = 0
	sleeping_pipe_moles = 0

/obj/machinery/atmospherics/unary/gas_dependency_changed(mixture_id, change_mask, list/observation, observation_index)
	if(!(change_mask & gas_dependency_mask))
		return FALSE
	var/observed_revision = observation && observation_index ? observation[observation_index + 2] : null
	if(mixture_id == sleeping_turf_mixture_id)
		if(!isnull(observed_revision))
			sleeping_turf_pressure = observation[observation_index + 3]
			sleeping_turf_moles = observation[observation_index + 14]
			return observed_revision != sleeping_turf_revision
		var/datum/gas_mixture/environment = return_air()
		return !environment || environment.arena_id() != sleeping_turf_mixture_id || environment.revision() != sleeping_turf_revision
	if(mixture_id == sleeping_pipe_mixture_id)
		if(!isnull(observed_revision))
			sleeping_pipe_pressure = observation[observation_index + 3]
			sleeping_pipe_moles = observation[observation_index + 14]
			return observed_revision != sleeping_pipe_revision
		return !air_contents || air_contents.arena_id() != sleeping_pipe_mixture_id || air_contents.revision() != sleeping_pipe_revision
	return TRUE

/obj/machinery/atmospherics/unary/gas_dependency_interest_mask()
	return gas_dependency_mask

/obj/machinery/atmospherics/unary/proc/invalidate_gas_dependencies()
	SSmachines.wake_vent(WEAKREF(src))

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
	// Sleeping devices are held through weakrefs, but their subscription buckets
	// and arena watches must be removed synchronously. Leaving these until the
	// next dirty publication kept deleted injectors alive in GC diagnostics.
	var/datum/weakref/self_ref = WEAKREF(src)
	unregister_gas_dependencies(self_ref)
	// A device destroyed while asleep must also drop out of the sleeping/hibernating
	// registries directly -- those are only cleared on wake, and Destroy() is not
	// guaranteed to route through a wake first.
	if(self_ref?.reference)
		SSmachines.sleeping_gas_devices -= self_ref.reference
		SSmachines.hibernating_vents -= self_ref.reference
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
