// The vent pump: an area air device (code/domains/atmos/area_air_device.dm) the air alarm drives over the radio, whose flow law is a Rust device edge
// between its pipe and the turf it faces (device.rs Flow: a volume rate, the turf side bounded by the external check, the pipe side by the internal
// one). The flow's rate is its volume times fifty litres a second, as it has been since the flow law moved to Rust; power_rating is what it draws, not
// what limits it (a power-limited flow would change every station's ventilation rates).
//
// What it is: CAPABILITIES below. Its own code is the Rust push, its radio commands and status, the gauge and the look.

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

	level = 1
	/// Its radio tag (area_air_device()): a map gives it, else it is made unique.
	var/id_tag = null
	var/frequency = PUMPS_FREQ

	/// 1 releasing into the room, 0 siphoning out of it.
	var/pump_direction = 1

	var/external_pressure_bound = ONE_ATMOSPHERE
	var/internal_pressure_bound = 0

	/// VENT_CHECK_EXTERNAL: never past external_pressure_bound in the room. VENT_CHECK_INTERNAL: never past internal_pressure_bound in the pipe.
	var/pressure_checks = VENT_CHECK_EXTERNAL

	// What a "default" radio command restores.
	var/external_pressure_bound_default = ONE_ATMOSPHERE
	var/internal_pressure_bound_default = 0
	var/pressure_checks_default = VENT_CHECK_EXTERNAL

	/// The volume of its pipe-side air, L (a bigger vent moves more: its flow is fifty times this a second).
	var/vent_volume = ATMOS_DEFAULT_VOLUME_PUMP

TRACKED(/obj/machinery/atmospherics/unary/vent_pump, id_tag)
TRACKED(/obj/machinery/atmospherics/unary/vent_pump, frequency)
TRACKED(/obj/machinery/atmospherics/unary/vent_pump, pump_direction)
TRACKED(/obj/machinery/atmospherics/unary/vent_pump, external_pressure_bound)
TRACKED(/obj/machinery/atmospherics/unary/vent_pump, internal_pressure_bound)
TRACKED(/obj/machinery/atmospherics/unary/vent_pump, pressure_checks)

CAPABILITIES(/obj/machinery/atmospherics/unary/vent_pump)
	area_air_device(AREA_AIR_VENT, status = PROC_REF(status_fields), commands = list(
		"purge" = PROC_REF(cmd_purge),
		"stabalize" = PROC_REF(cmd_stabilize),
		"power" = PROC_REF(cmd_power),
		"power_toggle" = PROC_REF(cmd_power_toggle),
		"checks" = PROC_REF(cmd_checks),
		"checks_toggle" = PROC_REF(cmd_checks_toggle),
		"direction" = PROC_REF(cmd_direction),
		"set_internal_pressure" = PROC_REF(cmd_set_internal),
		"set_external_pressure" = PROC_REF(cmd_set_external),
		"adjust_internal_pressure" = PROC_REF(cmd_adjust_internal),
		"adjust_external_pressure" = PROC_REF(cmd_adjust_external),
		"reset_external_pressure" = PROC_REF(cmd_reset_external),
		"reset_internal_pressure" = PROC_REF(cmd_reset_internal)))
	weld_shut()
	multitool_settings(list(
		list("ID Tag", "id_tag", "text", 30),
		list("Frequency", "frequency", "frequency", null, "Note, [PUMPS_FREQ] will only hail Air Alarms for this device."),
		list("Direction", PROC_REF(flip_direction), "action"),
		list("-SAVE TO BUFFER-", PROC_REF(save_to_buffer), "action")))
	air_device_unwrench()
	examine_line(PROC_REF(gauge_text))
	on_change(WELD_SHUT_WELDED, ANY, then(PROC_REF(running_changed)))
	on_change(nameof(use_power), ANY, then(PROC_REF(running_changed)))

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
	pressure_checks = VENT_CHECK_INTERNAL
	pressure_checks_default = VENT_CHECK_INTERNAL

/obj/machinery/atmospherics/unary/vent_pump/high_volume
	name = "Large Air Vent"
	power_channel = EQUIP
	power_rating = 45000 // 15 kW ~ 20 HP // 45000
	vent_volume = ATMOS_DEFAULT_VOLUME_PUMP + 800

/obj/machinery/atmospherics/unary/vent_pump/high_volume/aux
	icon_state = "map_vent_aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX //connects to aux pipes

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
	vent_volume = ATMOS_DEFAULT_VOLUME_PUMP + 500 //meant to match air injector

/obj/machinery/atmospherics/unary/vent_pump/Initialize(mapload)
	. = ..()
	air_contents.set_volume(vent_volume)
	icon = null

/obj/machinery/atmospherics/unary/vent_pump/receive_signal(datum/signal/signal, receive_method, receive_param)
	area_air_receive(src, signal)

// ---- the Rust device edge ----

/// The vent's flow law (device.rs Flow), pushed once per frame after anything it reads changed. The turf is side A: releasing fills it up to the
/// external bound (the stop) and drains the pipe no lower than the internal bound (a cap); siphoning drains the room down to the external bound and
/// fills the pipe no higher than the internal bound. With only the internal check, it is the stop; with neither, the room fills without bound or
/// drains to nothing.
/obj/machinery/atmospherics/unary/vent_pump/push_to_rust()
	if(QDELETED(src))
		return
	if(!node || !can_pump()) // ALLOW(derived_reads): a port bind and a disconnect bump rust_device_rev
		rust_unregister_device()
		return
	var/datum/gas_mixture/environment = return_air()
	if(!environment)
		rust_unregister_device()
		return
	var/stop_side = RUST_SIDE_A
	var/stop_cmp = RUST_STOP_NONE
	var/stop_kpa = 0
	var/limit_cmp = RUST_STOP_NONE
	var/limit_kpa = 0
	if(pressure_checks & VENT_CHECK_EXTERNAL)
		stop_cmp = pump_direction ? RUST_STOP_AT_LEAST : RUST_STOP_AT_MOST
		stop_kpa = external_pressure_bound
	if(pressure_checks & VENT_CHECK_INTERNAL)
		limit_cmp = pump_direction ? RUST_STOP_AT_MOST : RUST_STOP_AT_LEAST
		limit_kpa = internal_pressure_bound
	if(stop_cmp == RUST_STOP_NONE)
		if(limit_cmp != RUST_STOP_NONE)
			stop_side = RUST_SIDE_B
			stop_cmp = limit_cmp
			stop_kpa = limit_kpa
			limit_cmp = RUST_STOP_NONE
		else
			stop_cmp = pump_direction ? RUST_STOP_AT_LEAST : RUST_STOP_AT_MOST
			stop_kpa = pump_direction ? 1e30 : 0
	rust_set_turf_device(1, environment)
	rust_set_device_flow(0, RUST_FLOW_VOLUME, vent_volume * 50, RUST_DIR_FORCED, stop_side, stop_cmp, stop_kpa, RUST_SIDE_B, limit_cmp, limit_kpa) // ALLOW(derived_reads): vent_volume is fixed by the type; use_power and operability bump rust_device_rev

/obj/machinery/atmospherics/unary/vent_pump/rust_device_stepped(moles, power_w, target_reached)
	last_flow_rate = abs(moles)

/// The Rust law is pushed (once per frame) when any of these change: rust_device_rev is bumped by a power change, a port bind and a disconnect.
/obj/machinery/atmospherics/unary/vent_pump/derived()
	. = ..()
	. += rust_push(nameof(rust_device_rev), nameof(pump_direction), nameof(external_pressure_bound), nameof(internal_pressure_bound), nameof(pressure_checks))
	. += drawn_from(nameof(use_power), nameof(pump_direction))

/// It moves gas: powered, on, not welded.
/obj/machinery/atmospherics/unary/vent_pump/proc/can_pump()
	return operable() && use_power && !weld_shut_welded(src, null)

// ---- the look ----

/obj/machinery/atmospherics/unary/vent_pump/draw(datum/look/look)
	..()
	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	var/vent_icon = "vent"
	// ALLOW(sys_dx_untracked_read): a pipe's level and a floor's plating are fixed while the vent stands on them; a change of either rebuilds the pipes
	if(!T.is_plating() && node && node.level == 1 && istype(node, /obj/machinery/atmospherics/pipe)) // ALLOW(derived_reads): atmos_init() and disconnect() redraw it when its pipe comes or goes
		vent_icon += "h"
	if(weld_shut_welded(src, null))
		vent_icon += "weld"
	else if(!use_power || !node || !operable())
		vent_icon += "off"
	else
		vent_icon += "[pump_direction ? "out" : "in"]"
	look.overlay(GLOB.icon_manager.get_atmos_icon("device", , , vent_icon))

/// The pump starts or stops (the power, the weld): it is heard.
/obj/machinery/atmospherics/unary/vent_pump/proc/running_changed(datum/act/A)
	rust_device_dirty()
	var/static/start_sound = SFX_MACHINES_AIR_PUMP_AIRPUMPSTART
	var/static/stop_sound = SFX_MACHINES_AIR_PUMP_AIRPUMPSHUTDOWN
	playsound(src, can_pump() ? start_sound : stop_sound, 25, ignore_walls = FALSE, preference = /datum/preference/toggle/air_pump_noise)

/obj/machinery/atmospherics/unary/vent_pump/update_underlays()
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

/obj/machinery/atmospherics/unary/vent_pump/hide()
	update_underlays()

/// The gauge, to someone beside it.
/obj/machinery/atmospherics/unary/vent_pump/proc/gauge_text(datum/act/eval/A)
	var/mob/viewer = A.actor
	if(viewer && Adjacent(viewer))
		return "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s; [round(last_power_draw)] W"
	return "You are too far away to read the gauge."

// ---- radio ----

/// What the vent reports beside the common status fields.
/obj/machinery/atmospherics/unary/vent_pump/proc/status_fields()
	return list(
		"direction" = pump_direction ? "release" : "siphon",
		"checks" = pressure_checks,
		"internal" = internal_pressure_bound,
		"external" = external_pressure_bound,
		"power_draw" = last_power_draw,
		"flow_rate" = last_flow_rate)


/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_purge(value)
	set_pressure_checks(pressure_checks & ~VENT_CHECK_EXTERNAL)
	set_pump_direction(0)

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_stabilize(value)
	set_pressure_checks(pressure_checks | VENT_CHECK_EXTERNAL)
	set_pump_direction(1)

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_power(value)
	set_use_power(text2num("[value]"))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_power_toggle(value)
	set_use_power(!use_power)

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_checks(value)
	set_pressure_checks(value == "default" ? pressure_checks_default : text2num("[value]"))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_checks_toggle(value)
	set_pressure_checks(pressure_checks ? 0 : (VENT_CHECK_EXTERNAL | VENT_CHECK_INTERNAL))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_direction(value)
	set_pump_direction(text2num("[value]"))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_set_internal(value)
	set_internal_pressure_bound(value == "default" ? internal_pressure_bound_default : clamp(text2num("[value]"), 0, ONE_ATMOSPHERE * 50))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_set_external(value)
	set_external_pressure_bound(value == "default" ? external_pressure_bound_default : clamp(text2num("[value]"), 0, ONE_ATMOSPHERE * 50))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_adjust_internal(value)
	set_internal_pressure_bound(clamp(internal_pressure_bound + text2num("[value]"), 0, ONE_ATMOSPHERE * 50))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_adjust_external(value)
	set_external_pressure_bound(clamp(external_pressure_bound + text2num("[value]"), 0, ONE_ATMOSPHERE * 50))

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_reset_external(value)
	set_external_pressure_bound(ONE_ATMOSPHERE)

/obj/machinery/atmospherics/unary/vent_pump/proc/cmd_reset_internal(value)
	set_internal_pressure_bound(0)

// ---- the multitool ----

/// The multitool's "Direction": it flips between releasing and siphoning.
/obj/machinery/atmospherics/unary/vent_pump/proc/flip_direction(datum/act/op/A)
	set_pump_direction(!pump_direction)
	to_chat(A.actor, span_notice("[src] is now [pump_direction ? "pumping in" : "siphoning out"]."))

/// The multitool's "-SAVE TO BUFFER-": the vent goes into the multitool's buffer (for linking).
/obj/machinery/atmospherics/unary/vent_pump/proc/save_to_buffer(datum/act/op/A)
	var/obj/item/multitool/tool = A.held
	if(istype(tool))
		rel_set(tool, nameof(tool.connectable), src)
