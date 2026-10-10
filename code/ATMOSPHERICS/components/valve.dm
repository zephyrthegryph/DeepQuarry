/obj/machinery/atmospherics/valve
	// A manual valve: the AI can't turn it (digital and shutoff valves set SILICON_USE_HAND).
	silicon_use = NONE
	icon = 'icons/atmos/valve.dmi'
	icon_state = "map_valve0"
	construction_type = /obj/item/pipe/binary
	pipe_state = "mvalve"

	name = "manual valve"
	desc = "A pipe valve"

	level = 1
	dir = SOUTH
	initialize_directions = SOUTH|NORTH

	var/open = 0
	var/openDuringInit = 0

	var/datum/pipe_network/network_node1
	var/datum/pipe_network/network_node2

/obj/machinery/atmospherics/valve/open
	open = 1
	icon_state = "map_valve1"

TRACKED(/obj/machinery/atmospherics/valve, open)

/obj/machinery/atmospherics/valve/draw(datum/look/look)
	..()
	look.state("valve[open]")

/obj/machinery/atmospherics/valve/derived()
	. = ..()
	. += drawn_from(nameof(open))

/// The wheel-turning animation, played when the toggle starts (the state follows a second later).
/obj/machinery/atmospherics/valve/proc/animate_toggle()
	flick("valve[src.open][!src.open]", src)

/obj/machinery/atmospherics/valve/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	add_underlay(T, node1, get_dir(src, node1))
	add_underlay(T, node2, get_dir(src, node2))

/obj/machinery/atmospherics/valve/hide(i)
	update_underlays()

/obj/machinery/atmospherics/valve/init_dir()
	switch(dir)
		if(NORTH,SOUTH)
			initialize_directions = NORTH|SOUTH
		if(EAST,WEST)
			initialize_directions = EAST|WEST

/obj/machinery/atmospherics/valve/get_neighbor_nodes_for_init()
	return list(node1, node2)

/obj/machinery/atmospherics/valve/proc/open()
	if(open) return 0

	var/list/old_edges = rust_pipe_internal_edges()
	set_open(1)
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/valve/proc/close()
	if(!open)
		return 0

	var/list/old_edges = rust_pipe_internal_edges()
	set_open(0)
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/valve/proc/normalize_dir()
	if(dir==3)
		set_dir(1)
	else if(dir==12)
		set_dir(4)

MSG_DEF_SELF(valve/unpowered, "It has no power.")

CAPABILITIES(/obj/machinery/atmospherics/valve)
	op("toggle", hand(), label("Toggle"), wait(0), then(PROC_REF(wheel_turned)))
	pipe_device_unwrench()

/// A valve needs no power to come off: it never runs.
/obj/machinery/atmospherics/valve/pipe_device_idle(datum/act/A)
	return TRUE

/// The wheel turns: the valve moves a second later.
/obj/machinery/atmospherics/valve/proc/wheel_turned(datum/act/op/A)
	animate_toggle()
	after(src, 1 SECOND, PROC_REF(finish_toggle))
	return OP_OK

/// The switch, a second after the wheel is turned.
/obj/machinery/atmospherics/valve/proc/finish_toggle()
	if(open)
		close()
	else
		open()

// M2 (simulation.md §5): a valve's "flow law" is pure topology (M1b's region
// merge on connect, split on disconnect already equalizes the instant the
// aperture opens/closes — see open()/close() above), so there is no device
// edge or per-tick physics to run here at all. process() is deleted outright
// rather than kept as a self-killing no-op; atmos_init() below stops DM
// process() scheduling for good, matching passive_gate's pattern.

/obj/machinery/atmospherics/valve/atmos_init()
	normalize_dir()

	var/node1_dir
	var/node2_dir

	for(var/direction in GLOB.cardinal)
		if(direction&initialize_directions)
			if (!node1_dir)
				node1_dir = direction
			else if (!node2_dir)
				node2_dir = direction

	STANDARD_ATMOS_CHOOSE_NODE(1, node1_dir)
	STANDARD_ATMOS_CHOOSE_NODE(2, node2_dir)

	update_underlays()

	if(openDuringInit)
		close()
		open()
		openDuringInit = 0


/obj/machinery/atmospherics/valve/return_network(obj/machinery/atmospherics/reference)
	if(reference==node1)
		return network_node1

	if(reference==node2)
		return network_node2

	return null

/obj/machinery/atmospherics/valve/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network_node1 == old_network)
		rel_set(src, nameof(network_node1), new_network)
	if(network_node2 == old_network)
		rel_set(src, nameof(network_node2), new_network)

	return 1

/obj/machinery/atmospherics/valve/return_network_air(datum/pipe_network/reference)
	return null

/obj/machinery/atmospherics/valve/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network_node1)
		rel_clear(src, nameof(node1))

	else if(reference==node2)
		rust_release_network_wrapper(network_node2)
		rel_clear(src, nameof(node2))

	update_underlays()

	return null

/obj/machinery/atmospherics/valve/digital		// can be controlled by AI
	name = "digital valve"
	desc = "A digitally controlled valve."
	icon = 'icons/atmos/digital_valve.dmi'
	pipe_state = "dvalve"

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

/// A digital valve turns for someone its access lets in, while it has power; so does its wrench.
CAPABILITIES(/obj/machinery/atmospherics/valve/digital)
	silicon_hand()
	extend("toggle", needs(req(PROC_REF(actor_allowed), because = MSG(lock/denied)), req(PROC_REF(has_power), because = MSG(valve/unpowered))))
	extend("unwrench", needs(req(PROC_REF(actor_allowed), because = MSG(lock/denied))))

/obj/machinery/atmospherics/valve/digital/proc/has_power(datum/act/A)
	return !power_lost()

/obj/machinery/atmospherics/valve/digital/open
	open = 1
	icon_state = "map_valve1"

/obj/machinery/atmospherics/valve/digital/draw(datum/look/look)
	..()
	if(power_lost())
		look.state("valve[open]nopower")

/obj/machinery/atmospherics/valve/digital/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_ATMOSIA))

/obj/machinery/atmospherics/valve/digital/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/valve/digital/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id))
		return 0

	switch(signal.data["command"])
		if("valve_open")
			if(!open)
				open()

		if("valve_close")
			if(open)
				close()

		if("valve_toggle")
			if(open)
				close()
			else
				open()

/obj/machinery/atmospherics/valve/examine(mob/user)
	. = ..()
	. += "It is [open ? "open" : "closed"]."


