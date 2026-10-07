/*
Quick overview:

Pipes combine to form pipelines
Pipelines and other atmospheric objects combine to form pipe_networks
	Note: A single pipe_network represents a completely open space

Pipes -> Pipelines
Pipelines + Other Objects -> Pipe network

*/
/obj/machinery/atmospherics
	material_template = /datum/material_template/pressure
	material_total = SHEET_MATERIAL_AMOUNT
	anchored = TRUE
	idle_power_usage = 0
	active_power_usage = 0
	power_channel = ENVIRON
	var/nodealert = 0
	var/power_rating //the maximum amount of power the machine can use to do work, affects how powerful the machine is, in Watts
	/// Bumped (rust_device_dirty()) when the device's Rust law changed for a reason that is no DM var of its own:
	/// a port bound, a neighbour gone, power or a weld. A device's push_to_rust() reads it with the vars its law
	/// is built from, so the push is one coalesced run per frame.
	var/rust_device_rev = 0

	unacidable = TRUE
	layer = ATMOS_LAYER
	plane = PLATING_PLANE

	var/pipe_flags = PIPING_DEFAULT_LAYER_ONLY // Allow other layers by exception basis.
	var/connect_types = CONNECT_TYPE_REGULAR
	var/piping_layer = PIPING_LAYER_DEFAULT // This will replace icon_connect_type at some point ~Leshana
	var/icon_connect_type = "" //"-supply" or "-scrubbers"
	var/construction_type = null // Type path of the pipe item when this is deconstructed.
	var/pipe_state // icon_state as a pipe item

	var/being_loaded = FALSE //If the atmos machinery is currently being loaded via a map_template

	var/initialize_directions = 0
	var/pipe_color

	/// Node topology: foreign neighbours, relation views (cleared by the framework when a
	/// neighbour dies). disconnect() is the domain unlink.
	var/obj/machinery/atmospherics/node1
	var/obj/machinery/atmospherics/node2
	/// Optional material or layered composite retained through construction/deconstruction.
	var/engineered_material_id
	var/material_liner_integrity = 100
	var/material_sorbed_moles = 0
	var/material_sorbed_thermal_energy = 0
	var/material_last_exposure = 0
	/// Every pipe network whose normal_members roster lists this machine (the two-sided
	/// partner of /datum/pipe_network.normal_members).
	var/list/datum/pipe_network/network_memberships
TRACKED(/obj/machinery/atmospherics, icon_connect_type)
TRACKED(/obj/machinery/atmospherics, pipe_color)



/// Phase 1 (unbind): the pipe topology leaves Rust, every node neighbour
/// (get_neighbor_nodes_for_init(), each type's topology declaration)
/// forgets this machine (disconnect() updates its icon and network), and every
/// Rust-owned network wrapper holding it lets go. The node and roster views
/// themselves are relations: the framework clears both ends in phase 4.
/obj/machinery/atmospherics/lifecycle_unbind()
	. = ..()
	rust_unregister_pipe_topology()
	for(var/obj/machinery/atmospherics/neighbour in get_neighbor_nodes_for_init())
		if(!QDELETED(neighbour))
			neighbour.disconnect(src)
	for(var/datum/pipe_network/network as anything in network_memberships?.Copy())
		rust_release_network_wrapper(network)

/// Points holder.var_name (a PROTO gas port: air1/air2/air3, air_contents, a pipeline's air)
/// at `value`. A mixture another holder owns (the pipe network's authoritative air, the
/// proto) is referenced, never adopted; an unowned mixture (a detached port share, a fresh
/// port) becomes the holder's private copy. The private copy it replaces is deleted; a
/// network's shared mixture is only let go (the network owns it).
/proc/atmos_air_set(datum/holder, var_name, datum/gas_mixture/value)
	. = atmos_air_assign(holder, var_name, value)
	var/atom/A = holder
	if(istype(A) && cap_of(A, CAP_GAS_WATCH))
		gas_watch_arm(A) // a gas_watch() follows its mixture
	if(istype(A) && cap_of(A, CAP_GAS_LEVEL))
		gas_level_rearm_all(A) // so does a gas_level()

/proc/atmos_air_assign(datum/holder, var_name, datum/gas_mixture/value)
	var/datum/gas_mixture/old = holder.vars[var_name]
	if(old == value)
		return value
	if(!value || !value.own_holder_ref || (value.own_holder_ref == own_key(holder) && value.own_slot == var_name) || !owner_of(value))
		return proto_set(holder, var_name, value)
	proto_set(holder, var_name, null)
	holder.vars[var_name] = value // ALLOW(api): a PROTO gas port naming the network-owned mixture (ownership.md §3, gas mixtures); proto_teardown leaves it to the network
	return value

/obj/machinery/atmospherics/proc/engineered_material()
	return material_for_role(MATERIAL_ROLE_STRUCTURE) || (engineered_material_id ? get_material_by_name(engineered_material_id) : null)

/obj/machinery/atmospherics/proc/supports_engineered_material()
	return FALSE

/obj/machinery/atmospherics/pipe/supports_engineered_material()
	return TRUE

/obj/machinery/atmospherics/pipe/Initialize(mapload, newdir)
	if(power_rating > 0)
		ensure_pump_materials()
	return ..()

/obj/machinery/atmospherics/examine(mob/user)
	. = ..()
	if(engineered_material_id)
		var/datum/material/material = engineered_material()
		. += span_notice("Pressure construction: [material?.display_name || engineered_material_id]; exposed liner integrity [round(material_liner_integrity)]%.")

// ALLOW(init/INSTANCE_STATE): a pipe device takes its colour (or none it cannot show) and sets up its connection directions
/obj/machinery/atmospherics/Initialize(mapload)
	. = ..()
	if(!pipe_color)
		set_pipe_color(color)
	color = null

	if(!pipe_color_check(pipe_color))
		set_pipe_color(null)
	init_dir()

/obj/machinery/atmospherics/examine_icon()
	return icon(icon=initial(icon),icon_state=initial(icon_state))

// This is used to set up what directions pipes will connect to.  Should be called inside New() and whenever a dir changes.
/obj/machinery/atmospherics/proc/init_dir()
	return

// Get ALL initialize_directions - Some types (HE pipes etc) combine two vars together for this.
/obj/machinery/atmospherics/proc/get_init_dirs()
	return initialize_directions

// Get the direction each node is facing to connect.
// It now returns as a list so it can be fetched nicely, each entry corresponds to node of same number.
/obj/machinery/atmospherics/proc/get_node_connect_dirs()
	return

// Initializes nodes by looking at neighboring atmospherics machinery to connect to.
// When we're being constructed at runtime, atmos_init() is called by the construction code.
// When dynamically loading a map atmos_init is called by the maploader (initTemplateBounds proc)
// But during initial world creation its called by the master_controller.
// TODO - Consolidate these different ways of being called once SSatoms is created.
/obj/machinery/atmospherics/proc/atmos_init()
	return

/** Check if target is an acceptable target to connect as a node from this machine. */
/obj/machinery/atmospherics/proc/can_be_node(obj/machinery/atmospherics/target, node_num)
	return (target.initialize_directions & get_dir(target,src)) && check_connectable(target) && target.check_connectable(src)

/** Check if this machine is willing to connect with the target machine. */
/obj/machinery/atmospherics/proc/check_connectable(obj/machinery/atmospherics/target)
	return (src.connect_types & target.connect_types)

MSG_DEF_SELF(atmospherics/has_shell, "It already has an engineered material shell.")

/// A stack of material could be fitted at all.
/obj/machinery/atmospherics/proc/material_fittable(datum/act/op/A)
	return supports_engineered_material()

/obj/machinery/atmospherics/proc/no_shell(datum/act/A)
	return !engineered_material_id // ALLOW(reads): asked when the sheets are used, never from a cached menu

/obj/machinery/atmospherics/proc/painter_swallowed(datum/act/op/A)
	return OP_OK

/// The sheet (the op's cost) becomes the device's structure and liner.
/obj/machinery/atmospherics/proc/material_fitted(datum/act/op/A)
	var/obj/item/stack/material/stock = A.held
	var/datum/material/material = stock?.material
	if(!material)
		return OP_FAILED
	engineered_material_id = material.name
	apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = material.name, MATERIAL_ROLE_LINER = material.name), /datum/material_template/pressure, SHEET_MATERIAL_AMOUNT)
	to_chat(A.actor, span_notice("You fit [material.display_name] onto [src]. Its actual geometry and operating conditions will determine performance."))
	return OP_OK

/obj/machinery/atmospherics/proc/add_underlay(turf/T, obj/machinery/atmospherics/node, direction, icon_connect_type)
	if(node)
		if(!T.is_plating() && node.level == 1 && istype(node, /obj/machinery/atmospherics/pipe))
			//underlays += icon_manager.get_atmos_icon("underlay_down", direction, color_cache_name(node))
			underlays += GLOB.icon_manager.get_atmos_icon("underlay", direction, color_cache_name(node), "down" + icon_connect_type)
		else
			//underlays += icon_manager.get_atmos_icon("underlay_intact", direction, color_cache_name(node))
			underlays += GLOB.icon_manager.get_atmos_icon("underlay", direction, color_cache_name(node), "intact" + icon_connect_type)
	else
		//underlays += icon_manager.get_atmos_icon("underlay_exposed", direction, pipe_color)
		underlays += GLOB.icon_manager.get_atmos_icon("underlay", direction, color_cache_name(node), "exposed" + icon_connect_type)

/obj/machinery/atmospherics/proc/update_underlays()
	return TRUE

/obj/machinery/atmospherics/proc/color_cache_name(obj/machinery/atmospherics/node)
	//Don't use this for standard pipes
	if(!istype(node))
		return null

	return node.pipe_color

/// Completion callback for deferred Rust gas transfers. Devices which queued a
/// request must make their scheduling decision from the committed amount, not
/// from the optimistic request calculated before shared-source clamping.
/obj/machinery/atmospherics/proc/pump_transaction_committed(actual_moles)
	return

/// Rebind and detach the gas-bearing ports owned by this machine. A connected
/// pipenet has one authoritative mixture; the concrete component maps the
/// relevant air1/air2/air_contents slots to it.
/obj/machinery/atmospherics/proc/bind_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air)
	return

/obj/machinery/atmospherics/proc/detach_network_air(datum/pipe_network/reference, datum/gas_mixture/network_air, network_volume)
	return

/// Optional external reservoir (portable canister/mecha) attached through a
/// connector after the fixed pipe topology has been built.
/obj/machinery/atmospherics/proc/attach_external_network_air(datum/pipe_network/reference)
	return

/proc/detached_pipenet_air(datum/gas_mixture/source, port_volume, network_volume)
	var/datum/gas_mixture/detached = new(max(port_volume, 1))
	if(source && network_volume > 0 && port_volume > 0)
		detached.copy_from_ratio(source, min(port_volume / network_volume, 1))
	detached.set_volume(max(port_volume, 1))
	return detached

/// Generic connector interface shared by portable atmos devices and mecha.
/atom/movable/proc/port_network_air()
	return null

/atom/movable/proc/set_port_network_air(datum/gas_mixture/new_air)
	return FALSE

/obj/machinery/atmospherics/proc/build_network(new_attachment)
	// Compatibility entry point for construction and older callers. Rust is the
	// only topology builder; this publishes stable ports and returns its wrapper.
	rust_register_pipe_topology()
	return return_network()

/obj/machinery/atmospherics/proc/return_network(obj/machinery/atmospherics/reference)
	// Read-only compatibility view. This must never construct topology.
	return null

/obj/machinery/atmospherics/proc/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	// Used when two pipe_networks are combining

/obj/machinery/atmospherics/proc/return_network_air(datum/pipe_network/reference)
	// Return a list of gas_mixture(s) in the object
	//		associated with reference pipe_network for use in rebuilding the networks gases list
	// Is permitted to return null

/obj/machinery/atmospherics/proc/disconnect(obj/machinery/atmospherics/reference)


/obj/machinery/atmospherics/proc/can_unwrench()

	return TRUE

// Deconstruct into a pipe item.
/obj/machinery/atmospherics/atom_deconstruct()
	if(QDELETED(src))
		return
	if(construction_type)
		var/obj/item/pipe/I = new construction_type(loc, null, null, src)
		I.setPipingLayer(piping_layer)
		if(istype(I, /obj/item/pipe/trinary/flippable))
			var/obj/item/pipe/trinary/flippable/flip = I
			flip.icon_state = "[flip.icon_state][flip.mirrored ? "m" : ""]"
		transfer_fingerprints_to(I)
	destroyed(src)

// Return the neighboring nodes whose physical links must be refreshed during construction.
/obj/machinery/atmospherics/proc/get_neighbor_nodes_for_init()
	return null

// Called on construction (i.e from pipe item) but not on initialization
/obj/machinery/atmospherics/proc/on_construction(obj_color, set_layer)
	wake_automatic_shutoff_valves()
	set_pipe_color(obj_color)
	setPipingLayer(set_layer)
	// TODO - M.connect_types = src.connect_types - Or otherwise copy from item? Or figure it out from piping layer?
	var/turf/T = get_turf(src)
	level = !T.is_plating() ? 2 : 1
	atmos_init()
	if(QDELETED(src))
		return // TODO - Eventually should get rid of the need for this.
	var/list/nodes = get_neighbor_nodes_for_init()
	for(var/obj/machinery/atmospherics/A in nodes)
		A.atmos_init()
	rust_register_pipe_topology()

// This sets our piping layer.  Hopefully its cool.
/obj/machinery/atmospherics/proc/setPipingLayer(new_layer)
	if(pipe_flags & (PIPING_DEFAULT_LAYER_ONLY|PIPING_ALL_LAYER))
		new_layer = PIPING_LAYER_DEFAULT
	piping_layer = new_layer
	// Do it the Polaris way
	switch(piping_layer)
		if(PIPING_LAYER_SCRUBBER)
			icon_state = "[icon_state]-scrubbers"
			connect_types = CONNECT_TYPE_SCRUBBER
			layer = PIPES_SCRUBBER_LAYER
			set_icon_connect_type("-scrubbers")
		if(PIPING_LAYER_SUPPLY)
			icon_state = "[icon_state]-supply"
			connect_types = CONNECT_TYPE_SUPPLY
			layer = PIPES_SUPPLY_LAYER
			set_icon_connect_type("-supply")
		if(PIPING_LAYER_FUEL)
			icon_state = "[icon_state]-fuel"
			connect_types = CONNECT_TYPE_FUEL
			layer = PIPES_FUEL_LAYER
			set_icon_connect_type("-fuel")
		if(PIPING_LAYER_AUX)
			icon_state = "[icon_state]-aux"
			connect_types = CONNECT_TYPE_AUX
			layer = PIPES_AUX_LAYER
			set_icon_connect_type("-aux")
	if(pipe_flags & PIPING_ALL_LAYER)
		connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_SUPPLY|CONNECT_TYPE_SCRUBBER|CONNECT_TYPE_FUEL|CONNECT_TYPE_AUX

/obj/machinery/atmospherics/proc/unsafe_pressure_release(mob/user, pressures = null)
	if(!user)
		return
	if(!pressures)
		var/datum/gas_mixture/int_air = return_air()
		var/datum/gas_mixture/env_air = loc.return_air()
		pressures = int_air.return_pressure() - env_air.return_pressure()

	act_message(user, null, MSG_SELF(span_userdanger("The pressure sends you flying!")), MSG_OTHERS(span_danger("%U% is sent flying by pressure!")))

	// if get_dir(src, user) is not 0, target is the edge_target_turf on that dir
	// otherwise, edge_target_turf uses a random cardinal direction
	// range is pressures / 250
	// speed is pressures / 1250
	if(user?.buckled_to())
		var/atom/movable/_tmp_buck_1 = user?.buckled_to()
		_tmp_buck_1.unbuckle_mob(user, TRUE)
	user.throw_at(get_edge_target_turf(user, get_dir(src, user) || pick(GLOB.cardinal)), pressures / 250, pressures / 1250)

/// Blows out a pipe, deconstructing it, breaking the floor and releasing all mobs crawling inside it
/obj/machinery/atmospherics/proc/blowout(mob/user)
	// Deconstruct turf
	var/turf/our_turf = loc
	if(!our_turf.is_plating() && istype(our_turf,/turf/simulated/floor)) //intact floor, pop the tile
		var/turf/simulated/floor/our_floor = our_turf
		our_floor.make_plating(TRUE)
	// Deconstruct pipe
	var/datum/gas_mixture/int_air = return_air()
	var/datum/gas_mixture/env_air = our_turf.return_air()
	var/internal_pressure = int_air.return_pressure()-env_air.return_pressure()
	atom_deconstruct()
	// Release pressure
	play_sfx(our_turf, SFX_EFFECTS_BANG, 1.4, vary = FALSE)
	play_sfx(our_turf, SFX_EFFECTS_CLANG2, 1.4, vary = FALSE)
	if(internal_pressure > 2*ONE_ATMOSPHERE)
		unsafe_pressure_release(user, internal_pressure)
		play_sfx(our_turf, SFX_MACHINES_HISS)


TRACKED_BRIDGED(/obj/machinery/atmospherics, rust_device_rev, CHANGE_MACHINE_SETTINGS)

/// The device's Rust law needs re-publishing (see rust_device_rev): push_to_rust() runs once this frame.
/obj/machinery/atmospherics/proc/rust_device_dirty()
	set_rust_device_rev(rust_device_rev + 1)

/// A power-mode change re-derives the device law (a device that is off is unregistered).
/obj/machinery/atmospherics/set_use_power(new_use_power)
	. = ..()
	if(.)
		rust_device_dirty()

/// Losing or regaining power changes whether the device runs.
/obj/machinery/atmospherics/power_change()
	. = ..()
	if(.)
		rust_device_dirty()
