/obj/machinery/atmospherics/trinary
	dir = SOUTH
	initialize_directions = SOUTH|NORTH|WEST
	use_power = USE_POWER_OFF
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/mirrored = FALSE
	var/tee = FALSE

	var/datum/gas_mixture/air1
	var/datum/gas_mixture/air2
	var/datum/gas_mixture/air3

	var/obj/machinery/atmospherics/node3

	var/datum/pipe_network/network1
	var/datum/pipe_network/network2
	var/datum/pipe_network/network3

/obj/machinery/atmospherics/trinary/Initialize(mapload)
	. = ..()

	air1 = new
	air2 = new
	air3 = new

	air1.set_volume(200)
	air2.set_volume(200)
	air3.set_volume(200)

/obj/machinery/atmospherics/trinary/init_dir()
	initialize_directions = get_initialize_directions_trinary(dir, mirrored, tee)

/obj/machinery/atmospherics/trinary/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	var/list/node_connects = get_node_connect_dirs()
	add_underlay(T, node1, node_connects[1])
	add_underlay(T, node2, node_connects[2])
	add_underlay(T, node3, node_connects[3])

/obj/machinery/atmospherics/trinary/hide(i)
	update_underlays()

/obj/machinery/atmospherics/trinary/power_change()
	var/old_stat = stat
	. = ..()
	if(old_stat != stat)
		update_icon()

/obj/machinery/atmospherics/trinary/wrench_act(mob/user, obj/item/W)
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	if (use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear a ratchet.")
		atom_deconstruct()
	return ITEM_INTERACT_SUCCESS

// Housekeeping and pipe network stuff below
/obj/machinery/atmospherics/trinary/get_neighbor_nodes_for_init()
	return list(node1, node2, node3)

/obj/machinery/atmospherics/trinary/Destroy()
	rust_unregister_pipe_topology()
	// Disconnect/qdel BEFORE ..() so node derefs are valid.
	if(node1)
		node1.disconnect(src)
		rust_release_network_wrapper(network1)
	if(node2)
		node2.disconnect(src)
		rust_release_network_wrapper(network2)
	if(node3)
		node3.disconnect(src)
		rust_release_network_wrapper(network3)

	node1 = null
	node2 = null
	node3 = null
	network1 = null
	network2 = null
	network3 = null
	return ..()

// Get the direction each node is facing to connect.
// It now returns as a list so it can be fetched nicely, each entry corresponds to node of same number.
/obj/machinery/atmospherics/trinary/get_node_connect_dirs()
	return get_node_connect_dirs_trinary(dir, mirrored, tee)

/obj/machinery/atmospherics/trinary/atmos_init()
	if(node1 && node2 && node3)
		return

	var/list/node_connects = get_node_connect_dirs()

	STANDARD_ATMOS_CHOOSE_NODE(1, node_connects[1])
	STANDARD_ATMOS_CHOOSE_NODE(2, node_connects[2])
	STANDARD_ATMOS_CHOOSE_NODE(3, node_connects[3])

	update_icon()
	update_underlays()

/obj/machinery/atmospherics/trinary/return_network(obj/machinery/atmospherics/reference)
	if(reference==node1)
		return network1

	if(reference==node2)
		return network2

	if(reference==node3)
		return network3

	return null

/obj/machinery/atmospherics/trinary/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network1 == old_network)
		network1 = new_network
	if(network2 == old_network)
		network2 = new_network
	if(network3 == old_network)
		network3 = new_network

	return 1

/obj/machinery/atmospherics/trinary/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	if(network1 == reference)
		results += air1
	if(network2 == reference)
		results += air2
	if(network3 == reference)
		results += air3

	return results

/obj/machinery/atmospherics/trinary/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network1 == reference)
		air1 = network_air
	if(network2 == reference)
		air2 = network_air
	if(network3 == reference)
		air3 = network_air

/obj/machinery/atmospherics/trinary/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network1 == reference && air1 == network_air)
		air1 = detached_pipenet_air(network_air, 200, network_volume)
	if(network2 == reference && air2 == network_air)
		air2 = detached_pipenet_air(network_air, 200, network_volume)
	if(network3 == reference && air3 == network_air)
		air3 = detached_pipenet_air(network_air, 200, network_volume)

/obj/machinery/atmospherics/trinary/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network1)
		node1 = null

	else if(reference==node2)
		rust_release_network_wrapper(network2)
		node2 = null

	else if(reference==node3)
		rust_release_network_wrapper(network3)
		node3 = null

	update_underlays()

	return null

// Trinary init_dir() logic in a separate proc so it can be referenced from "trinary-ish" places like T-Valves
// TODO - Someday refactor those places under atmospherics/trinary
/proc/get_initialize_directions_trinary(dir, mirrored = FALSE, tee = FALSE)
	if(tee)
		switch(dir)
			if(NORTH)
				return EAST|NORTH|WEST
			if(SOUTH)
				return SOUTH|WEST|EAST
			if(EAST)
				return EAST|NORTH|SOUTH
			if(WEST)
				return WEST|NORTH|SOUTH
	else if(mirrored)
		switch(dir)
			if(NORTH)
				return WEST|NORTH|SOUTH
			if(SOUTH)
				return SOUTH|EAST|NORTH
			if(EAST)
				return EAST|WEST|NORTH
			if(WEST)
				return WEST|SOUTH|EAST
	else
		switch(dir)
			if(NORTH)
				return EAST|NORTH|SOUTH
			if(SOUTH)
				return SOUTH|WEST|NORTH
			if(EAST)
				return EAST|WEST|SOUTH
			if(WEST)
				return WEST|NORTH|EAST

// Trinary get_node_connect_dirs() logic in a separate proc so it can be referenced from "trinary-ish" places like T-Valves
/proc/get_node_connect_dirs_trinary(dir, mirrored = FALSE, tee = FALSE)
	var/node1_connect
	var/node2_connect
	var/node3_connect

	if(tee)
		node1_connect = turn(dir, -90)
		node2_connect = turn(dir, 90)
		node3_connect = dir
	else if(mirrored)
		node1_connect = turn(dir, 180)
		node2_connect = turn(dir, 90)
		node3_connect = dir
	else
		node1_connect = turn(dir, 180)
		node2_connect = turn(dir, -90)
		node3_connect = dir
	return list(node1_connect, node2_connect, node3_connect)

/obj/machinery/atmospherics/trinary/click_ctrl(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(allowed(user))
		update_use_power(!use_power)
		update_icon()
		add_fingerprint(user)
		if(use_power)
			to_chat(user, span_notice("You toggle the [name] on."))
		else
			to_chat(user, span_notice("You toggle the [name] off."))

	else
		to_chat(user, span_warning("Access denied."))
