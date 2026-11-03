// The airlock cycle (doc/rewrite/proposals/docking_port.md section 3): a state on the airlock console itself, which holds its doors, pumps,
// sensors and mech sensors by relation (keyed views of the map's tags, linked when the map loads and re-linked on a retag). It reads
// them directly (a door's density and bolts, a vent's power) and commands them directly (a door's airlock_command(), a vent's setters):
// nothing is remembered from a radio report, so nothing can go stale.
//
// The chamber's pressure is the median of the chamber region: the turfs that share air with the chamber sensor's (the pump's when there is
// no sensor), at most AIRLOCK_REGION_MAX. While the chamber pumps, the airlock holds a gas watch on each of the region's mixtures; a
// reported change wakes its step. A pumping chamber with no change sleeps.
//
// States: idle, prepare (shut and bolt the doors, pick the pump direction), depressurize, pressurize. Targets: none, inner door open,
// outer door open. A cycle is done when the state is idle and the target none.

#define AIRLOCK_STATE_IDLE			0
#define AIRLOCK_STATE_PREPARE		1
#define AIRLOCK_STATE_DEPRESSURIZE	2
#define AIRLOCK_STATE_PRESSURIZE	3

#define AIRLOCK_TARGET_NONE		0
#define AIRLOCK_TARGET_INOPEN	-1
#define AIRLOCK_TARGET_OUTOPEN	-2

#define MIN_TARGET_PRESSURE (ONE_ATMOSPHERE * 0.05) // Never try to pump to pure vacuum, its not happening.
#define SKIPCYCLE_MARGIN	1 // Skip cycling airlock (just open the doors) if pressures are within this range.
/// The most turfs a chamber region holds: a chamber whose doors are open reaches into the rooms beyond, and stops here.
#define AIRLOCK_REGION_MAX	40

/obj/machinery/embedded_controller/radio/airlock
	/// Where the cycle is (AIRLOCK_STATE_*) and where it is going (AIRLOCK_TARGET_*).
	var/cycle_state = AIRLOCK_STATE_IDLE
	var/target_state = AIRLOCK_TARGET_NONE
	/// The chamber pressure the cycle pumps to (kPa).
	var/target_pressure = ONE_ATMOSPHERE
	/// Purge: empty the chamber to vacuum before filling it (an external-air airlock always purges).
	var/purge = FALSE
	/// Doors are bolted shut and opened with their bolts (starts as tag_secure).
	var/secure = FALSE
	/// The chamber's gas watch reported a change since the last step.
	var/chamber_heard = FALSE
	var/tag_pump_out_internal
	var/tag_pump_out_external

	// The devices, by relation (CAPABILITIES below).
	var/list/obj/machinery/door/airlock/exterior_doors
	var/list/obj/machinery/door/airlock/interior_doors
	var/list/obj/machinery/atmospherics/unary/vent_pump/chamber_pumps
	var/list/obj/machinery/atmospherics/binary/dp_vent_pump/chamber_dp_pumps
	var/list/obj/machinery/atmospherics/unary/vent_pump/pumps_out_internal
	var/list/obj/machinery/atmospherics/unary/vent_pump/pumps_out_external
	var/obj/machinery/airlock_sensor/chamber_sensor
	var/obj/machinery/airlock_sensor/exterior_sensor
	var/obj/machinery/airlock_sensor/interior_sensor
	var/list/obj/machinery/mech_sensor/airlock_mech_sensors
	var/list/obj/machinery/mech_sensor/shuttle_mech_sensors
	/// One gas watch per mixture of the chamber region, while it pumps.
	var/list/datum/native_watch/gas/chamber_watches

// Its relations and setup are in its one CAPABILITIES block (airlock_controllers.dm).
/// The tags the map left out take their defaults from the console's id_tag, before the keyed relations link.
/obj/machinery/embedded_controller/radio/airlock/proc/default_device_tags()
	set_secure(tag_secure)
	if(!id_tag)
		return
	tag_exterior_door ||= "[id_tag]_outer"
	tag_interior_door ||= "[id_tag]_inner"
	tag_airpump ||= "[id_tag]_pump"
	tag_chamber_sensor ||= "[id_tag]_sensor"
	tag_exterior_sensor ||= "[id_tag]_exterior_sensor"
	tag_interior_sensor ||= "[id_tag]_interior_sensor"
	tag_airlock_mech_sensor ||= "[id_tag]_airlock_mech"
	tag_shuttle_mech_sensor ||= "[id_tag]_shuttle_mech"
	if(cycle_to_external_air)
		tag_pump_out_external ||= "[id_tag]_pump_out_external"
		tag_pump_out_internal ||= "[id_tag]_pump_out_internal"

// ---- reading the devices ----

/// The chamber region: the turfs sharing air with the chamber sensor's turf (the pump's, else the console's), nearest first. It never
/// crosses the airlock's own doors, so an open door does not take the room beyond into the chamber.
/obj/machinery/embedded_controller/radio/airlock/proc/chamber_region()
	var/turf/start = get_turf(chamber_sensor)
	if(!start)
		var/atom/pump = LAZYACCESS(chamber_pumps, 1) || LAZYACCESS(chamber_dp_pumps, 1)
		start = get_turf(pump || src)
	if(!start)
		return list()
	var/list/door_turfs = list()
	for(var/obj/machinery/door/airlock/D as anything in (exterior_doors || list()) + (interior_doors || list()))
		door_turfs[get_turf(D)] = TRUE
	var/list/region = list(start)
	var/i = 1
	while(i <= length(region) && length(region) < AIRLOCK_REGION_MAX)
		var/turf/T = region[i++]
		for(var/turf/next as anything in T.get_atmos_adjacent_turfs())
			if(!(next in region) && !door_turfs[next])
				region += next
				if(length(region) >= AIRLOCK_REGION_MAX)
					break
	return region

/// The chamber's pressure: the median over its region (one atmosphere with no air to read, as an airlock assumed with no sensor report).
/// The median, not one tile and not the mean: the vent drains or fills its own tile first, and the atmos sim can leave a tile or two of a
/// pumped-down chamber holding a static pocket (21 kPa beside vacuum on Southern Cross's AEG stern airlocks), which held a mean out of the band
/// forever while the chamber was empty.
/obj/machinery/embedded_controller/radio/airlock/proc/chamber_pressure()
	var/list/readings = list()
	for(var/turf/T as anything in chamber_region())
		var/datum/gas_mixture/air = T.return_air()
		if(air)
			readings += air.return_pressure()
	var/count = length(readings)
	if(!count)
		return ONE_ATMOSPHERE
	sortTim(readings, GLOBAL_PROC_REF(cmp_numeric_asc))
	var/middle = round((count + 1) / 2)
	return (count % 2) ? readings[middle] : (readings[middle] + readings[middle + 1]) / 2

/// Outside: what the exterior sensor reads (vacuum without one, as before).
/obj/machinery/embedded_controller/radio/airlock/proc/external_pressure()
	var/datum/gas_mixture/air = exterior_sensor?.return_air()
	return air ? air.return_pressure() : 0

/// Inside: what the interior sensor reads (one atmosphere without one).
/obj/machinery/embedded_controller/radio/airlock/proc/internal_pressure()
	var/datum/gas_mixture/air = interior_sensor?.return_air()
	return air ? air.return_pressure() : ONE_ATMOSPHERE

/// A door set's state for the window and the door logic: list(state = "open"|"closed", lock = "locked"|"unlocked"). Open when any door is,
/// locked only when every door is bolted; no door at all reads closed and locked.
/proc/airlock_doors_status(list/doors)
	var/open = FALSE
	var/locked = TRUE
	for(var/obj/machinery/door/airlock/D as anything in doors)
		if(!D.density)
			open = TRUE
		if(!is_bolted(D))
			locked = FALSE
	return list("state" = open ? "open" : "closed", "lock" = locked ? "locked" : "unlocked")

/obj/machinery/embedded_controller/radio/airlock/proc/exterior_status()
	return airlock_doors_status(exterior_doors)

/obj/machinery/embedded_controller/radio/airlock/proc/interior_status()
	return airlock_doors_status(interior_doors)

/// Every pump the cycle drives.
/obj/machinery/embedded_controller/radio/airlock/proc/all_pumps()
	. = list()
	. += chamber_pumps || list()
	. += chamber_dp_pumps || list()
	. += pumps_out_internal || list()
	. += pumps_out_external || list()

/// A pump the cycle drives is moving gas.
/obj/machinery/embedded_controller/radio/airlock/proc/pumps_running()
	for(var/obj/machinery/atmospherics/P as anything in all_pumps())
		if(P.use_power)
			return TRUE
	return FALSE

// ---- commanding the devices ----

/// The chamber pumps on (`direction` 1 fills, 0 drains, toward `pressure`) or off. An unpowered vent takes nothing, as from its radio.
/obj/machinery/embedded_controller/radio/airlock/proc/drive_pumps(list/pumps, power, direction = null, pressure = null)
	for(var/obj/machinery/atmospherics/unary/vent_pump/V in pumps)
		V.airlock_pump(power, direction, pressure)
	for(var/obj/machinery/atmospherics/binary/dp_vent_pump/V in pumps)
		V.airlock_pump(power, direction, pressure)

/obj/machinery/embedded_controller/radio/airlock/proc/chamber_pump_list()
	. = list()
	. += chamber_pumps || list()
	. += chamber_dp_pumps || list()

/obj/machinery/embedded_controller/radio/airlock/proc/stop_pumps()
	drive_pumps(all_pumps(), 0)

/// One command to a door set, from what the doors are now: "toggle", "open" or "close", bolted when `secure_doors`. Nothing is sent when
/// the doors are already there.
/obj/machinery/embedded_controller/radio/airlock/proc/toggle_doors(list/doors, secure_doors, command)
	var/list/status = airlock_doors_status(doors)
	var/door_command = null
	if(command == "toggle")
		command = status["state"] == "open" ? "close" : "open"
	switch(command)
		if("close")
			if(secure_doors)
				if(status["state"] == "open")
					door_command = "secure_close"
				else if(status["lock"] == "unlocked")
					door_command = "lock"
			else
				if(status["state"] == "open")
					if(status["lock"] == "locked")
						command_doors(doors, "unlock")
					door_command = "close"
				else if(status["lock"] == "locked")
					door_command = "unlock"
		if("open")
			if(secure_doors)
				if(status["state"] == "closed")
					door_command = "secure_open"
				else if(status["lock"] == "unlocked")
					door_command = "lock"
			else
				if(status["state"] == "closed")
					if(status["lock"] == "locked")
						command_doors(doors, "unlock")
					door_command = "open"
				else if(status["lock"] == "locked")
					door_command = "unlock"
	if(door_command)
		command_doors(doors, door_command)

/obj/machinery/embedded_controller/radio/airlock/proc/command_doors(list/doors, command)
	for(var/obj/machinery/door/airlock/D as anything in doors)
		D.airlock_command(command)

/obj/machinery/embedded_controller/radio/airlock/proc/close_doors()
	toggle_doors(interior_doors, TRUE, "close")
	toggle_doors(exterior_doors, TRUE, "close")

/obj/machinery/embedded_controller/radio/airlock/proc/open_doors()
	toggle_doors(interior_doors, secure, "open")
	toggle_doors(exterior_doors, secure, "open")

/// At the end of a cycle (or from the access controller's buttons): the door toward the target opens, the other shuts.
/obj/machinery/embedded_controller/radio/airlock/proc/cycle_doors(target)
	if(dock_locked())
		return
	switch(target)
		if(AIRLOCK_TARGET_OUTOPEN)
			toggle_doors(interior_doors, secure, "close")
			toggle_doors(exterior_doors, secure, "open")
		if(AIRLOCK_TARGET_INOPEN)
			toggle_doors(exterior_doors, secure, "close")
			toggle_doors(interior_doors, secure, "open")
		if(AIRLOCK_TARGET_NONE)
			var/command = secure ? "lock" : "unlock"
			command_doors(exterior_doors, command)
			command_doors(interior_doors, command)

/obj/machinery/embedded_controller/radio/airlock/proc/set_mech_regulation(on)
	for(var/obj/machinery/mech_sensor/S as anything in (airlock_mech_sensors || list()) + (shuttle_mech_sensors || list()))
		S.set_on(on)

/obj/machinery/embedded_controller/radio/airlock/proc/check_exterior_door_secured()
	var/list/status = exterior_status()
	return status["state"] == "closed" && status["lock"] == "locked"

/obj/machinery/embedded_controller/radio/airlock/proc/check_interior_door_secured()
	var/list/status = interior_status()
	return status["state"] == "closed" && status["lock"] == "locked"

/obj/machinery/embedded_controller/radio/airlock/proc/check_doors_secured()
	return check_exterior_door_secured() && check_interior_door_secured()

// ---- the chamber watch ----

/// Watches the chamber region's mixtures while it pumps; drops the watches otherwise.
/obj/machinery/embedded_controller/radio/airlock/proc/watch_chamber(on)
	if(!on)
		if(chamber_watches)
			gas_watch_many_clear(src, nameof(chamber_watches))
		return
	var/list/mixtures = list()
	for(var/turf/T as anything in chamber_region())
		var/datum/gas_mixture/air = T.return_air()
		if(air)
			mixtures |= air
	gas_watch_many(src, nameof(chamber_watches), mixtures, GAS_DEPENDENCY_PRESSURE, PROC_REF(chamber_pressure_heard))

/// The chamber's air changed: the step judges the cycle again.
/obj/machinery/embedded_controller/radio/airlock/proc/chamber_pressure_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	chamber_heard = TRUE
	work_start(src)

// ---- commands ----

/obj/machinery/embedded_controller/radio/airlock/user_command(command)
	if(dock_locked())
		return FALSE
	. = TRUE
	switch(command)
		if("cycle_ext")
			//If airlock is already cycled in this direction, just toggle the doors.
			if(!purge && abs(external_pressure() - chamber_pressure()) <= SKIPCYCLE_MARGIN)
				toggle_doors(exterior_doors, secure, "toggle")
			//only respond to these commands if the airlock isn't already doing something
			else if(cycle_state == target_state)
				begin_cycle_out()
		if("cycle_int")
			if(!purge && abs(internal_pressure() - chamber_pressure()) <= SKIPCYCLE_MARGIN)
				toggle_doors(interior_doors, secure, "toggle")
			else if(cycle_state == target_state)
				begin_cycle_in()
		if("cycle_ext_door")
			cycle_doors(AIRLOCK_TARGET_OUTOPEN)
		if("cycle_int_door")
			cycle_doors(AIRLOCK_TARGET_INOPEN)
		if("abort")
			stop_cycling()
		if("force_ext")
			toggle_doors(exterior_doors, secure, "toggle")
		if("force_int")
			toggle_doors(interior_doors, secure, "toggle")
		if("purge")
			set_purge(!purge)
			if(purge)
				close_doors()
				set_cycle(AIRLOCK_STATE_PREPARE, AIRLOCK_TARGET_NONE)
		if("secure")
			set_secure(!secure)
			command_doors(interior_doors, secure ? "lock" : "unlock")
			command_doors(exterior_doors, secure ? "lock" : "unlock")
		else
			. = FALSE
	work_start(src)

/// The radio's external protocol: a button or a sensor names this console's id_tag with "cycle", "cycle_interior" or "cycle_exterior".
/// Everything else on the frequency is ignored and wakes nothing.
/obj/machinery/embedded_controller/radio/airlock/receive_signal(datum/signal/signal, receive_method, receive_param)
	if(!signal || signal.encryption || !id_tag || signal.data["tag"] != id_tag)
		return
	var/access_only = istype(src, /obj/machinery/embedded_controller/radio/airlock/access_controller)
	switch(signal.data["command"])
		if("cycle_exterior")
			user_command(access_only ? "cycle_ext_door" : "cycle_ext")
		if("cycle_interior")
			user_command(access_only ? "cycle_int_door" : "cycle_int")
		if("cycle")
			if(interior_status()["state"] == "open")		//handle backwards compatibility
				user_command("cycle_ext")
			else
				user_command("cycle_int")

/obj/machinery/embedded_controller/radio/airlock/proc/set_cycle(new_state, new_target)
	if(cycle_state == new_state && target_state == new_target)
		return
	log_game("Airlock [id_tag] cycle [cycle_state] -> [target_state] now [new_state] -> [new_target]")
	set_cycle_state(new_state)
	set_target_state(new_target)

/obj/machinery/embedded_controller/radio/airlock/proc/set_purge(value)
	if(purge == value)
		return
	purge = value
	tracked_changed(src, nameof(purge))
SETTER(/obj/machinery/embedded_controller/radio/airlock, purge)

/obj/machinery/embedded_controller/radio/airlock/proc/set_secure(value)
	if(secure == value)
		return
	secure = value
	tracked_changed(src, nameof(secure))
SETTER(/obj/machinery/embedded_controller/radio/airlock, secure)

/obj/machinery/embedded_controller/radio/airlock/proc/begin_cycle_in()
	set_cycle(AIRLOCK_STATE_IDLE, AIRLOCK_TARGET_INOPEN)
	set_purge(cycle_to_external_air)
	work_start(src)

/obj/machinery/embedded_controller/radio/airlock/proc/begin_cycle_out()
	set_cycle(AIRLOCK_STATE_IDLE, AIRLOCK_TARGET_OUTOPEN)
	set_purge(cycle_to_external_air)
	work_start(src)

/obj/machinery/embedded_controller/radio/airlock/proc/begin_dock_cycle()
	set_cycle(AIRLOCK_STATE_IDLE, AIRLOCK_TARGET_INOPEN)
	work_start(src)

/obj/machinery/embedded_controller/radio/airlock/proc/stop_cycling()
	set_cycle(AIRLOCK_STATE_IDLE, AIRLOCK_TARGET_NONE)
	work_start(src) // the idle step shuts the pumps and drops the watch

/obj/machinery/embedded_controller/radio/airlock/proc/done_cycling()
	return cycle_state == AIRLOCK_STATE_IDLE && target_state == AIRLOCK_TARGET_NONE

/obj/machinery/embedded_controller/radio/airlock/proc/cycling()
	return cycle_state != target_state

// ---- the step ----

/// Steps while a cycle prepares (its doors swinging), a change was heard, or an idle airlock still has a pump running or a watch armed.
/obj/machinery/embedded_controller/radio/airlock/needs_step()
	if(cycle_state == AIRLOCK_STATE_DEPRESSURIZE || cycle_state == AIRLOCK_STATE_PRESSURIZE)
		return chamber_heard || !pumps_running()
	if(cycling())
		return TRUE
	return chamber_heard || pumps_running() || length(chamber_watches)

/obj/machinery/embedded_controller/radio/airlock/controller_step()
	chamber_heard = FALSE
	if(cycle_state == AIRLOCK_STATE_IDLE)
		if(target_state)
			switch(target_state)
				if(AIRLOCK_TARGET_INOPEN)
					target_pressure = internal_pressure()
				if(AIRLOCK_TARGET_OUTOPEN)
					target_pressure = external_pressure()
			//lock down the airlock before activating pumps
			close_doors()
			set_cycle(AIRLOCK_STATE_PREPARE, target_state)
		else
			//make sure to return to a sane idle state
			if(pumps_running())
				stop_pumps()
			watch_chamber(FALSE)

	if((cycle_state == AIRLOCK_STATE_PRESSURIZE || cycle_state == AIRLOCK_STATE_DEPRESSURIZE) && !check_doors_secured())
		//the airlock will not allow itself to continue to cycle when any of the doors are forced open.
		stop_cycling()
		stop_pumps()
		watch_chamber(FALSE)

	switch(cycle_state)
		if(AIRLOCK_STATE_PREPARE)
			if(check_doors_secured())
				prepare_pumping()
		if(AIRLOCK_STATE_PRESSURIZE)
			playsound(src, announcer_airlock_message(AIRLOCK_MSG_BEEP), 100, 0)
			var/chamber = chamber_pressure()
			if(chamber >= target_pressure * 0.95)
				stop_pumps()
				finish_cycle(AIRLOCK_MSG_END_IN)
			else if(!pumps_running())
				resume_pumping(TRUE, chamber) // filled, switched off, then lost gas again before the doors cycled
		if(AIRLOCK_STATE_DEPRESSURIZE)
			playsound(src, announcer_airlock_message(AIRLOCK_MSG_BEEP), 100, 0)
			var/chamber = chamber_pressure()
			if(chamber <= max(target_pressure * 1.05, MIN_TARGET_PRESSURE))
				stop_pumps()
				if(purge)
					set_purge(FALSE)
					target_pressure = (target_state == AIRLOCK_TARGET_INOPEN ? internal_pressure() : external_pressure())
					if(target_pressure > SKIPCYCLE_MARGIN)
						set_cycle(AIRLOCK_STATE_PREPARE, target_state) // Skip pressurizing if target pressure is already close enough.
						prepare_pumping()
					else
						finish_cycle(AIRLOCK_MSG_END_OUT)
				else
					finish_cycle(AIRLOCK_MSG_END_OUT)
			else if(!pumps_running())
				resume_pumping(FALSE, chamber) // pumped down, switched off, then gas came back before the doors cycled

/// Doors shut and bolted: pick the direction from the chamber and the target, start the pumps and watch the chamber.
/obj/machinery/embedded_controller/radio/airlock/proc/prepare_pumping()
	var/chamber = chamber_pressure()
	var/pressure = target_pressure
	if(purge)
		//purge apparently means clearing the airlock chamber to vacuum (then refilling, handled later)
		pressure = 0
		set_cycle(AIRLOCK_STATE_DEPRESSURIZE, target_state)
		playsound(src, announcer_airlock_message(AIRLOCK_MSG_OUT), 100, 0)
		if(!cycle_to_external_air || target_state == AIRLOCK_TARGET_OUTOPEN) // if going outside, pump internal air into air tank
			drive_pumps(chamber_pump_list(), 1, 0, pressure)
		else
			drive_pumps(pumps_out_internal, 1, 0, pressure) // if going inside, pump external air out of the airlock
			drive_pumps(pumps_out_external, 1, 1, 15000) // make sure the air is actually going outside
	else if(chamber <= pressure)
		set_cycle(AIRLOCK_STATE_PRESSURIZE, target_state)
		playsound(src, announcer_airlock_message(AIRLOCK_MSG_IN), 100, 0)
		if(!cycle_to_external_air || target_state == AIRLOCK_TARGET_INOPEN) // if going inside, pump air into airlock
			drive_pumps(chamber_pump_list(), 1, 1, pressure)
		else
			drive_pumps(pumps_out_internal, 1, 1, pressure) // if going outside, fill airlock with external air
			drive_pumps(pumps_out_external, 1, 0, 0)
	else if(!cycle_to_external_air)
		set_cycle(AIRLOCK_STATE_DEPRESSURIZE, target_state)
		playsound(src, announcer_airlock_message(AIRLOCK_MSG_OUT), 100, 0)
		drive_pumps(chamber_pump_list(), 1, 0, pressure)
	else
		set_purge(TRUE) // should always purge first if using external air, chamber pressure should never be higher than target pressure here
	//Make sure the airlock isn't aiming for pure vacuum - an impossibility
	target_pressure = max(target_pressure, MIN_TARGET_PRESSURE)
	var/pumping = cycle_state == AIRLOCK_STATE_PRESSURIZE || cycle_state == AIRLOCK_STATE_DEPRESSURIZE
	watch_chamber(pumping)
	// The next step judges the chamber once without waiting for a change: a chamber already in the band (a dock cycle between two
	// pressurized ports) never changes, and would wait for the watch forever.
	chamber_heard = pumping

/// The chamber reached its target: the doors toward the target open and the airlock rests.
/obj/machinery/embedded_controller/radio/airlock/proc/finish_cycle(message)
	var/target = target_state
	watch_chamber(FALSE)
	set_cycle(AIRLOCK_STATE_IDLE, AIRLOCK_TARGET_NONE)
	cycle_doors(target)
	playsound(src, announcer_airlock_message(message), 100, 0)

/// A cycle whose chamber left the target band after its pump stopped waited for a pressure it would never reach again (41348618ec): it
/// pumps again, with the prepare step's own commands, aimed past the band the cycle ends in (aimed at the target itself, the vent idled at its
/// bound with the reading just outside the band).
/obj/machinery/embedded_controller/radio/airlock/proc/resume_pumping(pressurize, chamber)
	var/pressure = purge ? 0 : target_pressure * (pressurize ? 1.1 : 0.9)
	log_game("Airlock [id_tag] resumes [pressurize ? "pressurizing" : "depressurizing"]: chamber [chamber] kPa, target [target_pressure] kPa, pump off")
	if(pressurize)
		if(!cycle_to_external_air || target_state == AIRLOCK_TARGET_INOPEN)
			drive_pumps(chamber_pump_list(), 1, 1, pressure)
		else
			drive_pumps(pumps_out_internal, 1, 1, pressure)
			drive_pumps(pumps_out_external, 1, 0, 0)
		return
	if(!cycle_to_external_air || target_state == AIRLOCK_TARGET_OUTOPEN)
		drive_pumps(chamber_pump_list(), 1, 0, pressure)
	else
		drive_pumps(pumps_out_internal, 1, 0, pressure)
		drive_pumps(pumps_out_external, 1, 1, 15000)

// ---- the devices' side of the direct calls ----

/// The airlock console's command (it holds this vent by relation): on with a direction and a bound, or off. An unpowered vent ignores it,
/// as its radio did; the area's air alarms hear its new status.
/obj/machinery/atmospherics/unary/vent_pump/proc/airlock_pump(power, direction, pressure)
	if(!operable())
		return
	set_use_power(power)
	if(!isnull(direction))
		set_pump_direction(direction)
	if(!isnull(pressure))
		set_external_pressure_bound(clamp(pressure, 0, ONE_ATMOSPHERE * 50))
	area_air_status_soon(src)

/// The airlock console's command (it holds this vent by relation): on with a direction and a bound, or off. Direction 0 (siphon) and a
/// bound of 0 (vacuum) are commands like any other: a depressurizing cycle needs both.
/obj/machinery/atmospherics/binary/dp_vent_pump/proc/airlock_pump(power, direction, pressure)
	set_use_power(power)
	if(!isnull(direction))
		set_pump_direction(direction)
	if(!isnull(pressure))
		set_external_pressure_bound(between(0, pressure, ONE_ATMOSPHERE * 50))

#undef AIRLOCK_STATE_IDLE
#undef AIRLOCK_STATE_PREPARE
#undef AIRLOCK_STATE_DEPRESSURIZE
#undef AIRLOCK_STATE_PRESSURIZE

#undef AIRLOCK_TARGET_NONE
#undef AIRLOCK_TARGET_INOPEN
#undef AIRLOCK_TARGET_OUTOPEN

#undef MIN_TARGET_PRESSURE
#undef SKIPCYCLE_MARGIN
#undef AIRLOCK_REGION_MAX
