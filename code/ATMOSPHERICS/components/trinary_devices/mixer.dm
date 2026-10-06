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

/obj/machinery/atmospherics/trinary/mixer/draw(datum/look/look)
	..()
	var/prefix = tee ? "t" : (mirrored ? "m" : "") // ALLOW(derived_reads): its orientation is fixed by its fitting; nothing changes it after it is built
	look.state("[prefix][(operable() && node1 && node2 && node3 && use_power) ? "on" : "off"]")

/obj/machinery/atmospherics/trinary/mixer/derived()
	. = ..()
	. += drawn_from(nameof(use_power))

/obj/machinery/atmospherics/trinary/mixer/Initialize(mapload)
	. = ..()

	air1.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_MIXER)
	air3.set_volume(ATMOS_DEFAULT_VOLUME_MIXER * 1.5)

/// A mixer is a Rust budget group (rust_set_budget_leg()): two input legs (port 1 and port 2 into port 3) with their shares.
/// The requested moles from the inputs' live gas, the entropy/power budget and the split are computed in Rust each device
/// step (power_budget.rs); this only declares the settings.
/obj/machinery/atmospherics/trinary/mixer/push_to_rust()
	if(QDELETED(src))
		return
	last_power_draw = 0
	last_flow_rate = 0
	if(!operable() || !use_power || !node1 || !node2 || !node3) // ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as do port binds and disconnect() (nodes, ports, modes)
		rust_unregister_device_n("in1")
		rust_unregister_device_n("in2")
		return
	var/available_power = material_pump_power(power_rating) // ALLOW(derived_reads): fixed by the material
	var/efficiency = ATMOS_FILTER_EFFICIENCY * (material_pump_efficiency() / 0.8)
	rust_set_budget_leg("in1", 1, 3, RUST_FLOW_MIX, 0, RUST_ROLE_OUTPUT, node1_concentration, set_flow_rate, available_power, efficiency)
	rust_set_budget_leg("in2", 2, 3, RUST_FLOW_MIX, 0, RUST_ROLE_OUTPUT, node2_concentration, set_flow_rate, available_power, efficiency)

/// A step's result: the moles the group moved and the power it drew, billed.
/obj/machinery/atmospherics/trinary/mixer/rust_device_stepped(moles, power_w, target_reached)
	last_power_draw = power_w
	if(power_w > 0)
		use_power(power_w)
	last_flow_rate = moles

/// A port bound: its region exists in Rust, so the legs can be registered once the last one is.
/obj/machinery/atmospherics/trinary/mixer/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 3)
		rust_device_dirty()

TRACKED(/obj/machinery/atmospherics/trinary/mixer, set_flow_rate)
TRACKED(/obj/machinery/atmospherics/trinary/mixer, node1_concentration)
TRACKED(/obj/machinery/atmospherics/trinary/mixer, node2_concentration)

/// The Rust group is pushed (once per frame) when any of these change.
/obj/machinery/atmospherics/trinary/mixer/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(set_flow_rate), nameof(node1_concentration), nameof(node2_concentration))

CAPABILITIES(/obj/machinery/atmospherics/trinary/mixer)
	pipe_device_window("AtmosMixer")
	op("power", ui_act("power"), then(PROC_REF(ui_power_switched)))
	op("pressure", ui_act("pressure", arg("pressure")), then(PROC_REF(ui_flow_rate_set)))
	op("node1", ui_act("node1", arg("concentration", num())), then(PROC_REF(ui_node1)))
	op("node2", ui_act("node2", arg("concentration", num())), then(PROC_REF(ui_node2)))

/// The window's data.
/obj/machinery/atmospherics/trinary/mixer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["on"] = use_power
	data["set_pressure"] = round(set_flow_rate)
	data["max_pressure"] = min(air1.return_volume(), air2.return_volume())
	data["node1_concentration"] = round(node1_concentration*100, 1)
	data["node2_concentration"] = round(node2_concentration*100, 1)
	var/list/node_connects = get_node_connect_dirs()
	data["node1_dir"] = dir_name(node_connects[1],TRUE)
	data["node2_dir"] = dir_name(node_connects[2],TRUE)
	return data

/obj/machinery/atmospherics/trinary/mixer/proc/ui_power_switched(datum/act/op/A)
	toggle_power()
	return OP_OK

/obj/machinery/atmospherics/trinary/mixer/proc/ui_flow_rate_set(datum/act/op/A, pressure)
	var/most = min(air1.return_volume(), air2.return_volume())
	if(pressure == "max")
		pressure = most
	if(isnum(pressure))
		set_set_flow_rate(clamp(pressure, 0, most))
	return OP_OK

/obj/machinery/atmospherics/trinary/mixer/proc/ui_node1(datum/act/op/A, concentration)
	set_node1_concentration(max(0, min(1, concentration / 100)))
	set_node2_concentration(1.0 - node1_concentration)
	return OP_OK

/obj/machinery/atmospherics/trinary/mixer/proc/ui_node2(datum/act/op/A, concentration)
	set_node2_concentration(max(0, min(1, concentration / 100)))
	set_node1_concentration(1.0 - node2_concentration)
	return OP_OK

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

/// A mixer missing a node can't run: it switches off when it loses one (the redraw used to do this).
/obj/machinery/atmospherics/trinary/mixer/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)

/obj/machinery/atmospherics/trinary/mixer/atmos_init()
	. = ..()
	if(!(node1 && node2 && node3))
		set_use_power(USE_POWER_OFF)
