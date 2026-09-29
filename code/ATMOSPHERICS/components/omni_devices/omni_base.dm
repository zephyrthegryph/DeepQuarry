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

	var/list/ports = new() // ALLOW(instance_list): atmos area (M1a): omni pipe device ports; listed in memory_lists_audit.md, not edited here

/obj/machinery/atmospherics/omni/Initialize(mapload)
	. = ..()

	icon_state = "base"

	ports = new()
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
		ports += new_port

	build_icons()

/obj/machinery/atmospherics/omni/update_icon()
	if(stat & NOPOWER)
		overlays = overlays_off
	else if(error_check())
		overlays = overlays_error
	else
		overlays = use_power ? (overlays_on) : (overlays_off)

	underlays = underlays_current

	return

/obj/machinery/atmospherics/omni/proc/error_check()
	return

/// Wake tracing for omni devices (off by default): define DQ_TRACE_OMNI_WAKE to log every
/// arm/clear/wake/step decision, for chasing OM_AUDIT missed wakes.
#ifdef DQ_TRACE_OMNI_WAKE
#define OMNI_WAKE_TRACE(M, what) log_world("OMNI_WAKE_TRACE [REF(M)] [M.name] t=[world.time] [what] stat=[M.stat] use_power=[M.use_power] active=[M.step_active] armed=[om_watch_armed(M)]")
#else
#define OMNI_WAKE_TRACE(M, what)
#endif

/obj/machinery/atmospherics/omni/machine_step()
	OMNI_WAKE_TRACE(src, "step")
	last_power_draw = 0
	last_flow_rate = 0

	if(error_check())
		update_use_power(USE_POWER_OFF)

	if((stat & (NOPOWER|BROKEN)) || !use_power)
		return 0
	return 1

/obj/machinery/atmospherics/omni/power_change()
	var/old_stat = stat
	..()
	OMNI_WAKE_TRACE(src, "power_change old_stat=[old_stat]")
	if(old_stat != stat)
		update_icon()
		wake_for_state_change()

/// Arms its eligibility rule (code/datums/om/watch.dm om_watch_arm_condition()) over every port
/// mixture: it wakes only once it is on, powered and can_process_gas() says there is enough to
/// move -- not on every revision of every port.
/obj/machinery/atmospherics/omni/proc/hibernate_until_gas_changes()
	var/list/mixture_ids = list()
	for(var/datum/omni_port/P as anything in ports)
		var/id = P.air?.arena_id()
		if(!isnull(id))
			mixture_ids |= id
	om_watch_arm_condition(src, "gas", mixture_ids, GAS_DEPENDENCY_ALL, CALLBACK(src, PROC_REF(gas_wake_condition)), wake_callback = CALLBACK(src, PROC_REF(wake_for_state_change)))
	MACHINE_SLEEP(src)
	OMNI_WAKE_TRACE(src, "hibernate mixtures=[length(mixture_ids)]")

/obj/machinery/atmospherics/omni/proc/clear_gas_dependencies()
	om_watch_disarm(src, "gas")

/obj/machinery/atmospherics/omni/proc/gas_wake_condition()
	return use_power && !(stat & (NOPOWER|BROKEN)) && can_process_gas()

/obj/machinery/atmospherics/omni/proc/can_process_gas()
	return TRUE

/obj/machinery/atmospherics/omni/proc/wake_for_state_change()
	clear_gas_dependencies()
	if(use_power && !(stat & (NOPOWER|BROKEN)))
		MACHINE_WAKE(src)
	OMNI_WAKE_TRACE(src, "wake_for_state_change")

/obj/machinery/atmospherics/omni/wrench_act(mob/user, obj/item/W)
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/omni/proc/wrench_act_tool_done(mob/user)
	user.visible_message( \
		span_infoplain(span_bold("\The [user]") + "unfastens \the [src]."), \
		span_notice("You have unfastened \the [src]."), \
		"You hear a ratchet.")
	atom_deconstruct()

/obj/machinery/atmospherics/omni/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/omni_open_ui,
	)
	..()

/// Open the omni device's interface: the old `if(..()) return; add_fingerprint(user); tgui_interact(user)`.
/datum/interaction/machine_hand/omni_open_ui
	id = "omni_open_ui"
	name = "Use"
	effect = /obj/machinery/atmospherics/omni/proc/interaction_open_ui_impl

/obj/machinery/atmospherics/omni/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

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

	update_icon()

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
				P.node = target
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
			P.network = new_network

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
			P.air = network_air

/obj/machinery/atmospherics/omni/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	for(var/datum/omni_port/P in ports)
		if(P.network == reference && P.air == network_air)
			P.air = detached_pipenet_air(network_air, 200, network_volume)

/obj/machinery/atmospherics/omni/disconnect(obj/machinery/atmospherics/reference)
	wake_for_state_change()
	for(var/datum/omni_port/P in ports)
		if(reference == P.node)
			rust_release_network_wrapper(P.network)
			P.node = null
			P.update = 1
			break

	update_ports()

	return null

// Keybinds for EVEEERYTHING
/obj/machinery/atmospherics/omni/click_ctrl(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(allowed(user))
		update_use_power(!use_power)
		wake_for_state_change()
		update_icon()
		add_fingerprint(user)
		if(use_power)
			configuring = 0
			to_chat(user, span_notice("You toggle the [name] on."))

		else
			to_chat(user, span_notice("You toggle the [name] off."))

	else
		to_chat(user, span_warning("Access denied."))

/obj/machinery/atmospherics/omni/step_has_work()
	return gas_wake_condition()

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/atmospherics/omni/arm_wakes()
	..()
	hibernate_until_gas_changes()

// Ports are ours; each points back as `master`, and the filter/mixer subtypes hold them again
// (input, output, atmos_filters, inputs), so the port lets go of its master when deleted.
DECLARE_REF(/obj/machinery/atmospherics/omni, "ports", OWNED_LIST, null)
