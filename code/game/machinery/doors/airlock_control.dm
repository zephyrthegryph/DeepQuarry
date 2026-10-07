// This code allows for airlocks to be controlled externally by setting an id_tag and comm frequency (disables ID access)
/obj/machinery/door/airlock
	var/id_tag
	var/frequency
	var/list/shockedby
	var/datum/radio_frequency/radio_connection
	var/last_reported_density = -1
	var/last_reported_locked = -1
	/// The command the door is currently attempting to complete; command_step() retries it every second while set (airlock.dm declares the every()).
	var/cur_command

TRACKED_BRIDGED(/obj/machinery/door/airlock, cur_command, CHANGE_MACHINE_SETTINGS)

/obj/machinery/door/airlock/proc/command_step(datum/act/A)
	if (power_systems_on())
		execute_current_command()

/obj/machinery/door/airlock/receive_signal(datum/signal/signal)
	if (!power_systems_on()) return //no power

	if(!signal || signal.encryption) return

	if(id_tag != signal.data["tag"] || !signal.data["command"]) return

	set_cur_command(signal.data["command"])
	execute_current_command()

/obj/machinery/door/airlock/proc/execute_current_command()
	if(operating)
		return //emagged or busy doing something else

	if (!cur_command)
		return
	if(cur_command != "update" && command_completed(cur_command))
		check_completion()
		return

	do_command(cur_command)

/obj/machinery/door/airlock/proc/check_completion(do_lock, delayed_status)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	// The command's own swing finishes this same moment (its last frame and this check are due together, and
	// may run in either order), so the bolts drop even mid-swing: refused for `operating`, the command stayed
	// pending, the door autoclosed and the command reopened it, forever.
	if(do_lock)
		set_bolted(src, TRUE, TRUE)
	if(delayed_status)
		// ALLOW(sys_om_after_rearm): one retry that waits for the delayed status to land, not a loop over state
		after(src, 0.2 SECONDS, PROC_REF(check_completion))
		return
	var/completed_command = cur_command
	if(command_completed(completed_command))
		set_cur_command(null)
	send_status(force = completed_command == "update")

/obj/machinery/door/airlock/proc/do_command(command)
	switch(command)
		if("open")
			open()
			after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion))

		if("close")
			close()
			after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion))

		if("unlock")
			set_bolted(src, FALSE)
			check_completion()

		if("lock")
			check_completion(TRUE)

		if("secure_open")
			set_bolted(src, FALSE)

			after(src, 0.2 SECONDS, PROC_REF(do_secure_open))

		if("secure_close")
			set_bolted(src, FALSE)
			close()
			after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion), with = list(TRUE, 0.2 SECONDS))

		if("update")
			check_completion(delayed_status = TRUE)

/obj/machinery/door/airlock/proc/do_secure_open()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	open()
	after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion), with = list(TRUE))

/obj/machinery/door/airlock/proc/command_completed(command)
	switch(command)
		if("open")
			return (!density)

		if("close")
			return density

		if("unlock")
			return !is_bolted(src)

		if("lock")
			return is_bolted(src)

		if("secure_open")
			return (is_bolted(src) && !density)

		if("secure_close")
			return (is_bolted(src) && density)

		if("update")
			return TRUE // We just want the send_status() call from check_completion()

	return 1	//Unknown command. Just assume it's completed.

/obj/machinery/door/airlock/proc/send_status(bumped = FALSE, force = FALSE)
	if(radio_connection())
		if(!force && !bumped && density == last_reported_density && is_bolted(src) == last_reported_locked)
			return
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = EXPIRY_AT(src, CLOCK_WORLD, 0)

		signal.data["door_status"] = density?("closed"):("open")
		signal.data["lock_status"] = is_bolted(src) ? "locked" : "unlocked"

		if (bumped)
			signal.data["bumped_with_access"] = 1

		radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
		last_reported_density = density
		last_reported_locked = is_bolted(src)

/obj/machinery/door/airlock/open(surpress_send)
	. = ..()
	if(!surpress_send) send_status()

/obj/machinery/door/airlock/close(forced= FALSE, ignore_safties = FALSE, crush_damage)
	. = ..()
	if(!forced) send_status()

/obj/machinery/door/airlock/proc/set_frequency(new_frequency)
	rel_clear(src, nameof(radio_connection))
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	last_reported_density = -1
	last_reported_locked = -1

	if(new_frequency)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, new_frequency, RADIO_AIRLOCK))

/obj/machinery/airlock_sensor
	maintenance_flags = MACHINE_MAINT_STANDARD
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_sensor_off"
	layer = ABOVE_WINDOW_LAYER
	name = "airlock sensor"
	desc = "Sends atmospheric readings to a nearby controller."

	anchored = TRUE
	power_channel = ENVIRON
	circuit = /obj/item/circuitboard/airlock_cycling

	var/id_tag
	var/master_tag
	var/frequency = AIRLOCK_FREQ
	var/command = "cycle"

	var/datum/radio_frequency/radio_connection

	on = 1
	var/alert = 0
	var/previousPressure

// ---- what an airlock sensor is, declared ----
//
// It reads the pressure where it stands and sends it to its airlock controller whenever the reading (to a tenth of a kilopascal) changes: it waits on a gas
// watch (woken only when the reading would differ) and never polls. A hand on it asks the controller to cycle the airlock (the master tag and the command it is set to). A multitool sets its tags, its frequency and its command.

CAPABILITIES(/obj/machinery/airlock_sensor)
	gas_watch(mask = GAS_DEPENDENCY_PRESSURE, changed = PROC_REF(pressure_heard))
	multitool_settings(list(
		list("Master Tag", "master_tag", "text", 30),
		list("ID Tag", "id_tag", "text", 30),
		list("Frequency", "frequency", "frequency"),
		list("Command", "command", "text", MAX_TGUI_INPUT, "Valid options include: cycle, cycle_interior, cycle_exterior.")))
	op("cycle", hand(), label("Use"), wait(0), then(PROC_REF(cycle_asked)))

/// A hand on the sensor asks the controller to cycle.
/obj/machinery/airlock_sensor/proc/cycle_asked(datum/act/op/A)
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.data["tag"] = master_tag
	signal.data["command"] = command

	radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
	flick("airlock_sensor_cycle", src)
	return OP_OK

/// Waits for the air: one gas watch on the mixture here, woken only when the reading (to a tenth of a kilopascal) would be new, so a change that leaves
/// it identical cannot affect a controller or the icon.
/obj/machinery/airlock_sensor/proc/register_gas_dependencies()
	gas_watch_arm(src)

/obj/machinery/airlock_sensor/proc/pressure_heard(list/observation, observation_index)
	if(gas_wake_condition())
		SSmachines.gas_woken_last++
		gas_dependency_wake_count++
		wake_from_gas()

/obj/machinery/airlock_sensor/proc/gas_wake_condition()
	var/datum/gas_mixture/environment = return_air()
	return on && environment && round(environment.return_pressure(), 0.1) != previousPressure

/obj/machinery/airlock_sensor/proc/unregister_gas_dependencies()
	var/datum/cap_data/gas_watch/data = gas_watch_data(src)
	if(data)
		rel_clear(data, nameof(data.watch))
		data.armed_id = null

/// The reading changed: it is read and sent, and the sensor waits again.
/obj/machinery/airlock_sensor/proc/wake_from_gas()
	unregister_gas_dependencies()
	sample_pressure()

/// A sensor on the map reads once when the world is up and then waits.
/obj/machinery/airlock_sensor/on_materialize()
	. = ..()
	sample_pressure()

/// Reads the pressure here: a reading that differs from the last (to a tenth of a kilopascal) is sent to the controller, and below 80% of an
/// atmosphere the sensor shows its alert.
/obj/machinery/airlock_sensor/proc/sample_pressure()
	if(!on)
		unregister_gas_dependencies()
		return
	// return_air() is guaranteed non-null (empty vacuum mix on airless tiles): a sensor on a vacuum dock tile reports 0 pressure.
	var/datum/gas_mixture/air_sample = return_air()
	var/pressure = round(air_sample.return_pressure(), 0.1)

	if(abs(pressure - previousPressure) > 0.001 || previousPressure == null)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = EXPIRY_AT(src, CLOCK_WORLD, 0)
		signal.data["pressure"] = num2text(pressure)

		radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)

		previousPressure = pressure

		alert = (pressure < ONE_ATMOSPHERE*0.8)

		changed(src)
	register_gas_dependencies()

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/airlock_sensor/draw(datum/look/look)
	..()
	look.state("airlock_sensor_[on ? appearance_mode() : "off"]")
	if(panel_open == 1)
		look.state("airlock_sensor_open")

/obj/machinery/airlock_sensor/proc/appearance_mode()
	return alert ? "alert" : "standby"

/obj/machinery/airlock_sensor/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_AIRLOCK))

/obj/machinery/airlock_sensor/Initialize(mapload)
	. = ..()
	set_frequency(frequency)

/obj/machinery/airlock_sensor/examine(mob/user, infix, suffix)
	. = ..()
	if(in_range(src, user))
		. += "It has a master tag of \"[master_tag]\"."
		. += "It has an ID tag of \"[id_tag]\"."
		. += "It has a frequency of [frequency]."
		. += "It has a command of \"[command]\"."
		if(panel_open)
			. += "It's panel is open."

/obj/machinery/airlock_sensor/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/airlock_sensor/airlock_interior
	command = "cycle_interior"

/obj/machinery/airlock_sensor/airlock_exterior
	command = "cycle_exterior"

// Return the air from the turf in "front" of us (Used in shuttles, so it can be in the shuttle area but sense outside it)
/obj/machinery/airlock_sensor/airlock_exterior/shuttle/return_air()
	var/turf/T = get_step(src, dir)
	if(isnull(T))
		return ..()
	return T.return_air()

/obj/machinery/access_button
	maintenance_flags = MACHINE_MAINT_STANDARD
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_button_standby"
	layer = ABOVE_WINDOW_LAYER
	name = "access button"

	anchored = TRUE
	power_channel = ENVIRON
	circuit = /obj/item/circuitboard/airlock_cycling

	var/master_tag
	var/frequency = AMAG_ELE_FREQ
	var/command = "cycle"

	var/datum/radio_frequency/radio_connection

	on = 1

// ---- what an access button is, declared ----
//
// A button that asks an airlock controller to run its command (the master tag and the command it is set to) for whoever has access: a hand
// presses it, so does an ID or a PDA swiped on it. A multitool sets its tag, its frequency and its command.

MSG_DEF_SELF(access_button/denied, "Access Denied")

CAPABILITIES(/obj/machinery/access_button)
	multitool_settings(list(
		list("Tag", "master_tag", "text", 30),
		list("Frequency", "frequency", "frequency"),
		list("Command", "command", "text", MAX_TGUI_INPUT, "Valid options include: 'open', 'close', 'unlock', 'lock', 'secure_open', 'secure_close', and 'update', without the '. Additionally, some airlocks support 'cycle', 'cycle_interior', and 'cycle_exterior'.")))
	op("press", inputs(hand(), item(/obj/item/card/id), item(/obj/item/pda)), label("Use"), wait(0), needs(req(PROC_REF(button_allows), because = MSG(access_button/denied))), then(PROC_REF(pressed)))
	on_op("press", then(PROC_REF(flash_cycle)), outcome = ACT_REFUSED)

/// Whoever has access presses it.
/obj/machinery/access_button/proc/button_allows(datum/act/op/A)
	return allowed(A.actor)

/// The press: its signal goes to the controller.
/obj/machinery/access_button/proc/pressed(datum/act/op/A)
	add_fingerprint(A.actor)
	if(radio_connection())
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = master_tag
		signal.data["command"] = command

		radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
	flash_cycle()
	return OP_OK

/// The button blinks, pressed or refused.
/obj/machinery/access_button/proc/flash_cycle(datum/act/A)
	flick("access_button_cycle", src)
	return OP_OK

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/access_button/draw(datum/look/look)
	..()
	look.state("access_button_[on ? "standby" : "off"]")
	if(panel_open == 1)
		look.state("access_button_open")

/obj/machinery/access_button/examine(mob/user, infix, suffix)
	. = ..()
	if(in_range(src, user))
		. += "It has a master tag of \"[master_tag]\"."
		. += "It has a frequency of \"[frequency]\"."
		. += "It is sending a command of \"[command]\"."
		if(panel_open)
			. += "It's panel is open."

/obj/machinery/access_button/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/access_button/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_AIRLOCK))

/obj/machinery/access_button/Initialize(mapload)
	. = ..()
	set_frequency(frequency)

/obj/machinery/access_button/airlock_interior
	frequency = AIRLOCK_FREQ
	command = "cycle_interior"

/obj/machinery/access_button/airlock_exterior
	frequency = AIRLOCK_FREQ
	command = "cycle_exterior"

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/proc/radio_connection() as /datum/radio_frequency
	return radio_connection

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/airlock_sensor/proc/radio_connection() as /datum/radio_frequency
	return radio_connection

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/access_button/proc/radio_connection() as /datum/radio_frequency
	return radio_connection

// Remote door buttons find airlocks by id_tag (REL_KEYED sources).
/obj/machinery/door/airlock/relations()
	. = ..()
	. += rel_key(nameof(id_tag))
