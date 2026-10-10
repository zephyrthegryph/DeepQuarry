//--------------------------------------------
// Base omni device
//--------------------------------------------
/obj/machinery/atmospherics/omni
	name = "omni device"
	icon = 'icons/atmos/omni_devices_vr.dmi' // New Icon
	icon_state = "base"
	use_power = USE_POWER_IDLE
	initialize_directions = 0
	construction_type = /obj/item/pipe/quaternary
	level = 1

	var/configuring = 0

	var/tag_north = ATM_NONE
	var/tag_south = ATM_NONE
	var/tag_east = ATM_NONE
	var/tag_west = ATM_NONE

	var/overlays_on[5]
	var/overlays_off[5]
	var/overlays_error[2]
	var/underlays_current[4]

	/// The device's four ports, in GLOB.cardinal order (owned: rel_add in Initialize()).
	var/list/datum/omni_port/ports

TRACKED(/obj/machinery/atmospherics/omni, configuring)

CAPABILITIES(/obj/machinery/atmospherics/omni)
	owns_many(nameof(ports), /datum/omni_port)
	pipe_device_switch()
	pipe_device_unwrench()


/obj/machinery/atmospherics/omni/Initialize(mapload)
	. = ..()

	for(var/d in GLOB.cardinal)
		var/datum/omni_port/new_port = new(src, d)
		switch(d)
			if(NORTH)
				new_port.mode = tag_north
			if(SOUTH)
				new_port.mode = tag_south
			if(EAST)
				new_port.mode = tag_east
			if(WEST)
				new_port.mode = tag_west
		if(new_port.mode > 0)
			initialize_directions |= d
		rel_add(src, nameof(ports), new_port)

	build_icons()

/obj/machinery/atmospherics/omni/draw(datum/look/look)
	..()
	look.state("base")
	var/list/shown
	if(power_lost())
		shown = overlays_off // ALLOW(derived_reads): update_ports() and power_change() redraw it whenever the port icons or its power change
	else if(error_check())
		shown = overlays_error // ALLOW(derived_reads): update_ports() and power_change() redraw it whenever the port icons or its power change
	else
		shown = use_power ? overlays_on : overlays_off // ALLOW(derived_reads): update_ports() redraws it whenever the port icons change
	for(var/image in shown)
		look.overlay(image)

/obj/machinery/atmospherics/omni/derived()
	. = ..()
	. += drawn_from(nameof(use_power))

/obj/machinery/atmospherics/omni/proc/error_check()
	return

/// An omni device's flow is a Rust budget group (filter.dm, mixer.dm push_to_rust()): anything that changes its ports,
/// modes or shares marks the device dirty and the group is pushed once this frame.
/obj/machinery/atmospherics/omni/proc/wake_for_state_change()
	rust_device_dirty()

/// A port bound: its region exists in Rust, so the legs can be registered.
/obj/machinery/atmospherics/omni/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	rust_device_dirty()

/obj/machinery/atmospherics/omni/proc/build_icons()
	var/core_icon = null
	if(istype(src, /obj/machinery/atmospherics/omni/mixer))
		core_icon = "mixer"
	else if(istype(src, /obj/machinery/atmospherics/omni/atmos_filter))
		core_icon = "filter"
	else
		return

	//directional icons are layers 1-4, with the core icon on layer 5
	if(core_icon)
		overlays_off[5] = GLOB.icon_manager.get_atmos_icon("omni", , , core_icon)
		overlays_on[5] = GLOB.icon_manager.get_atmos_icon("omni", , , core_icon + "_glow")

		overlays_error[1] = GLOB.icon_manager.get_atmos_icon("omni", , , core_icon)
		overlays_error[2] = GLOB.icon_manager.get_atmos_icon("omni", , , "error")

/obj/machinery/atmospherics/omni/proc/update_port_icons()
	for(var/datum/omni_port/P in ports)
		if(P.update)
			var/ref_layer = 0
			switch(P.dir)
				if(NORTH)
					ref_layer = 1
				if(SOUTH)
					ref_layer = 2
				if(EAST)
					ref_layer = 3
				if(WEST)
					ref_layer = 4

			if(!ref_layer)
				continue

			var/list/port_icons = select_port_icons(P)
			if(port_icons)
				if(P.node)
					underlays_current[ref_layer] = port_icons["pipe_icon"]
				else
					underlays_current[ref_layer] = null
				overlays_off[ref_layer] = port_icons["off_icon"]
				overlays_on[ref_layer] = port_icons["on_icon"]
			else
				underlays_current[ref_layer] = null
				overlays_off[ref_layer] = null
				overlays_on[ref_layer] = null

	underlays = underlays_current // the pipe stubs under its ports (a look has no underlays)
	changed(src)

/obj/machinery/atmospherics/omni/proc/select_port_icons(datum/omni_port/P)
	if(!istype(P))
		return

	if(P.mode > 0)
		var/ic_dir = dir_name(P.dir)
		var/ic_on = ic_dir
		var/ic_off = ic_dir
		switch(P.mode)
			if(ATM_INPUT)
				ic_on += "_in_glow"
				ic_off += "_in"
			if(ATM_OUTPUT)
				ic_on += "_out_glow"
				ic_off += "_out"
			if(ATM_O2 to ATM_LASTGAS)
				ic_on += "_filter"
				ic_off += "_out"

		ic_on = GLOB.icon_manager.get_atmos_icon("omni", , , ic_on)
		ic_off = GLOB.icon_manager.get_atmos_icon("omni", , , ic_off)

		var/pipe_state
		var/turf/T = get_turf(src)
		if(!istype(T))
			return
		if(!T.is_plating() && istype(P.node, /obj/machinery/atmospherics/pipe) && P.node.level == 1 )
			//pipe_state = icon_manager.get_atmos_icon("underlay_down", P.dir, color_cache_name(P.node))
			pipe_state = GLOB.icon_manager.get_atmos_icon("underlay", P.dir, color_cache_name(P.node), "down")
		else
			//pipe_state = icon_manager.get_atmos_icon("underlay_intact", P.dir, color_cache_name(P.node))
			pipe_state = GLOB.icon_manager.get_atmos_icon("underlay", P.dir, color_cache_name(P.node), "intact")

		return list("on_icon" = ic_on, "off_icon" = ic_off, "pipe_icon" = pipe_state)

/obj/machinery/atmospherics/omni/update_underlays()
	for(var/datum/omni_port/P in ports)
		P.update = 1
	update_ports()

/obj/machinery/atmospherics/omni/hide(i)
	update_underlays()

/obj/machinery/atmospherics/omni/proc/update_ports()
	sort_ports()
	if(error_check())
		set_use_power(USE_POWER_OFF) // a device that cannot run (missing ports, bad shares) switches itself off
	update_port_icons()
	for(var/datum/omni_port/P in ports)
		P.update = 0

/obj/machinery/atmospherics/omni/proc/sort_ports()
	return

// Housekeeping and pipe network stuff below
/obj/machinery/atmospherics/omni/get_neighbor_nodes_for_init()
	var/list/neighbor_nodes = list()
	for(var/datum/omni_port/P in ports)
		neighbor_nodes += P.node
	return neighbor_nodes

/obj/machinery/atmospherics/omni/atmos_init()
	for(var/datum/omni_port/P in ports)
		if(P.node || P.mode == 0)
			continue
		for(var/obj/machinery/atmospherics/target in get_step(src, P.dir))
			if(can_be_node(target, 1))
				rel_set(P, nameof(P.node), target)
				break

	for(var/datum/omni_port/P in ports)
		P.update = 1

	update_ports()

/obj/machinery/atmospherics/omni/return_network(obj/machinery/atmospherics/reference)
	for(var/datum/omni_port/P in ports)
		if(reference == P.node)
			return P.network

	return null

/obj/machinery/atmospherics/omni/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	for(var/datum/omni_port/P in ports)
		if(P.network == old_network)
			rel_set(P, nameof(P.network), new_network)

	return 1

/obj/machinery/atmospherics/omni/return_network_air(datum/pipe_network/reference)
	var/list/results = list()

	for(var/datum/omni_port/P in ports)
		if(P.network == reference)
			results += P.air

	return results

/obj/machinery/atmospherics/omni/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	for(var/datum/omni_port/P in ports)
		if(P.network == reference)
			atmos_air_set(P, nameof(P.air), network_air)

/obj/machinery/atmospherics/omni/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	for(var/datum/omni_port/P in ports)
		if(P.network == reference && P.air == network_air)
			atmos_air_set(P, nameof(P.air), detached_pipenet_air(network_air, 200, network_volume))

/obj/machinery/atmospherics/omni/disconnect(obj/machinery/atmospherics/reference)
	wake_for_state_change()
	for(var/datum/omni_port/P in ports)
		if(reference == P.node)
			rust_release_network_wrapper(P.network)
			rel_clear(P, nameof(P.node))
			P.update = 1
			break

	update_ports()

	return null

/// The switch: running ends configuring, and the Rust group is pushed again.
/obj/machinery/atmospherics/omni/toggle_power()
	..()
	if(use_power)
		set_configuring(0)
	wake_for_state_change()

/// An omni device comes off its pipes whether it runs or not (only its gas holds it).
/obj/machinery/atmospherics/omni/pipe_device_idle(datum/act/A)
	return null

// Ports are ours; each points back as `master`, and the filter/mixer subtypes hold them again
// (input, output, atmos_filters, inputs), so the port lets go of its master when deleted.
