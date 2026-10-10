/obj/machinery/embedded_controller
	name = "Embedded Controller"
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	var/datum/embedded_program/program	//the currently executing program
	var/list/valid_actions
	on = 1

CAPABILITIES(/obj/machinery/embedded_controller)
	silicon_ui()
	started_work(step = PROC_REF(work_step))
	owns_one(nameof(program), /datum/embedded_program, starts = nameof(program))
	interface("EmbeddedController")
	// the window's buttons are its program's commands (the old UI_ACT_FALLBACK): every action no other op names, if the type lists it
	op("program_command", ui_act("*"), needs(req(PROC_REF(command_listed), silent = TRUE)), then(PROC_REF(ui_act_program_command)))
	op("embedded_controller_open_ui", hand(), ungated(), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/embedded_controller/Initialize(mapload)
	return ..()


/obj/machinery/embedded_controller/examine(mob/user, infix, suffix)
	. = ..()
	if(in_range(src, user))
		. += "It has an ID tag of \"[program?.id_tag]\""

/obj/machinery/embedded_controller/proc/post_signal(datum/signal/signal, comm_line)
	return 0

/obj/machinery/embedded_controller/receive_signal(datum/signal/signal, receive_method, receive_param)
	if(!signal || signal.encryption) return

	if(program)
		program.receive_signal(signal, receive_method, receive_param)
		if(program.signal_requires_processing(signal, receive_method, receive_param))
			work_start(src)


/// The controller's actions are its program's commands, listed per type in valid_actions.
/obj/machinery/embedded_controller/proc/command_listed(datum/act/op/A)
	return ((A.window_action() in valid_actions)) ? null : MSG(req_failed)

/// A program command from the window.
/obj/machinery/embedded_controller/proc/ui_act_program_command(datum/act/op/A)
	add_fingerprint(A.actor)
	work_start(src)
	program.receive_user_command(A.window_action())
	return TRUE

/obj/machinery/embedded_controller/proc/work_step(datum/act/timer/A)
	if(program)
		program.periodic_step()

	update_icon()
	if(!program || !program.memory["processing"])
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
	power_channel = ENVIRON
	density = FALSE
	unacidable = TRUE
	flags = WALL_ITEM

	var/id_tag

	var/frequency = AIRLOCK_FREQ
	var/radio_filter = null
	var/datum/radio_frequency/radio_connection

/obj/machinery/embedded_controller/radio/Initialize(mapload)
	set_frequency(frequency) // Set it before parent instantiates program
	. = ..()

DECLARE_APPEARANCE_PROC(/obj/machinery/embedded_controller/radio, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/embedded_controller/radio/appearance_overlays()
	. = list()
	if(on && program)
		if(program.memory["processing"])
			icon_state = "airlock_control_process"
		else
			icon_state = "airlock_control_standby"
	else
		icon_state = "airlock_control_off"


/obj/machinery/embedded_controller/radio/post_signal(datum/signal/signal, radio_filter = null)
	signal.transmission_method = TRANSMISSION_RADIO
	if(radio_connection())
		//use_power(radio_power_use)	//neat idea, but causes way too much lag.
		return radio_connection().post_signal(src, signal, radio_filter)
	else
		spent(signal)

/obj/machinery/embedded_controller/radio/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, radio_filter))

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/embedded_controller/radio/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
