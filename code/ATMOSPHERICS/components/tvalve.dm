/obj/machinery/atmospherics/tvalve
	// A manual valve: the AI can't turn it (digital valves set SILICON_USE_HAND).
	silicon_use = NONE
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

/obj/machinery/atmospherics/tvalve/draw(datum/look/look)
	..()
	look.state("tvalve[mirrored ? "m" : ""][state]")

/obj/machinery/atmospherics/tvalve/derived()
	. = ..()
	. += drawn_from(nameof(state))

/// The wheel-turning animation, played when the toggle starts (the state follows a second later).
/obj/machinery/atmospherics/tvalve/proc/animate_toggle()
	flick("tvalve[mirrored ? "m" : ""][src.state][!src.state]", src)

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

/obj/machinery/atmospherics/tvalve/proc/go_to_side()

	if(state) return 0

	var/list/old_edges = rust_pipe_internal_edges()
	set_state(1)
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/tvalve/proc/go_straight()

	if(!state)
		return 0

	var/list/old_edges = rust_pipe_internal_edges()
	set_state(0)
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

CAPABILITIES(/obj/machinery/atmospherics/tvalve)
	op("toggle", hand(), label("Toggle"), wait(0), then(PROC_REF(wheel_turned)))
	pipe_device_unwrench()

/// A three-way valve never runs: it comes off whenever its gas lets it.
/obj/machinery/atmospherics/tvalve/pipe_device_idle(datum/act/A)
	return null

/// The wheel turns: the valve moves a second later.
/obj/machinery/atmospherics/tvalve/proc/wheel_turned(datum/act/op/A)
	animate_toggle()
	after(src, 1 SECOND, PROC_REF(finish_toggle))
	return OP_OK

/// The switch, a second after the wheel is turned.
/obj/machinery/atmospherics/tvalve/proc/finish_toggle()
	if(state)
		go_straight()
	else
		go_to_side()

// M2 (simulation.md §5): same as valve — a three-way valve's flow law is
// pure topology (which pair of ports the region merge connects), so
// process() is deleted outright rather than kept as a self-killing no-op.

/obj/machinery/atmospherics/tvalve/get_node_connect_dirs()
	return get_node_connect_dirs_trinary(dir, mirrored)

/obj/machinery/atmospherics/tvalve/atmos_init()
	if(node1 && node2 && node3)
		return

	var/list/node_connects = get_node_connect_dirs()

	STANDARD_ATMOS_CHOOSE_NODE(1, node_connects[1])
	STANDARD_ATMOS_CHOOSE_NODE(2, node_connects[2])
	STANDARD_ATMOS_CHOOSE_NODE(3, node_connects[3])

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
		rel_set(src, nameof(network_node1), new_network)
	if(network_node2 == old_network)
		rel_set(src, nameof(network_node2), new_network)
	if(network_node3 == old_network)
		rel_set(src, nameof(network_node3), new_network)

	return 1

/obj/machinery/atmospherics/tvalve/return_network_air(datum/pipe_network/reference)
	return null

/obj/machinery/atmospherics/tvalve/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network_node1)
		rel_clear(src, nameof(node1))

	else if(reference==node2)
		rust_release_network_wrapper(network_node2)
		rel_clear(src, nameof(node2))

	else if(reference==node3)
		rust_release_network_wrapper(network_node3)
		rel_clear(src, nameof(node3))

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

/obj/machinery/atmospherics/tvalve/digital/bypass
	icon_state = "map_tvalve1"
	state = 1

/obj/machinery/atmospherics/tvalve/digital/draw(datum/look/look)
	..()
	if(power_lost())
		look.state("tvalve[mirrored ? "m" : ""]nopower")

/// A digital three-way valve turns for someone its access lets in, while it has power.
CAPABILITIES(/obj/machinery/atmospherics/tvalve/digital)
	silicon_hand()
	extend("toggle", needs(req(PROC_REF(actor_allowed)), req(PROC_REF(has_power))))

/obj/machinery/atmospherics/tvalve/digital/proc/has_power(datum/act/A)
	return (!power_lost()) ? null : MSG(valve/unpowered)

//Radio remote control

/obj/machinery/atmospherics/tvalve/digital/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_ATMOSIA))

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



TRACKED_BRIDGED(/obj/machinery/atmospherics/tvalve, state, CHANGE_MACHINE_SETTINGS)
