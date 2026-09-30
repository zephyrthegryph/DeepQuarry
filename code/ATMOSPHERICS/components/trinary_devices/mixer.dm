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

	// Input shares. These are the settings; the air datums they apply to are
	// rebound whenever the pipe topology commits, so nothing is keyed by them.
	var/node1_concentration = 0.5
	var/node2_concentration = 0.5

	//node 3 is the outlet, nodes 1 & 2 are intakes

/obj/machinery/atmospherics/trinary/mixer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_APPEARANCE_PROC(/obj/machinery/atmospherics/trinary/mixer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/atmospherics/trinary/mixer/appearance_overlays()
	. = list()
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

/obj/machinery/atmospherics/trinary/mixer/Initialize(mapload)
	. = ..()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)
	air3.set_volume(ATMOS_DEFAULT_VOLUME_MIXER * 1.5)

/// The gas -> share list mix_gas() takes, built from the current port air.
/obj/machinery/atmospherics/trinary/mixer/proc/mixing_inputs()
	var/list/inputs = list()
	inputs[air1] = node1_concentration
	inputs[air2] = node2_concentration
	return inputs

/// R10/M2 bridge (rust_architecture.md §8.5 step 6's filter/mixer slice):
/// a mixer is two input flows (port1->port3, port2->port3), each a plain
/// `DeviceFlow` row (mask 0: every gas) with `RUST_FLOW_MOLES`, ratio-
/// scaled by `vg_mix_transfer()` -- the entropy-limited power budget that
/// used to gate `mix_gas()`, unchanged maths, now in Rust
/// (`verdigris/domains/gas/src/power_budget.rs`). The actual gas movement
/// is Rust's own device-edge step, same as every other pipe device.
/obj/machinery/atmospherics/trinary/mixer/machine_step()
	..()

	last_power_draw = 0
	last_flow_rate = 0

	if((!operable()) || !use_power)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		return PROCESS_KILL

	//Figure out the amount of moles to transfer
	var/requested = mix_transfer_moles()
	if(requested <= MINIMUM_MOLES_TO_FILTER)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		hibernate_until_input_changes()
		return PROCESS_KILL

	var/available_power = material_pump_power(power_rating)
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	var/list/result = vg_mix_transfer(mixing_inputs(), air3, requested, available_power, efficiency)
	if(!result)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		return 1

	var/power_draw = result[2]
	var/in1_moles = result[3]
	var/in2_moles = result[4]
	var/dt = NATIVE_PIPE_DEVICE_PERIOD

	last_power_draw = power_draw
	use_power(power_draw)

	rust_set_device_n("in1", 1, 3)
	rust_set_device_flow_n("in1", 0, RUST_FLOW_MOLES, in1_moles / dt, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	rust_set_device_n("in2", 2, 3)
	rust_set_device_flow_n("in2", 0, RUST_FLOW_MOLES, in2_moles / dt, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

	if(network1 && node1_concentration)
		network1.mark_dirty()

	if(network2 && node2_concentration)
		network2.mark_dirty()

	if(network3)
		network3.mark_dirty()

	return 1

DECLARE_UI(/obj/machinery/atmospherics/trinary/mixer, "AtmosMixer")

UI_DATA_REPLACE(/obj/machinery/atmospherics/trinary/mixer, "on=use_power", "merge:ui_data_obj_machinery_atmospherics_trinary_mixer{set_pressure:num,max_pressure:num,node1_concentration:num,node2_concentration:num,node1_dir:text,node2_dir:text}")

/// The computed part of /obj/machinery/atmospherics/trinary/mixer's window data (declared on its UI_DATA row).
/obj/machinery/atmospherics/trinary/mixer/proc/ui_data_obj_machinery_atmospherics_trinary_mixer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["set_pressure"] = round(set_flow_rate)
	data["max_pressure"] = min(air1.return_volume(), air2.return_volume())
	data["node1_concentration"] = round(node1_concentration*100, 1)
	data["node2_concentration"] = round(node2_concentration*100, 1)
	var/list/node_connects = get_node_connect_dirs()
	data["node1_dir"] = dir_name(node_connects[1],TRUE)
	data["node2_dir"] = dir_name(node_connects[2],TRUE)
	return data

UI_ACT(/obj/machinery/atmospherics/trinary/mixer, "power", ui_act_power)
UI_ACT_PROC(/obj/machinery/atmospherics/trinary/mixer, ui_act_power)
	set_use_power(!use_power)
	. = TRUE
	update_icon()
	MACHINE_WAKE(src) // settings: re-evaluate the mix now

UI_ACT(/obj/machinery/atmospherics/trinary/mixer, "pressure", ui_act_pressure, UI_ARG_VALUE("pressure"))
UI_ACT_PROC(/obj/machinery/atmospherics/trinary/mixer, ui_act_pressure)
	var/pressure = params["pressure"]
	if(pressure == "max")
		pressure = min(air1.return_volume(), air2.return_volume())
		. = TRUE
	else if(isnum(pressure))
		. = TRUE
	if(.)
		set_flow_rate = clamp(pressure, 0, min(air1.return_volume(), air2.return_volume()))
	update_icon()
	MACHINE_WAKE(src) // settings: re-evaluate the mix now

UI_ACT(/obj/machinery/atmospherics/trinary/mixer, "node1", ui_act_node1, UI_ARG_NUM("concentration"))
UI_ACT_PROC(/obj/machinery/atmospherics/trinary/mixer, ui_act_node1)
	var/value = params["concentration"]
	node1_concentration = max(0, min(1, value / 100))
	node2_concentration = 1.0 - node1_concentration
	. = TRUE
	update_icon()
	MACHINE_WAKE(src) // settings: re-evaluate the mix now

UI_ACT(/obj/machinery/atmospherics/trinary/mixer, "node2", ui_act_node2, UI_ARG_NUM("concentration"))
UI_ACT_PROC(/obj/machinery/atmospherics/trinary/mixer, ui_act_node2)
	var/value = params["concentration"]
	node2_concentration = max(0, min(1, value / 100))
	node1_concentration = 1.0 - node2_concentration
	. = TRUE
	update_icon()
	MACHINE_WAKE(src) // settings: re-evaluate the mix now

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

/obj/machinery/atmospherics/trinary/mixer/proc/mix_transfer_moles()
	return (set_flow_rate*node1_concentration/air1.return_volume())*air1.total_moles() + (set_flow_rate*node2_concentration/air2.return_volume())*air2.total_moles()

/// Nothing to mix: park until the inputs hold enough to move (the same test machine_step()
/// makes). Power and settings changes wake it through their own channels.
/obj/machinery/atmospherics/trinary/mixer/proc/hibernate_until_input_changes()
	om_watch_arm_condition(src, "gas", list(air1?.arena_id(), air2?.arena_id()), GAS_DEPENDENCY_COMPOSITION | GAS_DEPENDENCY_PRESSURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))

/obj/machinery/atmospherics/trinary/mixer/proc/gas_wake_condition()
	return use_power && operable() && mix_transfer_moles() > MINIMUM_MOLES_TO_FILTER

/obj/machinery/atmospherics/trinary/mixer/proc/wake_from_gas()
	om_watch_disarm(src, "gas")
	MACHINE_WAKE(src)

/obj/machinery/atmospherics/trinary/mixer/step_has_work()
	return gas_wake_condition()

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/atmospherics/trinary/mixer/arm_wakes()
	..()
	hibernate_until_input_changes()

/// A mixer missing a node can't run: it switches off when it loses one (the redraw used to do this).
/obj/machinery/atmospherics/trinary/mixer/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)

/obj/machinery/atmospherics/trinary/mixer/atmos_init()
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)
