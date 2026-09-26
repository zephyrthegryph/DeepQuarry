// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/obj/machinery/atmospherics/trinary/mixer
	icon = 'icons/atmos/mixer.dmi'
	icon_state = "map"
	construction_type = /obj/item/pipe/trinary/flippable
	pipe_state = "mixer"
	density = FALSE
	level = 1

	name = "Gas mixer"

	use_power = USE_POWER_IDLE
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 3700	//This also doubles as a measure of how powerful the mixer is, in Watts. 3700 W ~ 5 HP

	var/set_flow_rate = ATMOS_DEFAULT_VOLUME_MIXER
	var/list/mixing_inputs

	//for mapping
	var/node1_concentration = 0.5
	var/node2_concentration = 0.5

	//node 3 is the outlet, nodes 1 & 2 are intakes

/obj/machinery/atmospherics/trinary/mixer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/obj/machinery/atmospherics/trinary/mixer/update_icon(safety = 0)
	if(tee)
		icon_state = "t"
	else if(mirrored)
		icon_state = "m"
	else
		icon_state = ""

	if(!powered())
		icon_state += "off"
	else if(node2 && node3 && node1)
		icon_state += use_power ? "on" : "off"
	else
		icon_state += "off"
		update_use_power(USE_POWER_OFF)

/obj/machinery/atmospherics/trinary/mixer/Initialize(mapload)
	. = ..()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)
	air3.set_volume(ATMOS_DEFAULT_VOLUME_MIXER * 1.5)

	if (!mixing_inputs)
		mixing_inputs = list(src.air1 = node1_concentration, src.air2 = node2_concentration)

/// R10/M2 bridge (rust_architecture.md §8.5 step 6's filter/mixer slice):
/// a mixer is two input flows (port1->port3, port2->port3), each a plain
/// `DeviceFlow` row (mask 0: every gas) with `RUST_FLOW_MOLES`, ratio-
/// scaled by `vg_mix_transfer()` -- the entropy-limited power budget that
/// used to gate `mix_gas()`, unchanged maths, now in Rust
/// (`verdigris/domains/gas/src/power_budget.rs`). The actual gas movement
/// is Rust's own device-edge step, same as every other pipe device.
/obj/machinery/atmospherics/trinary/mixer/process()
	..()

	last_power_draw = 0
	last_flow_rate = 0

	if((stat & (NOPOWER|BROKEN)) || !use_power)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		return 1

	//Figure out the amount of moles to transfer
	var/requested = (set_flow_rate*mixing_inputs[air1]/air1.return_volume())*air1.total_moles() + (set_flow_rate*mixing_inputs[air2]/air2.return_volume())*air2.total_moles()
	if(requested <= MINIMUM_MOLES_TO_FILTER)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		return 1

	var/available_power = material_pump_power(power_rating)
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	var/list/result = vg_mix_transfer(mixing_inputs, air3, requested, available_power, efficiency)
	if(!result)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		return 1

	var/power_draw = result[2]
	var/in1_moles = result[3]
	var/in2_moles = result[4]
	var/dt = SSvg.wait / (1 SECONDS)

	last_power_draw = power_draw
	use_power(power_draw)

	rust_set_device_n("in1", 1, 3)
	rust_set_device_flow_n("in1", 0, RUST_FLOW_MOLES, in1_moles / dt, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	rust_set_device_n("in2", 2, 3)
	rust_set_device_flow_n("in2", 0, RUST_FLOW_MOLES, in2_moles / dt, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	if(network1 && mixing_inputs[air1])
		network1.mark_dirty()

	if(network2 && mixing_inputs[air2])
		network2.mark_dirty()

	if(network3)
		network3.mark_dirty()

	return 1

/obj/machinery/atmospherics/trinary/mixer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AtmosMixer", name)
		ui.open()

/obj/machinery/atmospherics/trinary/mixer/tgui_data(mob/user)
	var/list/data = list()
	data["on"] = use_power
	data["set_pressure"] = round(set_flow_rate)
	data["max_pressure"] = min(air1.return_volume(), air2.return_volume())
	data["node1_concentration"] = round(mixing_inputs[air1]*100, 1)
	data["node2_concentration"] = round(mixing_inputs[air2]*100, 1)
	var/list/node_connects = get_node_connect_dirs()
	data["node1_dir"] = dir_name(node_connects[1],TRUE)
	data["node2_dir"] = dir_name(node_connects[2],TRUE)
	return data

/obj/machinery/atmospherics/trinary/mixer/tgui_act(action, params)
	if(..())
		return TRUE

	switch(action)
		if("power")
			update_use_power(!use_power)
			. = TRUE
		if("pressure")
			var/pressure = params["pressure"]
			if(pressure == "max")
				pressure = min(air1.return_volume(), air2.return_volume())
				. = TRUE
			else if(text2num(pressure) != null)
				pressure = text2num(pressure)
				. = TRUE
			if(.)
				set_flow_rate = clamp(pressure, 0, min(air1.return_volume(), air2.return_volume()))
		if("node1")
			var/value = text2num(params["concentration"])
			mixing_inputs[air1] = max(0, min(1, value / 100))
			mixing_inputs[air2] = 1.0 - mixing_inputs[air1]
			. = TRUE
		if("node2")
			var/value = text2num(params["concentration"])
			mixing_inputs[air2] = max(0, min(1, value / 100))
			mixing_inputs[air1] = 1.0 - mixing_inputs[air2]
			. = TRUE
	update_icon()

//
// "T" Orientation - Inputs are on oposite sides instead of adjacent
//
/obj/machinery/atmospherics/trinary/mixer/t_mixer
	icon_state = "tmap"
	construction_type = /obj/item/pipe/trinary  // Can't flip a "T", its symmetrical
	pipe_state = "t_mixer"
	dir = SOUTH
	initialize_directions = SOUTH|EAST|WEST
	tee = TRUE

//
// Mirrored Orientation - Flips the output dir to opposite side from normal.
//
/obj/machinery/atmospherics/trinary/mixer/m_mixer
	icon_state = "mmap"
	dir = SOUTH
	initialize_directions = SOUTH|NORTH|EAST
	mirrored = TRUE
