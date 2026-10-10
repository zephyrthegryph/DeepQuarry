// The air scrubber: an area air device (code/domains/atmos/area_air_device.dm) the air alarm drives over the radio, whose flow law is a Rust device
// edge from the turf it faces into its pipe: filtering (the gases it scrubs, at MAX_SCRUBBER_FLOWRATE) or siphoning everything (panic, at
// MAX_SIPHON_FLOWRATE).

/obj/machinery/atmospherics/unary/vent_scrubber
	icon = 'icons/atmos/vent_scrubber.dmi'
	icon_state = "map_scrubber_off"
	pipe_state = "scrubber"

	name = "Air Scrubber"
	desc = "Has a valve and pump attached to it"
	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 7500			//7500 W ~ 10 HP

	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_SCRUBBER //connects to regular and scrubber pipes

	level = 1
	/// Its radio tag (area_air_device()): a map gives it, else it is made unique.
	var/id_tag = null
	var/frequency = PUMPS_FREQ

	/// 1 filtering, 0 siphoning everything.
	var/scrubbing = 1
	/// Gas ids to scrub. Defaults to a list shared by every scrubber: never mutate it in place, assign a new list instead (copy on write).
	var/list/scrubbing_gas
	/// Siphoning the room in a panic.
	var/panic = 0

TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, id_tag)
TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, frequency)
TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, scrubbing)
TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, panic)
TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, scrubbing_gas)

CAPABILITIES(/obj/machinery/atmospherics/unary/vent_scrubber)
	area_air_device(AREA_AIR_SCRUBBER, status = PROC_REF(status_fields), commands = list(
		"power" = PROC_REF(cmd_power),
		"power_toggle" = PROC_REF(cmd_power_toggle),
		"panic_siphon" = PROC_REF(cmd_panic),
		"toggle_panic_siphon" = PROC_REF(cmd_panic_toggle),
		"scrubbing" = PROC_REF(cmd_scrubbing),
		"toggle_scrubbing" = PROC_REF(cmd_scrubbing_toggle),
		"o2_scrub" = PROC_REF(cmd_filter), "toggle_o2_scrub" = PROC_REF(cmd_filter_toggle),
		"n2_scrub" = PROC_REF(cmd_filter), "toggle_n2_scrub" = PROC_REF(cmd_filter_toggle),
		"co2_scrub" = PROC_REF(cmd_filter), "toggle_co2_scrub" = PROC_REF(cmd_filter_toggle),
		"tox_scrub" = PROC_REF(cmd_filter), "toggle_tox_scrub" = PROC_REF(cmd_filter_toggle),
		"n2o_scrub" = PROC_REF(cmd_filter), "toggle_n2o_scrub" = PROC_REF(cmd_filter_toggle),
		"fuel_scrub" = PROC_REF(cmd_filter), "toggle_fuel_scrub" = PROC_REF(cmd_filter_toggle),
		"ch4_scrub" = PROC_REF(cmd_filter), "toggle_ch4_scrub" = PROC_REF(cmd_filter_toggle)))
	weld_shut()
	air_device_unwrench()
	examine_line(PROC_REF(gauge_text))
	on_change(WELD_SHUT_WELDED, ANY, then(PROC_REF(weld_changed)))

/obj/machinery/atmospherics/unary/vent_scrubber/on
	use_power = USE_POWER_IDLE
	icon_state = "map_scrubber_on"

/obj/machinery/atmospherics/unary/vent_scrubber/Initialize(mapload)
	. = ..()
	var/static/list/default_scrubbing_gas = list(GAS_CO2, GAS_PHORON, GAS_CH4)
	if(isnull(scrubbing_gas))
		set_scrubbing_gas(default_scrubbing_gas)
	air_contents.set_volume(ATMOS_DEFAULT_VOLUME_FILTER)
	icon = null

/obj/machinery/atmospherics/unary/vent_scrubber/receive_signal(datum/signal/signal, receive_method, receive_param)
	area_air_receive(src, signal)

// ---- the Rust device edge ----

/// The scrubber's flow law: turf ("a") into its pipe ("b"), masked by `scrubbing_gas` unless siphoning.
/obj/machinery/atmospherics/unary/vent_scrubber/push_to_rust()
	if(QDELETED(src))
		return
	// ALLOW(derived_reads): set_use_power(), power_change(), a port bind, a disconnect and the weld bump rust_device_rev
	if(!node || !use_power || !operable() || weld_shut_welded(src, null))
		rust_unregister_device()
		return
	var/datum/gas_mixture/environment = return_air()
	if(!environment)
		rust_unregister_device()
		return
	var/mask = 0
	for(var/gas_id in scrubbing_gas)
		mask |= (1 << GAS_IDX(gas_id))
	var/rate = scrubbing ? MAX_SCRUBBER_FLOWRATE : MAX_SIPHON_FLOWRATE
	rust_set_turf_device(1, environment)
	rust_set_device_flow(scrubbing ? mask : 0, RUST_FLOW_VOLUME, rate, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

/obj/machinery/atmospherics/unary/vent_scrubber/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)

/// The Rust law is pushed (once per frame) when any of these change: rust_device_rev is bumped by a power change, a port bind, a disconnect and the weld.
/obj/machinery/atmospherics/unary/vent_scrubber/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(scrubbing), nameof(scrubbing_gas))
	. += drawn_from(nameof(use_power), nameof(scrubbing))

/// Welded shut or freed: the flow law follows.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/weld_changed(datum/act/A)
	rust_device_dirty()

// ---- the look ----

/obj/machinery/atmospherics/unary/vent_scrubber/draw(datum/look/look)
	..()
	if(!istype(get_turf(src), /turf))
		return
	var/scrubber_icon = "scrubber"
	if(weld_shut_welded(src, null))
		scrubber_icon += "weld"
	else if(!operable())
		scrubber_icon += "off"
	else
		scrubber_icon += "[use_power ? "[scrubbing ? "on" : "in"]" : "off"]"
	look.overlay(GLOB.icon_manager.get_atmos_icon("device", , , scrubber_icon))

/obj/machinery/atmospherics/unary/vent_scrubber/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	if(!T.is_plating() && node && node.level == 1 && istype(node, /obj/machinery/atmospherics/pipe))
		return
	if(node)
		add_underlay(T, node, dir, node.icon_connect_type)
	else
		add_underlay(T,, dir)

/obj/machinery/atmospherics/unary/vent_scrubber/hide(i) //to make the little pipe section invisible, the icon changes.
	update_underlays()

/// The gauge, to someone beside it.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/gauge_text(datum/act/eval/A)
	var/mob/viewer = A.actor
	if(viewer && Adjacent(viewer))
		return "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s; [round(last_power_draw)] W"
	return "You are too far away to read the gauge."

// ---- radio ----

/// The gas each filter command names.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/filter_gas(key)
	var/static/list/gases = list(
		"o2_scrub" = GAS_O2, "toggle_o2_scrub" = GAS_O2,
		"n2_scrub" = GAS_N2, "toggle_n2_scrub" = GAS_N2,
		"co2_scrub" = GAS_CO2, "toggle_co2_scrub" = GAS_CO2,
		"tox_scrub" = GAS_PHORON, "toggle_tox_scrub" = GAS_PHORON,
		"n2o_scrub" = GAS_N2O, "toggle_n2o_scrub" = GAS_N2O,
		"fuel_scrub" = GAS_VOLATILE_FUEL, "toggle_fuel_scrub" = GAS_VOLATILE_FUEL,
		"ch4_scrub" = GAS_CH4, "toggle_ch4_scrub" = GAS_CH4)
	return gases[key]

/// What the scrubber reports beside the common status fields.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/status_fields()
	return list(
		"scrubbing" = scrubbing,
		"panic" = panic,
		"filter_o2" = (GAS_O2 in scrubbing_gas),
		"filter_n2" = (GAS_N2 in scrubbing_gas),
		"filter_co2" = (GAS_CO2 in scrubbing_gas),
		"filter_phoron" = (GAS_PHORON in scrubbing_gas),
		"filter_n2o" = (GAS_N2O in scrubbing_gas),
		"filter_fuel" = (GAS_VOLATILE_FUEL in scrubbing_gas),
		"filter_ch4" = (GAS_CH4 in scrubbing_gas))


/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_power(value)
	set_use_power(text2num("[value]"))

/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_power_toggle(value)
	set_use_power(!use_power)

/// Panic siphons everything (and keeps the scrubber on); ending it goes back to filtering.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/apply_panic(on)
	set_panic(on)
	if(panic)
		set_use_power(USE_POWER_IDLE)
		set_scrubbing(0)
	else
		set_scrubbing(1)

/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_panic(value)
	apply_panic(text2num("[value]") ? 1 : 0)

/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_panic_toggle(value)
	apply_panic(!panic)

/// Filtering ends a panic.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/apply_scrubbing(on)
	set_scrubbing(on)
	if(scrubbing)
		set_panic(0)

/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_scrubbing(value)
	apply_scrubbing(text2num("[value]") ? 1 : 0)

/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_scrubbing_toggle(value)
	apply_scrubbing(!scrubbing)

/// A filter set on (1) or off (0).
/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_filter(value, key)
	var/gas = filter_gas(key)
	var/want = !!text2num("[value]")
	if(!gas || want == (gas in scrubbing_gas))
		return
	set_scrubbing_gas(scrubbing_gas ^ list(gas)) // a new list: the default is shared

/// A filter flipped.
/obj/machinery/atmospherics/unary/vent_scrubber/proc/cmd_filter_toggle(value, key)
	var/gas = filter_gas(key)
	if(gas)
		set_scrubbing_gas(scrubbing_gas ^ list(gas))
