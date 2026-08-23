/obj/machinery/atmospherics/portables_connector
	icon = 'icons/atmos/connector.dmi'
	icon_state = "map_connector"

	name = "Connector Port"
	desc = "For connecting portables devices related to atmospherics control."

	dir = SOUTH
	initialize_directions = SOUTH
	construction_type = /obj/item/pipe/directional
	pipe_state = "connector"
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/obj/machinery/portable_atmospherics/connected_device

	var/obj/machinery/atmospherics/node

	var/datum/pipe_network/network

	var/on = 0
	var/sleeping_device_mixture_id
	use_power = USE_POWER_OFF
	level = 1

/obj/machinery/atmospherics/portables_connector/fuel
	icon_state = "map_connector-fuel"
	pipe_state = "connector-fuel"
	icon_connect_type = "-fuel"
	pipe_flags = PIPING_ONE_PER_TURF
	connect_types = CONNECT_TYPE_FUEL

/obj/machinery/atmospherics/portables_connector/aux
	icon_state = "map_connector-aux"
	pipe_state = "connector-aux"
	icon_connect_type = "-aux"
	pipe_flags = PIPING_ONE_PER_TURF
	connect_types = CONNECT_TYPE_AUX

/obj/machinery/atmospherics/portables_connector/supply
	icon_state = "map_connector-supply"
	pipe_state = "connector-supply"
	icon_connect_type = "-supply"
	pipe_flags = PIPING_ONE_PER_TURF
	connect_types = CONNECT_TYPE_SUPPLY
	piping_layer = PIPING_LAYER_SUPPLY

/obj/machinery/atmospherics/portables_connector/scrubbers
	icon_state = "map_connector-scrubbers"
	pipe_state = "connector-scrubbers"
	icon_connect_type = "-scrubbers"
	pipe_flags = PIPING_ONE_PER_TURF
	connect_types = CONNECT_TYPE_SCRUBBER
	piping_layer = PIPING_LAYER_SCRUBBER

/obj/machinery/atmospherics/portables_connector/init_dir()
	initialize_directions = dir

/obj/machinery/atmospherics/portables_connector/update_icon()
	icon_state = "connector"

/obj/machinery/atmospherics/portables_connector/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node, dir, node?.icon_connect_type)

/obj/machinery/atmospherics/portables_connector/hide(i)
	update_underlays()

/obj/machinery/atmospherics/portables_connector/process()
	..()
	if(!on)
		return PROCESS_KILL
	if(!connected_device)
		on = 0
		return PROCESS_KILL
	if(network)
		network.mark_dirty()
	hibernate_until_device_changes()
	return PROCESS_KILL

/obj/machinery/atmospherics/portables_connector/proc/hibernate_until_device_changes()
	var/datum/gas_mixture/device_air = connected_device?.air_contents
	if(!device_air)
		return
	var/datum/weakref/WR = WEAKREF(src)
	sleeping_device_mixture_id = device_air.arena_id()
	SSmachines.sleeping_gas_devices[WR.reference] = WR
	SSmachines.subscribe_gas_dependency(sleeping_device_mixture_id, WR)

/obj/machinery/atmospherics/portables_connector/proc/clear_gas_dependency()
	var/datum/weakref/WR = WEAKREF(src)
	if(isnull(sleeping_device_mixture_id))
		if(WR?.reference)
			SSmachines.sleeping_gas_devices.Remove(WR.reference)
		return
	SSmachines.unsubscribe_gas_dependency(sleeping_device_mixture_id, WR)
	sleeping_device_mixture_id = null
	if(WR?.reference)
		SSmachines.sleeping_gas_devices.Remove(WR.reference)

/obj/machinery/atmospherics/portables_connector/proc/gas_dependency_changed(mixture_id, change_mask)
	if(!(change_mask & GAS_DEPENDENCY_ALL))
		return FALSE
	var/datum/gas_mixture/device_air = connected_device?.air_contents
	if(!on || !device_air || device_air.arena_id() != mixture_id)
		return TRUE
	// The connector has no local work to perform. Its sole responsibility on a
	// device-side mutation is enrolling the shared pipenet for reconciliation.
	// Do that directly and leave the connector subscribed instead of scheduling
	// a machinery callback that immediately goes back to sleep.
	if(network)
		network.mark_dirty()
	return FALSE

// Housekeeping and pipe network stuff below
/obj/machinery/atmospherics/portables_connector/get_neighbor_nodes_for_init()
	return list(node)

/obj/machinery/atmospherics/portables_connector/network_expand(datum/pipe_network/new_network, obj/machinery/atmospherics/pipe/reference)
	// Idempotency guard: check membership before assigning slot vars.
	if(new_network.normal_members.Find(src))
		return 0

	if(reference == node)
		network = new_network

	new_network.normal_members += src

	return null

/obj/machinery/atmospherics/portables_connector/Destroy()
	clear_gas_dependency()
	// Disconnect/qdel BEFORE ..() so connected_device/node derefs are valid.
	if(connected_device)
		connected_device.disconnect()

	if(node)
		node.disconnect(src)
		qdel(network)

	node = null
	network = null
	return ..()

/obj/machinery/atmospherics/portables_connector/atmos_init()
	if(node)
		return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,node_connect))
		if(can_be_node(target, 1))
			node = target
			break

	update_icon()
	update_underlays()

/obj/machinery/atmospherics/portables_connector/build_network()
	if(!network && node)
		network = new /datum/pipe_network()
		network.normal_members += src
		network.build_network(node, src)


/obj/machinery/atmospherics/portables_connector/return_network(obj/machinery/atmospherics/reference)
	build_network()

	if(reference==node)
		return network

	if(reference==connected_device)
		return network

	return null

/obj/machinery/atmospherics/portables_connector/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network == old_network)
		network = new_network

	return 1

/obj/machinery/atmospherics/portables_connector/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	if(connected_device)
		results += connected_device.air_contents

	return results

/obj/machinery/atmospherics/portables_connector/disconnect(obj/machinery/atmospherics/reference)
	clear_gas_dependency()
	if(reference==node)
		qdel(network)
		node = null
	if(reference == connected_device || !connected_device)
		on = 0
		STOP_MACHINE_PROCESSING(src)

	update_underlays()

	return null


/obj/machinery/atmospherics/portables_connector/attackby(obj/item/W as obj, mob/user as mob)
	if (!W.has_tool_quality(TOOL_WRENCH))
		return ..()
	if (connected_device)
		to_chat(user, span_warning("You cannot unwrench \the [src], dettach \the [connected_device] first."))
		return 1
	if (locate(/obj/machinery/portable_atmospherics, src.loc))
		return 1
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it too exerted due to internal pressure."))
		add_fingerprint(user)
		return 1
	playsound(src, W.usesound, 50, 1)
	to_chat(user, span_notice("You begin to unfasten \the [src]..."))
	if (do_after(user, 40 * W.toolspeed, target = src))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear a ratchet.")
		atom_deconstruct()
