/obj/machinery/embedded_controller
	name = "Embedded Controller"
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	use_power = USE_POWER_IDLE
	/// The docking port this console runs (a docking console's type sets it to the port type it makes), or null.
	var/datum/docking_port/port
	var/list/valid_actions
	on = 1

/// TRUE while the controller has work (a cycle, a docking handshake): work_step() writes it each step, the display shows it.
/obj/machinery/embedded_controller/var/processing_shown = FALSE

CAPABILITIES(/obj/machinery/embedded_controller)
	configure(uses_power(idle = 10))
	silicon_ui()
	started_work(step = PROC_REF(work_step))
	owns_one(nameof(port), /datum/docking_port, starts = nameof(port))
	// Each console type opens its own window (interface() in its block); its buttons are its commands, one op per command, each run by
	// ui_act_program_command() when the type lists it in valid_actions.
	op("embedded_controller_open_ui", hand(), ungated(), then(PROC_REF(interaction_open_ui_impl)))




/// The controller's commands are listed per type in valid_actions: a command op the type inherits but does not list is refused.
/obj/machinery/embedded_controller/proc/command_listed(datum/act/op/A)
	return ((A.window_action() in valid_actions)) ? null : MSG(req_failed)

/// A command from the window: the op's window action is the command.
/obj/machinery/embedded_controller/proc/ui_act_program_command(datum/act/op/A)
	add_fingerprint(A.actor)
	work_start(src)
	run_command(A.window_action())
	return TRUE

/// A command from the window: the docking port takes its own, the console the rest.
/obj/machinery/embedded_controller/proc/run_command(command)
	if(port?.user_command(command))
		return TRUE
	return user_command(command)

/// The console's own commands (an airlock's cycle buttons); TRUE when it took the command.
/obj/machinery/embedded_controller/proc/user_command(command)
	return FALSE

/// The console's own step (an airlock's cycle).
/obj/machinery/embedded_controller/proc/controller_step()
	return

/// Whether the console's own work keeps it stepping.
/obj/machinery/embedded_controller/proc/needs_step()
	return FALSE

/// The airlocks a docking port on this console cycles (its relations; none by default).
/obj/machinery/embedded_controller/proc/port_airlocks()
	return list()

/// The hatch doors a docking port on this console opens and bolts (its relations; none by default).
/obj/machinery/embedded_controller/proc/port_hatches()
	return list()

/obj/machinery/embedded_controller/proc/work_step(datum/act/timer/A)
	controller_step()
	port?.handshake_step()

	var/working = !!needs_step() || !!port?.needs_step()
	set_processing_shown(working)
	if(!working)
		return PROCESS_KILL

/obj/machinery/embedded_controller/power_change()
	. = ..()
	work_start(src)

/// Old attack_hand: a tool user opens the window.
/obj/machinery/embedded_controller/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.IsAdvancedToolUser())
		return TRUE
	tgui_interact(user)
	return TRUE

//
// Embedded controller with a radio! (Most things (All things?) use this)
//
/obj/machinery/embedded_controller/radio
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_control_standby"
	density = FALSE
	flags = WALL_ITEM

	var/id_tag

	var/frequency = AIRLOCK_FREQ
	var/radio_filter = null
	var/datum/radio_frequency/radio_connection

CAPABILITIES(/obj/machinery/embedded_controller/radio)
	configure(movable_motion(unacidable = TRUE))
	configure(uses_power(channel = ENVIRON))
	ref_one(nameof(radio_connection), /datum/radio_frequency)
	radio_listen(freq = nameof(frequency), via = PROC_REF(set_frequency)) // tuned from init: an airlock hears its buttons' commands (airlock_cycle.dm receive_signal())

/// The state names of the controller's display ("<base>_off", "_standby", "_process").
/obj/machinery/embedded_controller/radio/var/display_base = "airlock_control"

/// What the controller shows: off while switched off, else standing by or working.
/obj/machinery/embedded_controller/radio/draw(datum/look/look)
	..()
	if(!on)
		look.state("[display_base]_off")
	else
		look.state("[display_base]_[processing_shown ? "process" : "standby"]")


/obj/machinery/embedded_controller/radio/examine(mob/user, infix, suffix)
	. = ..()
	if(in_range(src, user))
		. += "It has an ID tag of \"[id_tag]\""


/obj/machinery/embedded_controller/radio/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, radio_filter))

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/embedded_controller/radio/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
