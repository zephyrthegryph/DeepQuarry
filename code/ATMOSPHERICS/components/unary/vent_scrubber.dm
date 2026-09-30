/obj/machinery/atmospherics/unary/vent_scrubber
	gas_dependency_mask = GAS_DEPENDENCY_ALL
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

	var/area/initial_loc
	var/id_tag = null
	var/frequency = PUMPS_FREQ
	var/datum/radio_frequency/radio_connection

	var/scrubbing = 1 //0 = siphoning, 1 = scrubbing
	/// Gas ids to scrub. Defaults to a list shared by every scrubber: never
	/// mutate it in place, assign a new list instead (copy on write).
	var/list/scrubbing_gas

	var/panic = 0 //is this scrubber panicked?

	var/area_uid
	var/radio_filter_out
	var/radio_filter_in

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
	initial_loc = get_area(loc)
	area_uid = "\ref[initial_loc]"
	if (!id_tag)
		assign_uid()
		id_tag = num2text(uid)

/obj/machinery/atmospherics/unary/vent_scrubber/proc/update_area()
	initial_loc = get_area(loc)
	area_uid = "\ref[initial_loc]"
	assign_uid()
	id_tag = num2text(uid)

/// Phase 2: leaves its area's scrubber index.
/obj/machinery/atmospherics/unary/vent_scrubber/lifecycle_dematerialize()
	. = ..()
	if(initial_loc)
		LAZYREMOVE(initial_loc.air_scrub_info, id_tag)
		LAZYREMOVE(initial_loc.air_scrub_names, id_tag)

// M2 (simulation.md §5): the flow law lives on the Rust device edge
// (device::DeviceParams::Scrubber). rust_bind_pipe_port fires once the
// port's region exists in Rust, the earliest point it can bind to a turf.
/obj/machinery/atmospherics/unary/vent_scrubber/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	rust_device_dirty()

/// Publishes (or unpublishes) the scrubber's Rust device edge: turf ("a")
/// into air_contents ("b"), masked by `scrubbing_gas` unless siphoning.
/obj/machinery/atmospherics/unary/vent_scrubber/push_to_rust()
	// disconnect() (called mid-Destroy(), after the port/region is already
	// torn down) reaches here via invalidate_gas_dependencies(); air_contents
	// may already be a dead handle at that point.
	if(QDELETED(src))
		return
	// ALLOW(derived_reads): set_use_power() and power_change() bump rust_device_rev
	if(!node || !use_power || (!operable()) || welded)
		rust_unregister_device()
		return
	var/datum/gas_mixture/environment = return_air()
	if(!environment)
		rust_unregister_device()
		return
	// scrubbing_gas holds GAS_* short-id strings ("plasma", "co2", ...), not
	// numbers - GAS_IDX() resolves to the numeric Rust gas index the mask
	// bit corresponds to.
	var/mask = 0
	for(var/gas_id in scrubbing_gas)
		mask |= (1 << GAS_IDX(gas_id))
	var/rate = scrubbing ? MAX_SCRUBBER_FLOWRATE : MAX_SIPHON_FLOWRATE
	rust_set_turf_device(1, environment)
	rust_set_device_flow(scrubbing ? mask : 0, RUST_FLOW_VOLUME, rate, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0)

/obj/machinery/atmospherics/unary/vent_scrubber/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)

// The unary base's invalidate_gas_dependencies() wakes a DM gas-dependency
// subscriber; vent_scrubber has none any more (M2), so this republishes the
// Rust device edge instead. Covers every existing call site (welder_act,
// power_change, receive_signal).
/obj/machinery/atmospherics/unary/vent_scrubber/invalidate_gas_dependencies()
	rust_device_dirty()

// The unary base's disconnect() calls invalidate_gas_dependencies() before
// nulling `node`, so that call sees stale state; re-publish afterwards.
/obj/machinery/atmospherics/unary/vent_scrubber/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	rust_device_dirty()

DECLARE_APPEARANCE_PROC(/obj/machinery/atmospherics/unary/vent_scrubber, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/atmospherics/unary/vent_scrubber/appearance_overlays()
	. = list()

	var/scrubber_icon = "scrubber"

	var/turf/T = get_turf(src)
	if(!istype(T))
		return .

	if(welded)
		scrubber_icon += "weld"
	else if(!powered())
		scrubber_icon += "off"
	else
		scrubber_icon += "[use_power ? "[scrubbing ? "on" : "in"]" : "off"]"

	. += GLOB.icon_manager.get_atmos_icon("device", , , scrubber_icon)

/obj/machinery/atmospherics/unary/vent_scrubber/update_underlays()
	..()
	underlays.Cut()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	if(!T.is_plating() && node && node.level == 1 && istype(node, /obj/machinery/atmospherics/pipe))
		return
	else
		if(node)
			add_underlay(T, node, dir, node.icon_connect_type)
		else
			add_underlay(T,, dir)

/obj/machinery/atmospherics/unary/vent_scrubber/proc/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), GLOB.radio_service.add_object(src, frequency, radio_filter_in))

/obj/machinery/atmospherics/unary/vent_scrubber/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	rel_set(signal, nameof(signal.source), src)
	signal.data = list(
		"area" = area_uid,
		"tag" = id_tag,
		"device" = "AScr",
		"timestamp" = EXPIRY_AT(src, CLOCK_WORLD, 0),
		"power" = use_power,
		"scrubbing" = scrubbing,
		"panic" = panic,
		"filter_o2" = (GAS_O2 in scrubbing_gas),
		"filter_n2" = (GAS_N2 in scrubbing_gas),
		"filter_co2" = (GAS_CO2 in scrubbing_gas),
		"filter_phoron" = (GAS_PHORON in scrubbing_gas),
		"filter_n2o" = (GAS_N2O in scrubbing_gas),
		"filter_fuel" = (GAS_VOLATILE_FUEL in scrubbing_gas),
		"filter_ch4" = (GAS_CH4 in scrubbing_gas),
		"sigtype" = "status"
	)
	if(!LAZYACCESS(initial_loc.air_scrub_names, id_tag))
		var/new_name = "[initial_loc.name] Air Scrubber #[length(initial_loc.air_scrub_names)+1]"
		LAZYSET(initial_loc.air_scrub_names, id_tag, new_name)
		src.name = new_name
	LAZYSET(initial_loc.air_scrub_info, id_tag, signal.data)
	radio_connection.post_signal(src, signal, radio_filter_out)

	return 1

/obj/machinery/atmospherics/unary/vent_scrubber/atmos_init()
	..()
	radio_filter_in = frequency == initial(frequency) ? AIRALARM_AREA_FILTER(RADIO_FROM_AIRALARM, area_uid) : null
	radio_filter_out = frequency == initial(frequency) ? AIRALARM_AREA_FILTER(RADIO_TO_AIRALARM, area_uid) : null
	if (frequency)
		set_frequency(frequency)
		src.broadcast_status()

// process() and gas_dependency_changed() are deleted (M2, simulation.md
// §5): the flow law above is a Rust device edge, stepped every gas tick
// from SSair.fire() regardless of DM's process() scheduling, so there is
// nothing left to run and nothing to hibernate.

/obj/machinery/atmospherics/unary/vent_scrubber/hide(i) //to make the little pipe section invisible, the icon changes.
	update_icon()
	update_underlays()

/obj/machinery/atmospherics/unary/vent_scrubber/receive_signal(datum/signal/signal)
	if(!operable())
		return
	if(!signal.data["tag"] || (signal.data["tag"] != id_tag) || (signal.data["sigtype"]!="command"))
		return 0

	if(signal.data["power"] != null)
		set_use_power(text2num(signal.data["power"]))
	if(signal.data["power_toggle"] != null)
		set_use_power(!use_power)

	if(signal.data["panic_siphon"]) //must be before if("scrubbing" thing
		set_panic(text2num(signal.data["panic_siphon"]))
		if(panic)
			set_use_power(USE_POWER_IDLE)
			set_scrubbing(0)
		else
			set_scrubbing(1)
	if(signal.data["toggle_panic_siphon"] != null)
		set_panic(!panic)
		if(panic)
			set_use_power(USE_POWER_IDLE)
			set_scrubbing(0)
		else
			set_scrubbing(1)

	if(signal.data["scrubbing"] != null)
		set_scrubbing(text2num(signal.data["scrubbing"]))
		if(scrubbing)
			set_panic(0)
	if(signal.data["toggle_scrubbing"])
		set_scrubbing(!scrubbing)
		if(scrubbing)
			set_panic(0)

	var/list/toggle = list()

	if(!isnull(signal.data["o2_scrub"]) && text2num(signal.data["o2_scrub"]) != (GAS_O2 in scrubbing_gas))
		toggle += GAS_O2
	else if(signal.data["toggle_o2_scrub"])
		toggle += GAS_O2

	if(!isnull(signal.data["n2_scrub"]) && text2num(signal.data["n2_scrub"]) != (GAS_N2 in scrubbing_gas))
		toggle += GAS_N2
	else if(signal.data["toggle_n2_scrub"])
		toggle += GAS_N2

	if(!isnull(signal.data["co2_scrub"]) && text2num(signal.data["co2_scrub"]) != (GAS_CO2 in scrubbing_gas))
		toggle += GAS_CO2
	else if(signal.data["toggle_co2_scrub"])
		toggle += GAS_CO2

	if(!isnull(signal.data["tox_scrub"]) && text2num(signal.data["tox_scrub"]) != (GAS_PHORON in scrubbing_gas))
		toggle += GAS_PHORON
	else if(signal.data["toggle_tox_scrub"])
		toggle += GAS_PHORON

	if(!isnull(signal.data["n2o_scrub"]) && text2num(signal.data["n2o_scrub"]) != (GAS_N2O in scrubbing_gas))
		toggle += GAS_N2O
	else if(signal.data["toggle_n2o_scrub"])
		toggle += GAS_N2O

	if(!isnull(signal.data["fuel_scrub"]) && text2num(signal.data["fuel_scrub"]) != (GAS_VOLATILE_FUEL in scrubbing_gas))
		toggle += GAS_VOLATILE_FUEL
	else if(signal.data["toggle_fuel_scrub"])
		toggle += GAS_VOLATILE_FUEL

	if(!isnull(signal.data["ch4_scrub"]) && text2num(signal.data["ch4_scrub"]) != (GAS_CH4 in scrubbing_gas))
		toggle += GAS_CH4
	else if(signal.data["toggle_ch4_scrub"])
		toggle += GAS_CH4

	if(length(toggle))
		set_scrubbing_gas(scrubbing_gas ^ toggle) // new list: the default is shared

	if(signal.data["init"] != null)
		name = signal.data["init"]
		return

	if(signal.data["status"] != null)
		om_after(src, 2, PROC_REF(broadcast_status))
		return //do not update_icon

	om_after(src, 2, PROC_REF(broadcast_status))
	update_icon()
	return

/obj/machinery/atmospherics/unary/vent_scrubber/power_change()
	. = ..()
	if(.)
		invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/vent_scrubber/welder_act(mob/user, obj/item/W)
	use_tool(user, W, src, delay = 20, quality = TOOL_WELDER, volume = 0, start_self = "Now welding the vent.", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user, W))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/vent_scrubber/proc/welder_act_tool_done(mob/user, obj/item/W)
	if(!src)
		return ITEM_INTERACT_BLOCKING
	playsound(src, W.usesound, 50, 1)
	if(!welded)
		act_message(user, null, MSG_SELF(span_notice("You weld the vent shut.")), \
			MSG_OTHERS(span_notice("<b>%U%</b> welds the vent shut.")), \
			MSG_BLIND("You hear welding."))
		set_welded(TRUE)
		invalidate_gas_dependencies()
		update_icon()
	else
		act_message(user, null, MSG_SELF(span_notice("You unweld the vent.")), MSG_OTHERS(span_notice("%U% unwelds the vent.")), MSG_BLIND("You hear welding."))
		set_welded(FALSE)
		invalidate_gas_dependencies()
		update_icon()

/obj/machinery/atmospherics/unary/vent_scrubber/wrench_act(mob/user, obj/item/W)
	if (!has_stat(NOPOWER) && use_power)
		to_chat(user, span_warning("You cannot unwrench \the [src], turn it off first."))
		return ITEM_INTERACT_BLOCKING
	var/turf/T = src.loc
	if (node && node.level==1 && isturf(T) && !T.is_plating())
		to_chat(user, span_warning("You must remove the plating first."))
		return ITEM_INTERACT_BLOCKING
	if(welded)
		to_chat(user, span_warning("You cannot unwrench \the [src], it is welded down firmly."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, W, src, delay = 40, volume = 50, start_self = "You begin to unfasten \the [src]...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/vent_scrubber/proc/wrench_act_tool_done(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You have unfastened %T%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " unfastens %T%.")), \
		MSG_BLIND("You hear a ratchet."))
	atom_deconstruct()

/obj/machinery/atmospherics/unary/vent_scrubber/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s; [round(last_power_draw)] W"
	else
		. += "You are too far away to read the gauge."
	if(welded)
		. += "It is welded shut."


TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, scrubbing, CHANGE_MACHINE_SETTINGS)
TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, panic, CHANGE_MACHINE_SETTINGS)
TRACKED(/obj/machinery/atmospherics/unary/vent_scrubber, scrubbing_gas, CHANGE_MACHINE_SETTINGS)

/// The Rust device law is pushed (once per frame) when any of these change.
/obj/machinery/atmospherics/unary/vent_scrubber/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(scrubbing), nameof(scrubbing_gas), nameof(welded))
