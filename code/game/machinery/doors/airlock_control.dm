// This code allows for airlocks to be controlled externally by setting an id_tag and comm frequency (disables ID access)
/obj/machinery/door/airlock
	var/id_tag
	var/frequency
	var/shockedby = list()
	var/datum/radio_frequency/radio_connection
	var/last_reported_density = -1
	var/last_reported_locked = -1

/// The command the door is currently attempting to complete; command_step() retries it while set.
OM_FIELD(/obj/machinery/door/airlock, cur_command, null, CHANGE_MACHINE_SETTINGS)
DECLARE_REPEAT(/obj/machinery/door/airlock, 1 SECOND, command_step, "cur_command")

/obj/machinery/door/airlock/proc/command_step()
	if (arePowerSystemsOn())
		execute_current_command()

/obj/machinery/door/airlock/receive_signal(datum/signal/signal)
	if (!arePowerSystemsOn()) return //no power

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
		lock(forced = TRUE)
	if(delayed_status)
		// ALLOW(sys_om_after_rearm): one-shot deferral, not a loop: the re-armed call passes no args, so delayed_status is FALSE there and it never re-arms.
		om_after(src, 0.2 SECONDS, PROC_REF(check_completion))
		return
	var/completed_command = cur_command
	if(command_completed(completed_command))
		set_cur_command(null)
	send_status(force = completed_command == "update")

/obj/machinery/door/airlock/proc/do_command(command)
	switch(command)
		if("open")
			open()
			om_after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion))

		if("close")
			close()
			om_after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion))

		if("unlock")
			unlock()
			check_completion()

		if("lock")
			check_completion(TRUE)

		if("secure_open")
			unlock()

			om_after(src, 0.2 SECONDS, PROC_REF(do_secure_open))

		if("secure_close")
			unlock()
			close()
			om_after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion), TRUE, 0.2 SECONDS)

		if("update")
			check_completion(delayed_status = TRUE)

/obj/machinery/door/airlock/proc/do_secure_open()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	open()
	om_after(src, anim_length_before_density + anim_length_before_finalize, PROC_REF(check_completion), TRUE)

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

/obj/machinery/door/airlock/Bumped(atom/AM)
	..(AM)
	if(istype(AM, /obj/mecha))
		var/obj/mecha/mecha = AM
		if(density && radio_connection() && mecha?.slot_item(MECHA_SLOT_PILOT) && (src.allowed(mecha?.slot_item(MECHA_SLOT_PILOT)) || src.check_access_list(mecha.operation_req_access)))
			send_status(1)
	return

/obj/machinery/door/airlock/proc/set_frequency(new_frequency)
	rel_clear(src, nameof(radio_connection))
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	last_reported_density = -1
	last_reported_locked = -1

	if(new_frequency)
		rel_set(src, nameof(radio_connection), GLOB.radio_service.add_object(src, new_frequency, RADIO_AIRLOCK))

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

/// Wakes only when process() would transmit something new: it sends pressure rounded to 0.1 kPa,
/// so a change that leaves that reading identical cannot affect an airlock controller or icon.
/obj/machinery/airlock_sensor/proc/register_gas_dependencies()
	var/datum/gas_mixture/environment = return_air()
	om_watch_arm_condition(src, "gas", list(environment?.arena_id()), GAS_DEPENDENCY_PRESSURE, om_callable(src, PROC_REF(gas_wake_condition)), wake_callback = om_callable(src, PROC_REF(wake_from_gas)))

/obj/machinery/airlock_sensor/proc/gas_wake_condition()
	var/datum/gas_mixture/environment = return_air()
	return on && environment && round(environment.return_pressure(), 0.1) != previousPressure

/obj/machinery/airlock_sensor/proc/unregister_gas_dependencies()
	om_watch_disarm(src, "gas")

/obj/machinery/airlock_sensor/proc/wake_from_gas()
	unregister_gas_dependencies()
	MACHINE_WAKE(src)

APPEARANCE_TEMPLATE(/obj/machinery/airlock_sensor, "airlock_sensor_{on?@appearance_mode:off}")
DECLARE_APPEARANCE(/obj/machinery/airlock_sensor, "panel_open", list("1" = list(APPEARANCE_ICON_STATE = "airlock_sensor_open")))

/obj/machinery/airlock_sensor/proc/appearance_mode()
	return alert ? "alert" : "standby"

/obj/machinery/airlock_sensor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/airlock_sensor_cycle,
	)
	..()

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/airlock_sensor_cycle
	id = "airlock_sensor_cycle"
	name = "Use"
	effect = /obj/machinery/airlock_sensor/proc/interaction_cycle

/obj/machinery/airlock_sensor/proc/interaction_cycle(mob/user, obj/item/held, datum/interaction/interaction)
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.data["tag"] = master_tag
	signal.data["command"] = command

	radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
	flick("airlock_sensor_cycle", src)
	return TRUE

/obj/machinery/airlock_sensor/machine_step()
	if(on)
		// return_air() is now guaranteed non-null (empty vacuum mix on airless
		// tiles) — see /turf/open/return_air. A sensor on a vacuum dock tile
		// correctly reports 0 pressure instead of runtiming.
		var/datum/gas_mixture/air_sample = return_air()
		var/pressure = round(air_sample.return_pressure(),0.1)

		if(abs(pressure - previousPressure) > 0.001 || previousPressure == null)
			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO //radio signal
			signal.data["tag"] = id_tag
			signal.data["timestamp"] = EXPIRY_AT(src, CLOCK_WORLD, 0)
			signal.data["pressure"] = num2text(pressure)

			radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)

			previousPressure = pressure

			alert = (pressure < ONE_ATMOSPHERE*0.8)

			update_icon()
	GLOB.machine_service.hibernate_airlock_sensor(src)
	return PROCESS_KILL

/obj/machinery/airlock_sensor/proc/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), GLOB.radio_service.add_object(src, frequency, RADIO_AIRLOCK))

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

/obj/machinery/airlock_sensor/multitool_act(mob/user, obj/item/tool)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(config_chosen), message = "What would you like to configure?", title = "[src] Configuration", choices = list("Master Tag", "ID Tag", "Frequency", "Command", "None"), requires = PROMPT_ADJACENT, buttons = TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/airlock_sensor/proc/config_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/choice = ask.choice
	switch(choice)
		if("Master Tag")
			ask_text_var(user, "master_tag", "The current master tag is \"[master_tag]\", what would you like it to be?", "[src] Master Tag", 30)
		if("ID Tag")
			ask_text_var(user, "id_tag", "The current id tag is \"[id_tag]\", what would you like it to be?", "[src] ID Tag", 30)
		if("Frequency")
			ask_frequency(user, frequency)
		if("Command")
			ask_text_var(user, "command", "The current command is \"[command]\", what would you like it to be? Valid options include: cycle, cycle_interior, cycle_exterior.", "[src] command", MAX_TGUI_INPUT)

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

APPEARANCE_TEMPLATE(/obj/machinery/access_button, "access_button_{on?standby:off}")
DECLARE_APPEARANCE(/obj/machinery/access_button, "panel_open", list("1" = list(APPEARANCE_ICON_STATE = "access_button_open")))

/obj/machinery/access_button/examine(mob/user, infix, suffix)
	. = ..()
	if(in_range(src, user))
		. += "It has a master tag of \"[master_tag]\"."
		. += "It has a frequency of \"[frequency]\"."
		. += "It is sending a command of \"[command]\"."
		if(panel_open)
			. += "It's panel is open."

/obj/machinery/access_button/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/access_button_swipe,
		/datum/interaction/machine_hand/ungated/access_button_use,
	)
	..()

/// Old attackby: swiping an ID or PDA is treated as an attack_hand.
/datum/interaction/machine_item/access_button_swipe
	id = "access_button_swipe"
	name = "Swipe"
	held_type = list(/obj/item/card/id, /obj/item/pda)
	effect = /obj/machinery/access_button/proc/interaction_swipe

/obj/machinery/access_button/proc/interaction_swipe(mob/user, obj/item/I, datum/interaction/interaction)
	attack_hand(user)
	return TRUE

/obj/machinery/access_button/multitool_act(mob/user, obj/item/tool)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(setting_chosen), message = "What would you like to change?", title = "[src] Settings", choices = list("Tag", "Frequency", "Command", "None"), requires = PROMPT_ADJACENT, buttons = TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/access_button/proc/setting_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/choice = ask.choice
	switch(choice)
		if("Tag")
			ask_text_var(user, "master_tag", "[src] has an master tag of \"[master_tag]\". What would you like it to be?", "[src] ID", 30)
		if("Frequency")
			ask_frequency(user, frequency)
		if("Command")
			ask_text_var(user, "command", "[src] has a command of \"[command]\". Valid options include: 'open', 'close', 'unlock', 'lock', 'secure_open', 'secure_close', and 'update', without the '. Additionally, some airlocks support 'cycle', 'cycle_interion', and 'cycle_exterior' '", "[src] command", MAX_TGUI_INPUT)

/datum/interaction/machine_hand/ungated/access_button_use
	id = "access_button_use"
	name = "Use"
	effect = /obj/machinery/access_button/proc/interaction_use

/obj/machinery/access_button/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(!allowed(user))
		to_chat(user, span_warning("Access Denied"))

	else if(radio_connection())
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = master_tag
		signal.data["command"] = command

		radio_connection().post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
	flick("access_button_cycle", src)
	return TRUE

/obj/machinery/access_button/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/access_button/proc/set_frequency(new_frequency)
	GLOB.radio_service.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), GLOB.radio_service.add_object(src, frequency, RADIO_AIRLOCK))

/obj/machinery/access_button/Initialize(mapload)
	. = ..()
	set_frequency(frequency)

/obj/machinery/access_button/airlock_interior
	frequency = AIRLOCK_FREQ
	command = "cycle_interior"

/obj/machinery/access_button/airlock_exterior
	frequency = AIRLOCK_FREQ
	command = "cycle_exterior"

/// Setup at spawn: arm what wakes it (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/airlock_sensor/arm_wakes()
	..()
	register_gas_dependencies()

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
