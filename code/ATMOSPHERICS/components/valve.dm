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

/obj/machinery/atmospherics/valve/update_icon(animation)
	if(animation)
		flick("valve[src.open][!src.open]",src)
	else
		icon_state = "valve[open]"

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
	open = 1
	update_icon()
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/valve/proc/close()
	if(!open)
		return 0

	var/list/old_edges = rust_pipe_internal_edges()
	open = 0
	update_icon()
	rust_rewire_internal_ports(old_edges, rust_pipe_internal_edges())

	return 1

/obj/machinery/atmospherics/valve/proc/normalize_dir()
	if(dir==3)
		set_dir(1)
	else if(dir==12)
		set_dir(4)

/obj/machinery/atmospherics/valve/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/valve_toggle,
	)
	..()

/// Toggle the valve open or closed.
/datum/interaction/machine_hand/ungated/valve_toggle
	id = "valve_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/atmospherics/valve/proc/interaction_toggle

/obj/machinery/atmospherics/valve/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	update_icon(1)
	om_after(src, 1 SECOND, PROC_REF(finish_toggle))
	return TRUE

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

	update_icon()
	update_underlays()

	if(openDuringInit)
		close()
		open()
		openDuringInit = 0

	MACHINE_SLEEP(src)

/obj/machinery/atmospherics/valve/return_network(obj/machinery/atmospherics/reference)
	if(reference==node1)
		return network_node1

	if(reference==node2)
		return network_node2

	return null

/obj/machinery/atmospherics/valve/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network_node1 == old_network)
		rel_set(src, "network_node1", new_network)
	if(network_node2 == old_network)
		rel_set(src, "network_node2", new_network)

	return 1

/obj/machinery/atmospherics/valve/return_network_air(datum/pipe_network/reference)
	return null

/obj/machinery/atmospherics/valve/disconnect(obj/machinery/atmospherics/reference)
	if(reference==node1)
		rust_release_network_wrapper(network_node1)
		rel_clear(src, "node1")

	else if(reference==node2)
		rust_release_network_wrapper(network_node2)
		rel_clear(src, "node2")

	update_underlays()

	return null

/obj/machinery/atmospherics/valve/digital		// can be controlled by AI
	silicon_use = SILICON_USE_HAND
	name = "digital valve"
	desc = "A digitally controlled valve."
	icon = 'icons/atmos/digital_valve.dmi'
	pipe_state = "dvalve"

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/valve/digital/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/valve_digital_toggle,
	)
	..()

/// Toggle a digital valve: requires power and access, then behaves as the manual toggle.
/datum/interaction/machine_hand/ungated/valve_digital_toggle
	id = "valve_digital_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/atmospherics/valve/digital/proc/interaction_digital_toggle

/obj/machinery/atmospherics/valve/digital/proc/interaction_digital_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(!powered())
		return TRUE
	if(!allowed(user))
		to_chat(user, span_warning("Access denied."))
		return TRUE
	return interaction_toggle(user, held, interaction)

/obj/machinery/atmospherics/valve/digital/open
	open = 1
	icon_state = "map_valve1"

/obj/machinery/atmospherics/valve/digital/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_icon()

/obj/machinery/atmospherics/valve/digital/update_icon()
	..()
	if(!powered())
		icon_state = "valve[open]nopower"

/obj/machinery/atmospherics/valve/digital/proc/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, "radio_connection", GLOB.radio_service.add_object(src, frequency, RADIO_ATMOSIA))

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

/obj/machinery/atmospherics/valve/wrench_act(mob/user, obj/item/W)
	if (istype(src, /obj/machinery/atmospherics/valve/digital) && !src.allowed(user))
		to_chat(user, span_warning("Access denied."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, W, src, delay = 40, quality = TOOL_WRENCH, volume = 50, message_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/valve/proc/wrench_act_tool_done(mob/user)
	user.visible_message( \
		span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
		span_notice("You have unfastened \the [src]."), \
		"You hear a ratchet.")
	atom_deconstruct()

/obj/machinery/atmospherics/valve/examine(mob/user)
	. = ..()
	. += "It is [open ? "open" : "closed"]."


