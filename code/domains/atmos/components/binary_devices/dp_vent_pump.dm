// PRESSURE_CHECK_EXTERNAL / _INPUT / _OUTPUT are the Rust pressure_checks bits (verdigris/domains/gas/src/kind/devices.rs, generated into the DM defines).

/obj/machinery/atmospherics/binary/dp_vent_pump
	air2_volume = ATMOS_DEFAULT_VOLUME_PUMP
	air1_volume = ATMOS_DEFAULT_VOLUME_PUMP
	icon = 'icons/atmos/vent_pump.dmi'
	icon_state = "map_dp_vent"

	//node2 is output port
	//node1 is input port

	name = "Dual Port Air Vent"
	desc = "Has a valve and pump attached to it. There are two ports."

	level = 1

	use_power = USE_POWER_OFF
	init_power_rating = 7500			//7500 W ~ 10 HP, the Rust-owned rate the vent draws at

	pipe_flags = PIPING_ALL_LAYER
	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_SUPPLY|CONNECT_TYPE_SCRUBBER //connects to regular, supply and scrubbers pipes

	var/pump_direction = 1 //0 = siphoning, 1 = releasing

	// The bounds and the checks are the vent's Rust component's (get_/set_ over native_write()): there is no var for them.
	init_external_pressure_bound = ONE_ATMOSPHERE
	init_input_pressure_min = 0
	init_output_pressure_max = 10000

	var/frequency = ZERO_FREQ
	var/id = null
	var/datum/radio_frequency/radio_connection

	init_pressure_checks = PRESSURE_CHECK_EXTERNAL
	//1: Do not pass external_pressure_bound
	//2: Do not pass input_pressure_min
	//4: Do not pass output_pressure_max

/obj/machinery/atmospherics/binary/dp_vent_pump/proc/prepare_vent_renderer()

	set_icon(null)

/// Its turf is the device's other side: a new one is a new edge.
/obj/machinery/atmospherics/binary/dp_vent_pump/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	rust_device_dirty()

/obj/machinery/atmospherics/binary/dp_vent_pump/high_volume
	air2_volume = ATMOS_DEFAULT_VOLUME_PUMP + 800
	air1_volume = ATMOS_DEFAULT_VOLUME_PUMP + 800
	name = "Large Dual Port Air Vent"

/obj/machinery/atmospherics/binary/dp_vent_pump/draw(datum/look/look)
	..()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	var/vent_icon = "vent"
	if(!T.is_plating() && node1 && node2 && node1.level == 1 && node2.level == 1 && istype(node1, /obj/machinery/atmospherics/pipe) && istype(node2, /obj/machinery/atmospherics/pipe))
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
	update_underlays()

/// The vent's flow law is its own DpVentPump component (rust_bindings.md section 14): releasing it pushes port 1's gas out to the turf, siphoning it
/// pulls the turf's into port 2, at its power rating and stopping where the enabled checks say. What DM publishes is the device edge, between the
/// active port and the turf it stands on (side A), and the inputs it owns: which way it faces and whether it runs.
/obj/machinery/atmospherics/binary/dp_vent_pump/push_to_rust()
	if(QDELETED(src))
		return
	rust_push_inputs()
	var/datum/gas_mixture/environment = isturf(loc) ? loc.return_air() : null
	if(!environment || !(pump_direction ? node1 : node2))
		rust_unregister_device()
		return
	rust_set_turf_device(pump_direction ? 1 : 2, environment)

/// Pushes the inputs DM owns to the component: which way it faces, and whether it runs.
/obj/machinery/atmospherics/binary/dp_vent_pump/rust_push_inputs()
	if(vg_entity)
		push_pump_direction(dp_vent_pump_input_pump_direction())
	rust_push_running()

/obj/machinery/atmospherics/binary/dp_vent_pump/rust_device_binds_self()
	return TRUE

/obj/machinery/atmospherics/binary/dp_vent_pump/dp_vent_pump_input_pump_direction()
	return pump_direction

/// It moves gas: switched on, powered, operable and standing on a turf.
/obj/machinery/atmospherics/binary/dp_vent_pump/dp_vent_pump_input_running()
	return !!(use_power && operable() && isturf(loc))

/obj/machinery/atmospherics/binary/dp_vent_pump/rust_push_running()
	if(vg_entity)
		push_running(dp_vent_pump_input_running())

/// The settings have no DM var, so each has one hand setter over the one write door. Rust clamps; the stored value is returned.
/obj/machinery/atmospherics/binary/dp_vent_pump/proc/set_external_pressure_bound(value)
	return native_write(src, NATIVE_DPVENTPUMP_EXTERNAL_PRESSURE_BOUND, value)

/obj/machinery/atmospherics/binary/dp_vent_pump/proc/set_input_pressure_min(value)
	return native_write(src, NATIVE_DPVENTPUMP_INPUT_PRESSURE_MIN, value)

/obj/machinery/atmospherics/binary/dp_vent_pump/proc/set_output_pressure_max(value)
	return native_write(src, NATIVE_DPVENTPUMP_OUTPUT_PRESSURE_MAX, value)

/obj/machinery/atmospherics/binary/dp_vent_pump/proc/set_pressure_checks(value)
	return native_write(src, NATIVE_DPVENTPUMP_PRESSURE_CHECKS, value)

/// A step's result: the flow and the power it drew, billed.
/obj/machinery/atmospherics/binary/dp_vent_pump/rust_device_stepped(moles, power_w, target_reached)
	atmos_note_flow_rate(src, abs(moles))
	set_last_power_draw(power_w)
	if(power_w > 0)
		use_power(power_w)


/// The edge is published again (once per frame) when a pipe comes or goes or the vent turns round.
/obj/machinery/atmospherics/binary/dp_vent_pump/derived()
	. = ..()
	. += rust_push(nameof(node1), nameof(node2), nameof(pump_direction))
	. += drawn_from(nameof(use_power), nameof(pump_direction), nameof(node1), nameof(node2))

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
		"checks" = get_pressure_checks(),
		"input" = get_input_pressure_min(),
		"output" = get_output_pressure_max(),
		"external" = get_external_pressure_bound(),
		"sigtype" = "status"
	)
	radio_connection.post_signal(src, signal, radio_filter = RADIO_ATMOSIA)
	spent(signal) // the receivers read what they need while it is delivered

	return 1

CAPABILITIES(/obj/machinery/atmospherics/binary/dp_vent_pump)
	pipe_device_port()
	on_change(nameof(use_power), ANY, then(TYPE_PROC_REF(/obj/machinery/atmospherics, pipe_port_resync)))
	ref_one(nameof(radio_connection), /datum/radio_frequency)
	setup(PROC_REF(prepare_vent_renderer))
	radio_listen(freq = nameof(frequency), via = PROC_REF(set_frequency)) // its radio follows its frequency from init
	configure(uses_power(idle = 150))
	examine_line(PROC_REF(gauge_text))

/// The gauge, to someone beside it.
/obj/machinery/atmospherics/binary/dp_vent_pump/proc/gauge_text(datum/act/eval/A)
	var/mob/viewer = A.actor
	if(viewer && Adjacent(viewer))
		return "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s; [round(last_power_draw)] W"

/obj/machinery/atmospherics/binary/dp_vent_pump/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0
	if(!isnull(signal.data["power"]))
		set_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"])
		set_use_power(!use_power)

	if(!isnull(signal.data["direction"]))
		set_pump_direction(text2num(signal.data["direction"]))

	if(!isnull(signal.data["checks"]))
		set_pressure_checks(text2num(signal.data["checks"]))

	if(signal.data["purge"])
		set_pressure_checks(get_pressure_checks() & ~PRESSURE_CHECK_EXTERNAL)
		set_pump_direction(0)

	if(signal.data["stabalize"])
		set_pressure_checks(get_pressure_checks() | PRESSURE_CHECK_EXTERNAL)
		set_pump_direction(1)

	if(!isnull(signal.data["set_input_pressure"]))
		set_input_pressure_min(between(0, text2num(signal.data["set_input_pressure"]), ONE_ATMOSPHERE*50))

	if(!isnull(signal.data["set_output_pressure"]))
		set_output_pressure_max(between(0, text2num(signal.data["set_output_pressure"]), ONE_ATMOSPHERE*50))

	if(!isnull(signal.data["set_external_pressure"]))
		set_external_pressure_bound(between(0, text2num(signal.data["set_external_pressure"]), ONE_ATMOSPHERE*50))

	if(signal.data["status"])
		after(src, 0.2 SECONDS, PROC_REF(broadcast_status))
		return //do not update_icon

	after(src, 0.2 SECONDS, PROC_REF(broadcast_status))

