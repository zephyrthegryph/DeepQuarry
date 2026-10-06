/obj/machinery/atmospherics/binary
	dir = SOUTH
	initialize_directions = SOUTH|NORTH
	use_power = USE_POWER_IDLE

	var/datum/gas_mixture/air1
	var/datum/gas_mixture/air2

	var/datum/pipe_network/network1
	var/datum/pipe_network/network2

/obj/machinery/atmospherics/binary/Initialize(mapload)
	. = ..()

	atmos_air_set(src, nameof(air1), new /datum/gas_mixture)
	atmos_air_set(src, nameof(air2), new /datum/gas_mixture)

	air1.set_volume(200)
	air2.set_volume(200)

/obj/machinery/atmospherics/binary/init_dir()
	switch(dir)
		if(NORTH)
			initialize_directions = NORTH|SOUTH
		if(SOUTH)
			initialize_directions = NORTH|SOUTH
		if(EAST)
			initialize_directions = EAST|WEST
		if(WEST)
			initialize_directions = EAST|WEST

// Housekeeping and pipe network stuff below
/obj/machinery/atmospherics/binary/get_neighbor_nodes_for_init()
	return list(node1, node2)

/obj/machinery/atmospherics/binary/atmos_init()
	if(node1 && node2)
		return

	var/node2_connect = dir
	var/node1_connect = turn(dir, 180)

	STANDARD_ATMOS_CHOOSE_NODE(1, node1_connect)
	STANDARD_ATMOS_CHOOSE_NODE(2, node2_connect)

	update_underlays()

/obj/machinery/atmospherics/binary/return_network(obj/machinery/atmospherics/reference)
	if(reference==node1)
		return network1

	if(reference==node2)
		return network2

	return null

/obj/machinery/atmospherics/binary/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network1 == old_network)
		rel_set(src, nameof(network1), new_network)
	if(network2 == old_network)
		rel_set(src, nameof(network2), new_network)

	return 1

/obj/machinery/atmospherics/binary/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	if(network1 == reference)
		results += air1
	if(network2 == reference)
		results += air2

	return results

/obj/machinery/atmospherics/binary/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	if(network1 == reference)
		atmos_air_set(src, nameof(air1), network_air)
	if(network2 == reference)
		atmos_air_set(src, nameof(air2), network_air)

/obj/machinery/atmospherics/binary/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	if(network1 == reference && air1 == network_air)
		atmos_air_set(src, nameof(air1), detached_pipenet_air(network_air, 200, network_volume))
	if(network2 == reference && air2 == network_air)
		atmos_air_set(src, nameof(air2), detached_pipenet_air(network_air, 200, network_volume))

/obj/machinery/atmospherics/binary/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network1)
		rel_clear(src, nameof(node1))

	else if(reference==node2)
		rust_release_network_wrapper(network2)
		rel_clear(src, nameof(node2))

	update_underlays()

	return null



CAPABILITIES(/obj/machinery/atmospherics/binary)
	owns_one(nameof(air1), on_destroy = ON_DESTROY_PRIVATE_COPY)
	owns_one(nameof(air2), on_destroy = ON_DESTROY_PRIVATE_COPY)
