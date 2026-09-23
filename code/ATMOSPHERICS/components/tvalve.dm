/obj/machinery/atmospherics/tvalve
	icon = 'icons/atmos/tvalve.dmi'
	icon_state = "map_tvalve0"
	construction_type = /obj/item/pipe/trinary/flippable
	pipe_state = "mtvalve"

	name = "manual switching valve"
	desc = "A pipe valve"

	level = 1
	dir = SOUTH
	initialize_directions = SOUTH|NORTH|WEST

	var/state = 0 // 0 = go straight, 1 = go to side

	var/mirrored = FALSE
	var/tee = FALSE // Note: Tee not actually supported for T-valves: no sprites

	// like a trinary component, node1 is input, node2 is side output, node3 is straight output
	var/obj/machinery/atmospherics/node3

	var/datum/pipe_network/network_node1
	var/datum/pipe_network/network_node2
	var/datum/pipe_network/network_node3

/obj/machinery/atmospherics/tvalve/bypass
	icon_state = "map_tvalve1"
	state = 1

/obj/machinery/atmospherics/tvalve/update_icon(animation)
	if(animation)
		flick("tvalve[mirrored ? "m" : ""][src.state][!src.state]",src)
	else
		icon_state = "tvalve[mirrored ? "m" : ""][state]"

/obj/machinery/atmospherics/tvalve/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	var/list/node_connects = get_node_connect_dirs()
	add_underlay(T, node1, node_connects[1])
	add_underlay(T, node2, node_connects[2])
	add_underlay(T, node3, node_connects[3])

/obj/machinery/atmospherics/tvalve/hide(i)
	update_underlays()

/obj/machinery/atmospherics/tvalve/init_dir()
	initialize_directions = get_initialize_directions_trinary(dir, mirrored)

/obj/machinery/atmospherics/tvalve/get_neighbor_nodes_for_init()
	return list(node1, node2, node3)

/obj/machinery/atmospherics/tvalve/Destroy()
	rust_unregister_pipe_topology()
	// Disconnect/qdel BEFORE ..() so node derefs are valid.
	if(node1)
		node1.disconnect(src)
		rust_release_network_wrapper(network_node1)
	if(node2)
		node2.disconnect(src)
		rust_release_network_wrapper(network_node2)
	if(node3)
		node3.disconnect(src)
		rust_release_network_wrapper(network_node3)

	node1 = null
	node2 = null
	node3 = null
	network_node1 = null
	network_node2 = null
	network_node3 = null
	return ..()

/obj/machinery/atmospherics/tvalve/proc/go_to_side()

	if(state) return 0

	var/list/old_edges = rust_pipe_internal_edges()
	state = 1
	update_icon()
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/tvalve/proc/go_straight()

	if(!state)
		return 0

	var/list/old_edges = rust_pipe_internal_edges()
	state = 0
	update_icon()
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/tvalve/attack_ai(mob/user as mob)
	return

/obj/machinery/atmospherics/tvalve/attack_hand(mob/user as mob)
	src.add_fingerprint(user)
	update_icon(1)
	sleep(10)
	if (src.state)
		src.go_straight()
	else
		src.go_to_side()

// M2 (simulation.md §5): same as valve — a three-way valve's flow law is
// pure topology (which pair of ports the region merge connects), so
// process() is deleted outright rather than kept as a self-killing no-op.

/obj/machinery/atmospherics/tvalve/get_node_connect_dirs()
	return get_node_connect_dirs_trinary(dir, mirrored)

/obj/machinery/atmospherics/tvalve/atmos_init()
	STOP_MACHINE_PROCESSING(src)
	if(node1 && node2 && node3)
		return

	var/list/node_connects = get_node_connect_dirs()

	STANDARD_ATMOS_CHOOSE_NODE(1, node_connects[1])
	STANDARD_ATMOS_CHOOSE_NODE(2, node_connects[2])
	STANDARD_ATMOS_CHOOSE_NODE(3, node_connects[3])

	update_icon()
	update_underlays()

/obj/machinery/atmospherics/tvalve/return_network(obj/machinery/atmospherics/reference)
	if(reference==node1)
		return network_node1

	if(reference==node2)
		return network_node2

	if(reference==node3)
		return network_node3

	return null

/obj/machinery/atmospherics/tvalve/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network_node1 == old_network)
		network_node1 = new_network
	if(network_node2 == old_network)
		network_node2 = new_network
	if(network_node3 == old_network)
		network_node3 = new_network

	return 1

/obj/machinery/atmospherics/tvalve/return_network_air(datum/pipe_network/reference)
	return null

/obj/machinery/atmospherics/tvalve/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network_node1)
		node1 = null

	else if(reference==node2)
		rust_release_network_wrapper(network_node2)
		node2 = null

	else if(reference==node3)
		rust_release_network_wrapper(network_node3)
		node3 = null

	update_underlays()

	return null

/obj/machinery/atmospherics/tvalve/digital		// can be controlled by AI
	name = "digital switching valve"
	desc = "A digitally controlled valve."
	icon = 'icons/atmos/digital_tvalve.dmi'
	pipe_state = "dtvalve"

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/tvalve/digital/Destroy()
	unregister_radio(src, frequency)
	. = ..()

/obj/machinery/atmospherics/tvalve/digital/bypass
	icon_state = "map_tvalve1"
	state = 1

/obj/machinery/atmospherics/tvalve/digital/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_icon()

/obj/machinery/atmospherics/tvalve/digital/update_icon()
	..()
	if(!powered())
		icon_state = "tvalve[mirrored ? "m" : ""]nopower"

/obj/machinery/atmospherics/tvalve/digital/attack_ai(mob/user as mob)
	return src.attack_hand(user)

/obj/machinery/atmospherics/tvalve/digital/attack_hand(mob/user as mob)
	if(!powered())
		return
	if(!src.allowed(user))
		to_chat(user, span_warning("Access denied."))
		return
	..()

//Radio remote control

/obj/machinery/atmospherics/tvalve/digital/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = SSradio.add_object(src, frequency, RADIO_ATMOSIA)



/obj/machinery/atmospherics/tvalve/digital/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/tvalve/digital/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id))
		return 0

	switch(signal.data["command"])
		if("valve_open")
			if(!state)
				go_to_side()

		if("valve_close")
			if(state)
				go_straight()

		if("valve_toggle")
			if(state)
				go_straight()
			else
				go_to_side()

/obj/machinery/atmospherics/tvalve/wrench_act(mob/user, obj/item/W)
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	if(use_tool(user, W, src, delay = 40, quality = TOOL_WRENCH, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear a ratchet.")
		atom_deconstruct()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/tvalve/mirrored
	icon_state = "map_tvalvem0"
	mirrored = TRUE

/obj/machinery/atmospherics/tvalve/mirrored/bypass
	icon_state = "map_tvalvem1"
	state = 1

/obj/machinery/atmospherics/tvalve/digital/mirrored
	icon_state = "map_tvalvem0"
	mirrored = TRUE

/obj/machinery/atmospherics/tvalve/digital/mirrored/bypass
	icon_state = "map_tvalvem1"
	state = 1
