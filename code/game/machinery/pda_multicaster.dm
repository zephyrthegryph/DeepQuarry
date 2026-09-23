/obj/machinery/pda_multicaster
	name = "\improper PDA multicaster"
	desc = "This machine mirrors messages sent to it to specific departments."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pdamulti"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/telecomms/pda_multicaster
	use_power = USE_POWER_IDLE
	idle_power_usage = 750
	maintenance_flags = MACHINE_MAINT_STANDARD
	var/on = 1		// If we're currently active,
	var/toggle = 1	// If we /should/ be active or not,
	var/list/internal_PDAs = list() // Assoc list of PDAs inside of this, with the department name being the index,

	var/datum/looping_sound/tcomms/soundloop
	var/noisy = TRUE

/obj/machinery/pda_multicaster/Initialize(mapload)
	. = ..()
	internal_PDAs = list("command" = new /obj/item/pda/multicaster/command(src),
		"security" = new /obj/item/pda/multicaster/security(src),
		"engineering" = new /obj/item/pda/multicaster/engineering(src),
		"medical" = new /obj/item/pda/multicaster/medical(src),
		"research" = new /obj/item/pda/multicaster/research(src),
		"exploration" = new /obj/item/pda/multicaster/exploration(src),
		"cargo" = new /obj/item/pda/multicaster/cargo(src),
		"civilian" = new /obj/item/pda/multicaster/civilian(src))

	soundloop = new(list(src), FALSE)
	if(prob(60)) // 60% chance to change the midloop
		if(prob(40))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_02.ogg' = 1)
			soundloop.mid_length = 40
		else if(prob(20))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_03.ogg' = 1)
			soundloop.mid_length = 10
		else
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_04.ogg' = 1)
			soundloop.mid_length = 30
	update_power()

/obj/machinery/pda_multicaster/prebuilt/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/pda_multicaster/Destroy()
	// Snapshot: qdel pulls members out of contents mid-iteration.
	for(var/atom/movable/AM in contents.Copy())
		qdel(AM)
	QDEL_NULL(soundloop)
	. = ..()

/obj/machinery/pda_multicaster/update_icon()
	if(on)
		icon_state = initial(icon_state)
	else
		icon_state = "[initial(icon_state)]_off"

/obj/machinery/pda_multicaster/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/pda_multicaster_toggle,
	)
	..()

/// Old attack_hand (never called ..()): toggle the multicaster.
/datum/interaction/machine_hand/ungated/pda_multicaster_toggle
	id = "pda_multicaster_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/pda_multicaster/proc/interaction_toggle

/obj/machinery/pda_multicaster/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_power(user)
	return TRUE

/obj/machinery/pda_multicaster/proc/toggle_power(mob/user)
	toggle = !toggle
	visible_message("\the [user] turns \the [src] [toggle ? "on" : "off"].")
	update_power()
	if(!toggle)
		var/msg = "[user.client.key] ([user]) has turned [src] off, at [x],[y],[z]."
		message_admins(msg)
		log_game(msg)

/obj/machinery/pda_multicaster/proc/update_PDAs(turn_off)
	for(var/obj/item/pda/pda in contents)
		var/datum/data/pda/app/messenger/M = pda.find_program(/datum/data/pda/app/messenger/multicast)
		if(M)
			M.toff = turn_off

/obj/machinery/pda_multicaster/proc/update_power()
	if(toggle)
		if(stat & (BROKEN|NOPOWER|EMPED))
			on = 0
			update_PDAs(1) // 1 being to turn off.
			update_idle_power_usage(0)
			if(soundloop)
				soundloop.stop()
			noisy = FALSE
		else
			on = 1
			update_PDAs(0)
			update_idle_power_usage(750)
			if(soundloop)
				soundloop.start()
			noisy = TRUE
	else
		on = 0
		update_PDAs(1)
		update_idle_power_usage(0)
		if(soundloop)
			soundloop.stop()
		noisy = FALSE
	update_icon()

/obj/machinery/pda_multicaster/process()
	update_power()
	return PROCESS_KILL

/obj/machinery/pda_multicaster/power_change()
	. = ..()
	update_power()

/obj/machinery/pda_multicaster/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || (stat & EMPED))
		return
	stat |= EMPED
	update_power()
	var/duration = (300 * 10)/severity
	addtimer(CALLBACK(src, PROC_REF(emp_recover)), rand(duration - 20, duration + 20), TIMER_DELETE_ME)
	update_icon()
	..()

/obj/machinery/pda_multicaster/proc/emp_recover()
	stat &= ~EMPED
	update_power()
