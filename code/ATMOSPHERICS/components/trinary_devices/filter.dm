// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/obj/machinery/atmospherics/trinary/atmos_filter
	icon = 'icons/atmos/filter.dmi'
	icon_state = "map"
	construction_type = /obj/item/pipe/trinary/flippable
	pipe_state = "filter"
	density = FALSE
	level = 1

	name = "Gas filter"
	desc = "Filters one type of gas from an input, and pushes it out the side."

	use_power = USE_POWER_IDLE
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 7500	//This also doubles as a measure of how powerful the filter is, in Watts. 7500 W ~ 10 HP

	var/temp = null // -- TLE

	var/set_flow_rate = ATMOS_DEFAULT_VOLUME_FILTER

	/*
	Filter types:
		-1: Nothing
		0: Phoron: Phoron, Oxygen Agent B
		1: Oxygen: Oxygen ONLY
		2: Nitrogen: Nitrogen ONLY
		3: Carbon Dioxide: Carbon Dioxide ONLY
		4: Nitrous Oxide (Formerly called Sleeping Agent) (N2O)
		5: Methane: Methane only
	*/
	var/filter_type = -1

	var/frequency = ZERO_FREQ
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/trinary/atmos_filter/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_ATMOSIA))

/obj/machinery/atmospherics/trinary/atmos_filter/Initialize(mapload)
	. = ..()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	air3.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/trinary/atmos_filter/draw(datum/look/look)
	..()
	var/prefix = mirrored ? "m" : "" // ALLOW(derived_reads): its orientation is fixed by its fitting; nothing changes it after it is built
	look.state("[prefix][(operable() && node1 && node2 && node3 && use_power) ? "on" : "off"]")

/obj/machinery/atmospherics/trinary/atmos_filter/derived()
	. = ..()
	. += drawn_from(nameof(use_power))

/// The gases the filter takes out of the input, by its setting.
/obj/machinery/atmospherics/trinary/atmos_filter/proc/filtered_gas_ids()
	switch(filter_type)
		if(0) //removing hydrocarbons
			return list(GAS_PHORON, "oxygen_agent_b")
		if(1) //removing O2
			return list(GAS_O2)
		if(2) //removing N2
			return list(GAS_N2)
		if(3) //removing CO2
			return list(GAS_CO2)
		if(4)//removing N2O
			return list(GAS_N2O)
		if(5)//removing CH4
			return list(GAS_CH4)
	return list()

/// A filter is a Rust budget group (rust_set_budget_leg()): a filtered leg (port 1 to port 2) and a clean leg (port 1 to port 3).
/// The requested moles from the input's live gas, the entropy/power budget and the split between the legs are computed in
/// Rust each device step (power_budget.rs); this only declares the settings.
/obj/machinery/atmospherics/trinary/atmos_filter/push_to_rust()
	if(QDELETED(src))
		return
	last_power_draw = 0
	last_flow_rate = 0
	if(!operable() || !use_power || !node1 || !node2 || !node3) // ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as do port binds and disconnect() (nodes, ports, modes)
		rust_unregister_device_n("filtered")
		rust_unregister_device_n("clean")
		return
	var/mask = 0
	for(var/gas_id in filtered_gas_ids())
		mask |= (1 << GAS_IDX(gas_id))
	var/available_power = material_pump_power(power_rating) // ALLOW(derived_reads): fixed by the material
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	rust_set_budget_leg("filtered", 1, 2, RUST_FLOW_FILTER, mask, RUST_ROLE_OUTPUT, 0, set_flow_rate, available_power, efficiency)
	rust_set_budget_leg("clean", 1, 3, RUST_FLOW_FILTER, 0, RUST_ROLE_CLEAN, 0, set_flow_rate, available_power, efficiency)

/// A step's result: the moles the group moved and the power it drew, billed.
/obj/machinery/atmospherics/trinary/atmos_filter/rust_device_stepped(moles, power_w, target_reached)
	last_power_draw = power_w
	if(power_w > 0)
		use_power(power_w)
	var/before = air1.total_moles() + moles
	last_flow_rate = before > 0 ? (moles / before) * air1.return_volume() : 0

/// A port bound: its region exists in Rust, so the legs can be registered once the last one is.
/obj/machinery/atmospherics/trinary/atmos_filter/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 3)
		rust_device_dirty()

TRACKED(/obj/machinery/atmospherics/trinary/atmos_filter, set_flow_rate)
TRACKED(/obj/machinery/atmospherics/trinary/atmos_filter, filter_type)

/// The Rust group is pushed (once per frame) when any of these change.
/obj/machinery/atmospherics/trinary/atmos_filter/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(set_flow_rate), nameof(filter_type))

/// The window's data.
/obj/machinery/atmospherics/trinary/atmos_filter/ui_data(datum/act/eval/A)
	. = list()
	.["on"] = use_power
	.["rate"] = set_flow_rate
	var/list/part = ui_data_part_atmos_filter(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/atmospherics/trinary/atmos_filter/proc/ui_data_part_atmos_filter(datum/act/eval/A)
	var/list/data = list()

	data["max_rate"] = air1.return_volume()
	data["last_flow_rate"] = round(last_flow_rate, 0.1)

	data["filter_types"] = list()
	data["filter_types"] += list(list("name" = "Nothing", "f_type" = -1, "selected" = filter_type == -1))
	data["filter_types"] += list(list("name" = GASNAME_PHORON, "f_type" = 0, "selected" = filter_type == 0))
	data["filter_types"] += list(list("name" = GASNAME_O2, "f_type" = 1, "selected" = filter_type == 1))
	data["filter_types"] += list(list("name" = GASNAME_N2, "f_type" = 2, "selected" = filter_type == 2))
	data["filter_types"] += list(list("name" = GASNAME_CO2, "f_type" = 3, "selected" = filter_type == 3))
	data["filter_types"] += list(list("name" = GASNAME_N2O, "f_type" = 4, "selected" = filter_type == 4))
	data["filter_types"] += list(list("name" = GASNAME_CH4, "f_type" = 5, "selected" = filter_type == 5))

	return data

CAPABILITIES(/obj/machinery/atmospherics/trinary/atmos_filter)
	pipe_device_window("AtmosFilter")
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("rate", ui_act("rate", arg("rate")), then(PROC_REF(ui_act_rate)))
	op("filter", ui_act("filter", arg("filterset", num())), then(PROC_REF(ui_act_filter)))

/obj/machinery/atmospherics/trinary/atmos_filter/proc/ui_act_power(datum/act/op/A)
	toggle_power()
	return OP_OK

/obj/machinery/atmospherics/trinary/atmos_filter/proc/ui_act_rate(datum/act/op/A, rate)
	if(rate == "max")
		rate = air1.return_volume()
		. = TRUE
	else if(isnum(rate))
		. = TRUE
	if(.)
		set_set_flow_rate(clamp(rate, 0, air1.return_volume()))

/obj/machinery/atmospherics/trinary/atmos_filter/proc/ui_act_filter(datum/act/op/A, filterset)
	. = TRUE
	set_filter_type(filterset)

//
// Mirrored Orientation - Flips the output dir to opposite side from normal.
//
/obj/machinery/atmospherics/trinary/atmos_filter/m_filter
	icon_state = "mmap"
	dir = SOUTH
	initialize_directions = SOUTH|NORTH|EAST
	mirrored = TRUE

/// A filter missing a node can't run: it switches off when it loses one (the redraw used to do this).
/obj/machinery/atmospherics/trinary/atmos_filter/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)

/obj/machinery/atmospherics/trinary/atmos_filter/atmos_init()
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)
