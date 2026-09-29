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
	var/list/filtered_out = list() // ALLOW(instance_list): atmos area (M1a): trinary filter pipe device; listed in memory_lists_audit.md, not edited here

	var/frequency = ZERO_FREQ
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/trinary/atmos_filter/proc/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, "radio_connection", GLOB.radio_service.add_object(src, frequency, RADIO_ATMOSIA))

/obj/machinery/atmospherics/trinary/atmos_filter/Initialize(mapload)
	. = ..()

	switch(filter_type)
		if(0) //removing hydrocarbons
			filtered_out = list(GAS_PHORON)
		if(1) //removing O2
			filtered_out = list(GAS_O2)
		if(2) //removing N2
			filtered_out = list(GAS_N2)
		if(3) //removing CO2
			filtered_out = list(GAS_CO2)
		if(4)//removing N2O
			filtered_out = list(GAS_N2O)
		if(5)//removing CH4
			filtered_out = list(GAS_CH4)

	air1.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	air3.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	if(frequency)
		set_frequency(frequency)

DECLARE_APPEARANCE_PROC(/obj/machinery/atmospherics/trinary/atmos_filter, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/atmospherics/trinary/atmos_filter/appearance_overlays()
	. = list()
	if(mirrored)
		icon_state = "m"
	else
		icon_state = ""

	if(!powered())
		icon_state += "off"
	else if(node2 && node3 && node1)
		icon_state += use_power ? "on" : "off"
	else
		icon_state += "off"

/// R10/M2 bridge (rust_architecture.md §8.5 step 6's filter/mixer slice):
/// a filter is a masked flow to the filter port plus a pass-through flow
/// on the same two Rust device edges (source->filtered, source->clean),
/// each a plain `DeviceFlow` row with `RUST_FLOW_MOLES`. The entropy-
/// limited power budget that used to gate `filter_gas()` is unchanged
/// maths, now in Rust (`vg_filter_transfer()`,
/// `verdigris/domains/gas/src/power_budget.rs`) -- this proc only
/// resolves the filtering mask, calls that once, and republishes the two
/// flows' `rate` from the result; the actual gas movement is Rust's own
/// device-edge step, same as every other pipe device.
/obj/machinery/atmospherics/trinary/atmos_filter/machine_step()
	..()

	last_power_draw = 0
	last_flow_rate = 0

	if((!operable()) || !use_power)
		rust_unregister_device_n("filtered")
		rust_unregister_device_n("clean")
		return PROCESS_KILL

	var/mask = 0
	for(var/gas_id in filtered_out)
		mask |= (1 << GAS_IDX(gas_id))

	var/requested = (set_flow_rate/air1.return_volume())*air1.total_moles()
	if(requested <= MINIMUM_MOLES_TO_FILTER)
		rust_unregister_device_n("filtered")
		rust_unregister_device_n("clean")
		hibernate_until_input_changes()
		return PROCESS_KILL

	var/available_power = material_pump_power(power_rating)
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	var/list/result = vg_filter_transfer(air1, air2, air3, mask, requested, available_power, efficiency)
	if(!result)
		rust_unregister_device_n("filtered")
		rust_unregister_device_n("clean")
		return 1

	var/total_transfer_moles = result[1]
	var/filterable_moles = result[2]
	var/unfilterable_moles = result[3]
	var/power_draw = result[4]
	var/considered_moles = filterable_moles + unfilterable_moles
	var/dt = SSvg.wait / (1 SECONDS)

	last_flow_rate = (total_transfer_moles/air1.total_moles())*air1.return_volume()
	last_power_draw = power_draw
	use_power(power_draw)

	rust_set_device_n("filtered", 1, 2)
	rust_set_device_flow_n("filtered", mask, RUST_FLOW_MOLES, considered_moles > 0 ? (total_transfer_moles * filterable_moles / considered_moles) / dt : 0, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	rust_set_device_n("clean", 1, 3)
	rust_set_device_flow_n("clean", RUST_ALL_GASES_MASK & ~mask, RUST_FLOW_MOLES, considered_moles > 0 ? (total_transfer_moles * unfilterable_moles / considered_moles) / dt : 0, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	if(network2)
		network2.mark_dirty()

	if(network3)
		network3.mark_dirty()

	if(network1)
		network1.mark_dirty()

	return 1

/obj/machinery/atmospherics/trinary/atmos_filter/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/atmos_filter_use,
	)
	..()

/datum/interaction/machine_hand/atmos_filter_use
	id = "atmos_filter_use"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/trinary/atmos_filter/proc/lets_in, "access denied"))
	effect = /atom/proc/interaction_open_ui

/obj/machinery/atmospherics/trinary/atmos_filter/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/atmospherics/trinary/atmos_filter/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AtmosFilter", name)
		ui.open()

/obj/machinery/atmospherics/trinary/atmos_filter/tgui_data(mob/user)
	var/list/data = list()

	data["on"] = use_power
	data["rate"] = set_flow_rate
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

/obj/machinery/atmospherics/trinary/atmos_filter/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("power")
			set_use_power(!use_power)
		if("rate")
			var/rate = params["rate"]
			if(rate == "max")
				rate = air1.return_volume()
				. = TRUE
			else if(text2num(rate) != null)
				rate = text2num(rate)
				. = TRUE
			if(.)
				set_flow_rate = clamp(rate, 0, air1.return_volume())
		if("filter")
			. = TRUE
			filter_type = text2num(params["filterset"])
			filtered_out.Cut()	//no need to create new lists unnecessarily
			switch(filter_type)
				if(0) //removing hydrocarbons
					filtered_out += GAS_PHORON
					filtered_out += "oxygen_agent_b"
				if(1) //removing O2
					filtered_out += GAS_O2
				if(2) //removing N2
					filtered_out += GAS_N2
				if(3) //removing CO2
					filtered_out += GAS_CO2
				if(4)//removing N2O
					filtered_out += GAS_N2O
				if(5)//removing CH4
					filtered_out += GAS_CH4

	add_fingerprint(ui.user)
	update_icon()
	MACHINE_WAKE(src) // settings: re-evaluate the filter now

//
// Mirrored Orientation - Flips the output dir to opposite side from normal.
//
/obj/machinery/atmospherics/trinary/atmos_filter/m_filter
	icon_state = "mmap"
	dir = SOUTH
	initialize_directions = SOUTH|NORTH|EAST
	mirrored = TRUE

/// Nothing to filter: park until the input holds enough to move (the same test machine_step()
/// makes). Power and settings changes wake it through their own channels.
/obj/machinery/atmospherics/trinary/atmos_filter/proc/hibernate_until_input_changes()
	om_watch_arm_condition(src, "gas", list(air1?.arena_id()), GAS_DEPENDENCY_COMPOSITION | GAS_DEPENDENCY_PRESSURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))

/obj/machinery/atmospherics/trinary/atmos_filter/proc/gas_wake_condition()
	return use_power && operable() && (set_flow_rate / air1.return_volume()) * air1.total_moles() > MINIMUM_MOLES_TO_FILTER

/obj/machinery/atmospherics/trinary/atmos_filter/proc/wake_from_gas()
	om_watch_disarm(src, "gas")
	MACHINE_WAKE(src)

/obj/machinery/atmospherics/trinary/atmos_filter/step_has_work()
	return gas_wake_condition()

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/atmospherics/trinary/atmos_filter/arm_wakes()
	..()
	hibernate_until_input_changes()

/// A filter missing a node can't run: it switches off when it loses one (the redraw used to do this).
/obj/machinery/atmospherics/trinary/atmos_filter/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)

/obj/machinery/atmospherics/trinary/atmos_filter/atmos_init()
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)
