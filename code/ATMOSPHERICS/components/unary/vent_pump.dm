#define DEFAULT_PRESSURE_DELTA 10000

#define EXTERNAL_PRESSURE_BOUND ONE_ATMOSPHERE
#define INTERNAL_PRESSURE_BOUND 0
#define PRESSURE_CHECKS 1

#define PRESSURE_CHECK_EXTERNAL 1
#define PRESSURE_CHECK_INTERNAL 2

/obj/machinery/atmospherics/unary/vent_pump
	icon = 'icons/atmos/vent_pump.dmi'
	icon_state = "map_vent"
	pipe_state = "uvent"

	name = "Air Vent"
	desc = "Has a valve and pump attached to it"
	use_power = USE_POWER_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 30000 // 7500 W ~ 10 HP // 30000 W

	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_SUPPLY //connects to regular and supply pipes
	blocks_emissive = EMISSIVE_BLOCK_NONE

	var/area/initial_loc
	level = 1
	var/area_uid
	var/id_tag = null

	var/pump_direction = 1 //0 = siphoning, 1 = releasing

	var/external_pressure_bound = EXTERNAL_PRESSURE_BOUND
	var/internal_pressure_bound = INTERNAL_PRESSURE_BOUND

	var/pressure_checks = PRESSURE_CHECKS
	//1: Do not pass external_pressure_bound
	//2: Do not pass internal_pressure_bound
	//3: Do not pass either

	// Used when handling incoming radio signals requesting default settings
	var/external_pressure_bound_default = EXTERNAL_PRESSURE_BOUND
	var/internal_pressure_bound_default = INTERNAL_PRESSURE_BOUND
	var/pressure_checks_default = PRESSURE_CHECKS

	var/frequency = PUMPS_FREQ
	var/datum/radio_frequency/radio_connection

	var/radio_filter_out
	var/radio_filter_in

	//var/datum/looping_sound/air_pump/soundloop
	var/static/start_sound = 'sound/machines/air_pump/airpumpstart.ogg'
	var/static/stop_sound = 'sound/machines/air_pump/airpumpshutdown.ogg'


/obj/machinery/atmospherics/unary/vent_pump/on
	use_power = USE_POWER_IDLE
	icon_state = "map_vent_out"

/obj/machinery/atmospherics/unary/vent_pump/aux
	icon_state = "map_vent_aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX //connects to aux pipes

/obj/machinery/atmospherics/unary/vent_pump/siphon
	pump_direction = 0

/obj/machinery/atmospherics/unary/vent_pump/siphon/on
	use_power = USE_POWER_IDLE
	icon_state = "map_vent_in"

/obj/machinery/atmospherics/unary/vent_pump/siphon/on/atmos
	use_power = USE_POWER_IDLE
	icon_state = "map_vent_in"
	external_pressure_bound = 0
	external_pressure_bound_default = 0
	internal_pressure_bound = 2000
	internal_pressure_bound_default = 2000
	pressure_checks = 2
	pressure_checks_default = 2

/obj/machinery/atmospherics/unary/vent_pump/Initialize(mapload)
	. = ..()

	air_contents.set_volume(ATMOS_DEFAULT_VOLUME_PUMP)

	icon = null
	initial_loc = get_area(loc)
	area_uid = "\ref[initial_loc]"
	if (!id_tag)
		assign_uid()
		id_tag = num2text(uid)
	// M2: the flow law is a Rust device edge (pipe port <-> turf), stepped
	// from SSair every gas tick; this has no process() at all any more.
	STOP_MACHINE_PROCESSING(src)

// M2 (simulation.md §5): the flow law lives on the Rust device edge
// (device::DeviceParams::VentPump). rust_bind_pipe_port fires once the
// port's region exists in Rust, the earliest point it can bind to a turf.
/obj/machinery/atmospherics/unary/vent_pump/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	update_rust_device()

/// Publishes (or unpublishes) the vent's Rust device edge. `device.rs`'s
/// VentPump only bounds the turf ("a") side within `[min_kpa, max_kpa]`;
/// `pressure_checks`' PRESSURE_CHECK_EXTERNAL bit maps onto that bound
/// directly (the common case - every default configuration uses it).
/// PRESSURE_CHECK_INTERNAL (bounding the network side, used only by the
/// `/siphon/on/atmos` variant) has no equivalent yet, so that one variant
/// runs unbounded on the turf side until the network-side bound is added.
/obj/machinery/atmospherics/unary/vent_pump/proc/update_rust_device()
	// disconnect() (called mid-Destroy(), after the port/region is already
	// torn down) reaches here via invalidate_gas_dependencies(); air_contents
	// may already be a dead handle at that point.
	if(QDELETED(src))
		return
	if(!node || !can_pump())
		rust_unregister_device()
		return
	var/datum/gas_mixture/environment = return_air()
	if(!environment)
		rust_unregister_device()
		return
	var/mode = pump_direction ? RUST_VENT_MODE_RELEASE : RUST_VENT_MODE_SIPHON
	var/min_kpa = 0
	var/max_kpa = 1e30
	if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
		if(pump_direction)
			max_kpa = external_pressure_bound
		else
			min_kpa = external_pressure_bound
	var/max_rate = air_contents.return_volume() * 50
	rust_set_turf_device(1, environment, RUST_DEVICE_LAW_VENT_PUMP, mode, min_kpa, max_kpa, max_rate)

/obj/machinery/atmospherics/unary/vent_pump/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)

// The unary base's invalidate_gas_dependencies() wakes a DM gas-dependency
// subscriber; vent_pump has none any more (M2), so this republishes the
// Rust device edge instead. Covers every existing call site (welder_act,
// multitool_act, click_ctrl, power_change) without touching each one.
/obj/machinery/atmospherics/unary/vent_pump/invalidate_gas_dependencies()
	update_rust_device()

// The unary base's disconnect() calls invalidate_gas_dependencies() before
// nulling `node`, so that call sees stale state; re-publish afterwards.
/obj/machinery/atmospherics/unary/vent_pump/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	update_rust_device()

/obj/machinery/atmospherics/unary/vent_pump/proc/update_area()
	initial_loc = get_area(loc)
	area_uid = "\ref[initial_loc]"
	assign_uid()
	id_tag = num2text(uid)


/obj/machinery/atmospherics/unary/vent_pump/Destroy()
	// rust_unregister_device() runs as part of the base class's
	// rust_unregister_pipe_topology() (atmospherics.dm's Destroy()), below.
	unregister_radio(src, frequency)
	if(initial_loc)
		LAZYREMOVE(initial_loc.air_vent_info, id_tag)
		LAZYREMOVE(initial_loc.air_vent_names, id_tag)
	//QDEL_NULL(soundloop)
	return ..()

/obj/machinery/atmospherics/unary/vent_pump/high_volume
	name = "Large Air Vent"
	power_channel = EQUIP
	power_rating = 45000 // 15 kW ~ 20 HP // 45000

/obj/machinery/atmospherics/unary/vent_pump/high_volume/aux
	icon_state = "map_vent_aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX //connects to aux pipes

/obj/machinery/atmospherics/unary/vent_pump/high_volume/Initialize(mapload)
	. = ..()
	air_contents.set_volume(ATMOS_DEFAULT_VOLUME_PUMP + 800)

// Wall mounted vents
/obj/machinery/atmospherics/unary/vent_pump/high_volume/wall_mounted
	name = "Wall Mounted Air Vent"

/obj/machinery/atmospherics/unary/vent_pump/high_volume/wall_mounted/can_unwrench()
	return FALSE // No way to construct these, so don't let them be removed.

// Return the air from the turf in "front" of us (opposite the way the pipe is facing)
/obj/machinery/atmospherics/unary/vent_pump/high_volume/wall_mounted/return_air()
	var/turf/T = get_step(src, GLOB.reverse_dir[dir])
	if(isnull(T))
		return ..()
	return T.return_air()


/obj/machinery/atmospherics/unary/vent_pump/engine
	name = "Engine Core Vent"
	power_channel = ENVIRON
	power_rating = 30000	//15 kW ~ 20 HP

/obj/machinery/atmospherics/unary/vent_pump/engine/Initialize(mapload)
	. = ..()
	air_contents.set_volume(ATMOS_DEFAULT_VOLUME_PUMP + 500) //meant to match air injector

/obj/machinery/atmospherics/unary/vent_pump/update_icon(safety = 0)
	cut_overlays()

	var/vent_icon = "vent"

	var/turf/T = get_turf(src)
	if(!istype(T))
		return

	if(!T.is_plating() && node && node.level == 1 && istype(node, /obj/machinery/atmospherics/pipe))
		vent_icon += "h"

	if(welded)
		vent_icon += "weld"
		playsound(src, stop_sound, 25, ignore_walls = FALSE, preference = /datum/preference/toggle/air_pump_noise)

	else if(!use_power || !node || (stat & (NOPOWER|BROKEN)))
		vent_icon += "off"
		playsound(src, stop_sound, 25, ignore_walls = FALSE, preference = /datum/preference/toggle/air_pump_noise)
	else
		vent_icon += "[pump_direction ? "out" : "in"]"
		playsound(src, start_sound, 25, ignore_walls = FALSE, preference = /datum/preference/toggle/air_pump_noise)


	add_overlay(GLOB.icon_manager.get_atmos_icon("device", , , vent_icon))

/obj/machinery/atmospherics/unary/vent_pump/update_underlays()
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

/obj/machinery/atmospherics/unary/vent_pump/hide()
	update_icon()
	update_underlays()

/obj/machinery/atmospherics/unary/vent_pump/proc/can_pump()
	if(stat & (NOPOWER|BROKEN))
		return 0
	if(!use_power)
		return 0
	if(welded)
		return 0
	return 1

// process(), gas_dependency_changed() and pump_transaction_committed() are
// deleted (M2, simulation.md §5): the flow law above is a Rust device edge,
// stepped every gas tick from SSair.fire() regardless of DM's process()
// scheduling, so there is nothing left to run and nothing to hibernate.

/obj/machinery/atmospherics/unary/vent_pump/proc/get_pressure_delta(datum/gas_mixture/environment)
	return get_pressure_delta_values(environment.return_pressure(), air_contents.return_pressure())

/obj/machinery/atmospherics/unary/vent_pump/proc/get_pressure_delta_values(environment_pressure, internal_pressure)
	var/pressure_delta = DEFAULT_PRESSURE_DELTA

	if(pump_direction) //internal -> external
		if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
			pressure_delta = min(pressure_delta, external_pressure_bound - environment_pressure) //increasing the pressure here
		if(pressure_checks & PRESSURE_CHECK_INTERNAL)
			pressure_delta = min(pressure_delta, internal_pressure - internal_pressure_bound) //decreasing the pressure here
	else //external -> internal
		if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
			pressure_delta = min(pressure_delta, environment_pressure - external_pressure_bound) //decreasing the pressure here
		if(pressure_checks & PRESSURE_CHECK_INTERNAL)
			pressure_delta = min(pressure_delta, internal_pressure_bound - internal_pressure) //increasing the pressure here

	return pressure_delta

/obj/machinery/atmospherics/unary/vent_pump/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.source = src

	signal.data = list(
		"area" = src.area_uid,
		"tag" = src.id_tag,
		"device" = "AVP",
		"power" = use_power,
		"direction" = pump_direction?("release"):("siphon"),
		"checks" = pressure_checks,
		"internal" = internal_pressure_bound,
		"external" = external_pressure_bound,
		"timestamp" = world.time,
		"sigtype" = "status",
		"power_draw" = last_power_draw,
		"flow_rate" = last_flow_rate,
	)

	if(!LAZYACCESS(initial_loc.air_vent_names, id_tag))
		var/new_name = "[initial_loc.name] Vent Pump #[length(initial_loc.air_vent_names)+1]"
		LAZYSET(initial_loc.air_vent_names, id_tag, new_name)
		src.name = new_name
	LAZYSET(initial_loc.air_vent_info, id_tag, signal.data)

	radio_connection.post_signal(src, signal, radio_filter_out)

	return 1


/obj/machinery/atmospherics/unary/vent_pump/atmos_init()
	..()

	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/unary/vent_pump/click_ctrl(mob/user)
	. = ..()
	invalidate_gas_dependencies()

/obj/machinery/atmospherics/unary/vent_pump/proc/set_frequency(new_frequency)
	//some vents work his own special way
	radio_filter_in = new_frequency==1439 ? AIRALARM_AREA_FILTER(RADIO_FROM_AIRALARM, area_uid) : null
	radio_filter_out = new_frequency==1439 ? AIRALARM_AREA_FILTER(RADIO_TO_AIRALARM, area_uid) : null
	radio_connection = register_radio(src, frequency, new_frequency, radio_filter_in)
	frequency = new_frequency
	broadcast_status()

/obj/machinery/atmospherics/unary/vent_pump/receive_signal(datum/signal/signal)
	if(stat & (NOPOWER|BROKEN))
		return

	//log_admin("DEBUG \[[world.timeofday]\]: /obj/machinery/atmospherics/unary/vent_pump/receive_signal([signal.debug_print()])")
	if(!signal.data["tag"] || (signal.data["tag"] != id_tag) || (signal.data["sigtype"]!="command"))
		return 0

	if(signal.data["purge"] != null)
		pressure_checks &= ~1
		pump_direction = 0

	if(signal.data["stabalize"] != null)
		pressure_checks |= 1
		pump_direction = 1

	if(signal.data["power"] != null)
		update_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"] != null)
		update_use_power(!use_power)

	if(signal.data["checks"] != null)
		if (signal.data["checks"] == "default")
			pressure_checks = pressure_checks_default
		else
			pressure_checks = text2num(signal.data["checks"])

	if(signal.data["checks_toggle"] != null)
		pressure_checks = (pressure_checks?0:3)

	if(signal.data["direction"] != null)
		pump_direction = text2num(signal.data["direction"])

	if(signal.data["set_internal_pressure"] != null)
		if (signal.data["set_internal_pressure"] == "default")
			internal_pressure_bound = internal_pressure_bound_default
		else
			internal_pressure_bound = between(0,text2num(signal.data["set_internal_pressure"]),ONE_ATMOSPHERE*50)

	if(signal.data["set_external_pressure"] != null)
		if (signal.data["set_external_pressure"] == "default")
			external_pressure_bound = external_pressure_bound_default
		else
			external_pressure_bound = between(0,text2num(signal.data["set_external_pressure"]),ONE_ATMOSPHERE*50)

	if(signal.data["adjust_internal_pressure"] != null)
		internal_pressure_bound = between(0,internal_pressure_bound + text2num(signal.data["adjust_internal_pressure"]),ONE_ATMOSPHERE*50)

	if(signal.data["adjust_external_pressure"] != null)
		external_pressure_bound = between(0,external_pressure_bound + text2num(signal.data["adjust_external_pressure"]),ONE_ATMOSPHERE*50)

	if("reset_external_pressure" in signal.data)
		external_pressure_bound = ONE_ATMOSPHERE

	if("reset_internal_pressure" in signal.data)
		internal_pressure_bound = 0

	if(signal.data["init"] != null)
		name = signal.data["init"]
		return

	update_rust_device()

	if(signal.data["status"] != null)
		addtimer(CALLBACK(src, PROC_REF(broadcast_status)), 2, TIMER_DELETE_ME)
		return //do not update_icon

		//log_admin("DEBUG \[[world.timeofday]\]: vent_pump/receive_signal: unknown command \"[signal.data["command"]]\"\n[signal.debug_print()]")
	addtimer(CALLBACK(src, PROC_REF(broadcast_status)), 2, TIMER_DELETE_ME)
	update_icon()
	return

/obj/machinery/atmospherics/unary/vent_pump/welder_act(mob/user, obj/item/W)
	if(use_tool(user, W, src, delay = 20, quality = TOOL_WELDER, volume = 0, message_self = "Now welding the vent."))
		if(!src)
			return ITEM_INTERACT_BLOCKING
		playsound(src, W.usesound, 50, 1)
		if(!welded)
			user.visible_message(span_bold("\The [user]") + " welds the vent shut.", span_notice("You weld the vent shut."), "You hear welding.")
			welded = 1
			invalidate_gas_dependencies()
			update_icon()
		else
			user.visible_message(span_notice("[user] unwelds the vent."), span_notice("You unweld the vent."), "You hear welding.")
			welded = 0
			invalidate_gas_dependencies()
			update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/vent_pump/wrench_act(mob/user, obj/item/W)
	if (!(stat & NOPOWER) && use_power)
		to_chat(user, span_warning("You cannot unwrench \the [src], turn it off first."))
		return ITEM_INTERACT_BLOCKING
	var/turf/T = src.loc
	if (node && node.level==1 && isturf(T) && !T.is_plating())
		to_chat(user, span_warning("You must remove the plating first."))
		return ITEM_INTERACT_BLOCKING
	if(!can_unwrench())
		to_chat(user, span_warning("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return ITEM_INTERACT_BLOCKING
	if (use_tool(user, W, src, delay = 40, volume = 50, message_self = "You begin to unfasten \the [src]..."))
		user.visible_message( \
			span_infoplain(span_bold("\The [user]") + " unfastens \the [src]."), \
			span_notice("You have unfastened \the [src]."), \
			"You hear a ratchet.")
		atom_deconstruct()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/atmospherics/unary/vent_pump/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s; [round(last_power_draw)] W"
	else
		. += "You are too far away to read the gauge."
	if(welded)
		. += "It seems welded shut."

/obj/machinery/atmospherics/unary/vent_pump/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		invalidate_gas_dependencies()
		update_icon()

/obj/machinery/atmospherics/unary/vent_pump/multitool_act(mob/user, obj/item/W)
	var/list/options = list(
		"ID Tag", "Frequency", "Direction", "-SAVE TO BUFFER-")
	var/choice = tgui_input_list(user, "[src] has an ID of \"[id_tag]\" and a frequency of [frequency]. What would you like to change?", "[src] Config", options)
	switch(choice)
		if("ID Tag")
			var/new_id = tgui_input_text(user, "[src] has an ID of \"[id_tag]\". What would you like it to be?", "[src] ID", id_tag, 30)
			if(new_id)
				id_tag = new_id

		if("Frequency")
			var/new_frequency = tgui_input_number(user, "[src] has a frequency of [frequency]. What would you like it to be? Note, 1439 will only hail Air Alarms for this device.", "[src] frequency", frequency, RADIO_HIGH_FREQ, RADIO_LOW_FREQ)
			if(new_frequency)
				new_frequency = sanitize_frequency(new_frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
				set_frequency(new_frequency)

		if("-SAVE TO BUFFER-")
			var/obj/item/multitool/tool = W
			tool.connectable = src

		if("Direction")
			pump_direction = !pump_direction
			invalidate_gas_dependencies()
			to_chat(user, span_notice("[src] is now [pump_direction ? "pumping in" : "siphoning out"]."))
			update_icon()
	return ITEM_INTERACT_SUCCESS

#undef DEFAULT_PRESSURE_DELTA

#undef EXTERNAL_PRESSURE_BOUND
#undef INTERNAL_PRESSURE_BOUND
#undef PRESSURE_CHECKS

#undef PRESSURE_CHECK_EXTERNAL
#undef PRESSURE_CHECK_INTERNAL
