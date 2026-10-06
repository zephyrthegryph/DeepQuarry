#define EXTERNAL_PRESSURE_BOUND ONE_ATMOSPHERE
#define INTERNAL_PRESSURE_BOUND 0
#define PRESSURE_CHECKS 1

#define PRESSURE_CHECK_EXTERNAL 1
#define PRESSURE_CHECK_INPUT 2
#define PRESSURE_CHECK_OUTPUT 4

/obj/machinery/atmospherics/binary/dp_vent_pump
	icon = 'icons/atmos/vent_pump.dmi'
	icon_state = "map_dp_vent"

	//node2 is output port
	//node1 is input port

	name = "Dual Port Air Vent"
	desc = "Has a valve and pump attached to it. There are two ports."

	level = 1

	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 7500			//7500 W ~ 10 HP

	pipe_flags = PIPING_ALL_LAYER
	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_SUPPLY|CONNECT_TYPE_SCRUBBER //connects to regular, supply and scrubbers pipes

	var/pump_direction = 1 //0 = siphoning, 1 = releasing

	var/external_pressure_bound = EXTERNAL_PRESSURE_BOUND
	var/input_pressure_min = INTERNAL_PRESSURE_BOUND
	var/output_pressure_max = 10000

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

	var/pressure_checks = PRESSURE_CHECK_EXTERNAL
	//1: Do not pass external_pressure_bound
	//2: Do not pass input_pressure_min
	//4: Do not pass output_pressure_max

/obj/machinery/atmospherics/binary/dp_vent_pump/Initialize(mapload)
	. = ..()
	if(frequency)
		set_frequency(frequency)

	air1.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)
	icon = null

/obj/machinery/atmospherics/binary/dp_vent_pump/disconnect(obj/machinery/atmospherics/reference)
	rust_device_dirty()
	return ..()

/// Its turf is the device's other side: a new one is a new edge.
/obj/machinery/atmospherics/binary/dp_vent_pump/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	rust_device_dirty()

/obj/machinery/atmospherics/binary/dp_vent_pump/high_volume
	name = "Large Dual Port Air Vent"

/obj/machinery/atmospherics/binary/dp_vent_pump/high_volume/Initialize(mapload)
	. = ..()
	air1.set_volume(ATMOS_DEFAULT_VOLUME_PUMP + 800)
	air2.set_volume(ATMOS_DEFAULT_VOLUME_PUMP + 800)

/obj/machinery/atmospherics/binary/dp_vent_pump/draw(datum/look/look)
	..()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	var/vent_icon = "vent"
	// ALLOW(sys_dx_untracked_read): a pipe's level and a floor's plating are fixed while the vent stands on them; a change of either rebuilds the pipes
	if(!T.is_plating() && node1 && node2 && node1.level == 1 && node2.level == 1 && istype(node1, /obj/machinery/atmospherics/pipe) && istype(node2, /obj/machinery/atmospherics/pipe)) // ALLOW(derived_reads): atmos_init() and disconnect() redraw it when its pipes come or go
		vent_icon += "h"
	if(!operable() || !use_power)
		vent_icon += "off"
	else
		vent_icon += pump_direction ? "out" : "in"
	look.overlay(GLOB.icon_manager.get_atmos_icon("device", , , vent_icon))

/obj/machinery/atmospherics/binary/dp_vent_pump/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	if(!T.is_plating() && node1 && node2 && node1.level == 1 && node2.level == 1 && istype(node1, /obj/machinery/atmospherics/pipe) && istype(node2, /obj/machinery/atmospherics/pipe))
		return
	else
		if (node1)
			add_underlay(T, node1, turn(dir, -180), node1.icon_connect_type)
		else
			add_underlay(T, node1, turn(dir, -180))
		if (node2)
			add_underlay(T, node2, dir, node2.icon_connect_type)
		else
			add_underlay(T, node2, dir)

/obj/machinery/atmospherics/binary/dp_vent_pump/hide(i)
	changed(src)
	update_underlays()

/// Its flow law is a Rust device edge (the same shape as the vent pump's): the port it works through and the
/// turf are its two sides. rust_bind_pipe_port fires once per port, so the second one is the earliest both are live.
/obj/machinery/atmospherics/binary/dp_vent_pump/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 2)
		rust_device_dirty()

/// Publishes (or unpublishes) the vent's Rust device edge: releasing it pushes port 1's gas out to the turf, siphoning it
/// pulls the turf's into port 2, both at `power_rating` (device.rs's Power rate) and stopping where the enabled
/// checks say. The turf is side `a`: the external bound is the stop (released gas fills the turf up to it, siphoning
/// drains it down to it) and the input / output check of the port side the limit (a cap only).
/obj/machinery/atmospherics/binary/dp_vent_pump/push_to_rust()
	if(QDELETED(src))
		return
	// ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev, as does a port bind or disconnect() (node1, node2)
	if(!use_power || !operable() || !isturf(loc) || !(pump_direction ? node1 : node2))
		rust_unregister_device()
		return
	var/datum/gas_mixture/environment = loc.return_air()
	if(!environment)
		rust_unregister_device()
		return
	var/stop_side = RUST_SIDE_A
	var/stop_cmp = RUST_STOP_NONE
	var/stop_kpa = 0
	var/limit_side = RUST_SIDE_B
	var/limit_cmp = RUST_STOP_NONE
	var/limit_kpa = 0
	if(pump_direction) // internal -> external
		if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
			stop_cmp = RUST_STOP_AT_LEAST
			stop_kpa = external_pressure_bound
		if(pressure_checks & PRESSURE_CHECK_INPUT)
			limit_cmp = RUST_STOP_AT_MOST
			limit_kpa = input_pressure_min
	else // external -> internal
		if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
			stop_cmp = RUST_STOP_AT_MOST
			stop_kpa = external_pressure_bound
		if(pressure_checks & PRESSURE_CHECK_OUTPUT)
			limit_cmp = RUST_STOP_AT_LEAST
			limit_kpa = output_pressure_max
	if(stop_cmp == RUST_STOP_NONE)
		if(limit_cmp != RUST_STOP_NONE)
			// Only a port-side check: it is the stop.
			stop_side = limit_side
			stop_cmp = limit_cmp
			stop_kpa = limit_kpa
			limit_cmp = RUST_STOP_NONE
		else
			// No check at all: the turf fills without bound (releasing) or drains to nothing (siphoning).
			stop_cmp = pump_direction ? RUST_STOP_AT_LEAST : RUST_STOP_AT_MOST
			stop_kpa = pump_direction ? 1e30 : 0
	rust_set_turf_device(pump_direction ? 1 : 2, environment)
	rust_set_device_flow(0, RUST_FLOW_POWER, power_rating, RUST_DIR_FORCED, stop_side, stop_cmp, stop_kpa, limit_side, limit_cmp, limit_kpa) // ALLOW(derived_reads): power_rating is fixed by the type

/// A step's result: the flow and the power it drew, billed.
/obj/machinery/atmospherics/binary/dp_vent_pump/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)
	last_power_draw = power_w
	if(power_w > 0)
		use_power(power_w)

TRACKED(/obj/machinery/atmospherics/binary/dp_vent_pump, pump_direction)
TRACKED(/obj/machinery/atmospherics/binary/dp_vent_pump, external_pressure_bound)
TRACKED(/obj/machinery/atmospherics/binary/dp_vent_pump, input_pressure_min)
TRACKED(/obj/machinery/atmospherics/binary/dp_vent_pump, output_pressure_max)
TRACKED(/obj/machinery/atmospherics/binary/dp_vent_pump, pressure_checks)

/// The Rust device law is pushed (once per frame) when any of these change.
/obj/machinery/atmospherics/binary/dp_vent_pump/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(pump_direction), nameof(external_pressure_bound), nameof(input_pressure_min), nameof(output_pressure_max), nameof(pressure_checks))
	. += drawn_from(nameof(use_power), nameof(pump_direction))

//Radio remote control

/obj/machinery/atmospherics/binary/dp_vent_pump/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, radio_filter = RADIO_ATMOSIA))

/obj/machinery/atmospherics/binary/dp_vent_pump/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)

	signal.data = list(
		"tag" = id,
		"device" = "ADVP",
		"power" = use_power,
		"direction" = pump_direction?("release"):("siphon"),
		"checks" = pressure_checks,
		"input" = input_pressure_min,
		"output" = output_pressure_max,
		"external" = external_pressure_bound,
		"sigtype" = "status"
	)
	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)

	return 1

CAPABILITIES(/obj/machinery/atmospherics/binary/dp_vent_pump)
	examine_line(PROC_REF(gauge_text))

/// The gauge, to someone beside it.
/obj/machinery/atmospherics/binary/dp_vent_pump/proc/gauge_text(datum/act/eval/A)
	var/mob/viewer = A.actor
	if(viewer && Adjacent(viewer))
		return "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s; [round(last_power_draw)] W"

/obj/machinery/atmospherics/binary/dp_vent_pump/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0
	if(signal.data["power"])
		set_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"])
		set_use_power(!use_power)

	if(signal.data["direction"])
		set_pump_direction(text2num(signal.data["direction"]))

	if(signal.data["checks"])
		set_pressure_checks(text2num(signal.data["checks"]))

	if(signal.data["purge"])
		set_pressure_checks(pressure_checks & ~1)
		set_pump_direction(0)

	if(signal.data["stabalize"])
		set_pressure_checks(pressure_checks | 1)
		set_pump_direction(1)

	if(signal.data["set_input_pressure"])
		set_input_pressure_min(between(0, text2num(signal.data["set_input_pressure"]), ONE_ATMOSPHERE*50))

	if(signal.data["set_output_pressure"])
		set_output_pressure_max(between(0, text2num(signal.data["set_output_pressure"]), ONE_ATMOSPHERE*50))

	if(signal.data["set_external_pressure"])
		set_external_pressure_bound(between(0, text2num(signal.data["set_external_pressure"]), ONE_ATMOSPHERE*50))

	if(signal.data["status"])
		after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
		return //do not update_icon

	after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
	changed(src)

#undef EXTERNAL_PRESSURE_BOUND
#undef INTERNAL_PRESSURE_BOUND
#undef PRESSURE_CHECKS

#undef PRESSURE_CHECK_EXTERNAL
#undef PRESSURE_CHECK_INPUT
#undef PRESSURE_CHECK_OUTPUT
