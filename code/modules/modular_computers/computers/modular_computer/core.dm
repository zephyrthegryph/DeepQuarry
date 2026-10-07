// Delivers an event to every program currently running on this computer
// (both the active foreground program and all background idle threads) in a
// single atomic pass.  Callers never need to know the active/idle split.
//
// event_type: one of COMPUTER_EVENT_POWERFAILURE, COMPUTER_EVENT_NETWORKFAILURE,
//             COMPUTER_EVENT_IDREMOVED (defined in code/__defines/misc.dm).
// context:    optional extra datum passed through to the event handler; currently
//             unused but available for future expansion.
/obj/item/modular_computer/proc/broadcast_event(event_type, context = null)
	switch(event_type)
		if(COMPUTER_EVENT_POWERFAILURE)
			if(active_program())
				active_program().event_powerfailure(0)
			for(var/datum/computer_file/program/P in idle_threads)
				P.event_powerfailure(1)

		if(COMPUTER_EVENT_NETWORKFAILURE)
			if(active_program() && active_program().requires_ntnet && !get_ntnet_status(active_program().requires_ntnet_feature))
				active_program().event_networkfailure(0)
			for(var/datum/computer_file/program/P in idle_threads)
				if(P.requires_ntnet && !get_ntnet_status(P.requires_ntnet_feature))
					P.event_networkfailure(1)

		if(COMPUTER_EVENT_IDREMOVED)
			if(active_program())
				active_program().event_idremoved(0)
			for(var/datum/computer_file/program/P in idle_threads)
				P.event_idremoved(1)

/// Runs its programs while on; off, it sleeps until enable_computer().
/obj/item/modular_computer/proc/modular_computer_step(datum/act/timer/A)
	if(computer_broken())
		shutdown_computer()
		return 0

	// Dispatch network failure event through the unified broadcast proc.
	broadcast_event(COMPUTER_EVENT_NETWORKFAILURE)

	if(active_program())
		if(active_program().program_state != PROGRAM_STATE_KILLED)
			active_program().ntnet_status = get_ntnet_status()
			active_program().computer_emagged = computer_emagged
			active_program().process_tick()
		else
			rel_clear(src, nameof(active_program))

	for(var/datum/computer_file/program/P in idle_threads)
		if(P.program_state != PROGRAM_STATE_KILLED)
			P.ntnet_status = get_ntnet_status()
			P.computer_emagged = computer_emagged
			P.process_tick()
		else
			rel_remove(src, nameof(idle_threads), P)

	handle_power() // Handles all computer power interaction
	check_update_ui_need()

// Used to perform preset-specific hardware changes.
/obj/item/modular_computer/proc/install_default_hardware()
	return 1

// Used to install preset-specific programs
/obj/item/modular_computer/proc/install_default_programs()
	return 1


/obj/item/modular_computer/Initialize(mapload)
	if(!overlay_icon)
		overlay_icon = icon
	install_default_hardware()
	if(hard_drive)
		install_default_programs()
	update_icon()
	. = ..()

// its program is killed and hardware uninstalled.
/obj/item/modular_computer/on_destroy(force)
	kill_program(1)
	for(var/obj/item/computer_hardware/CH in src.get_all_components())
		uninstall_component(null, CH)
		ended_with(CH, src)
	rel_clear(src, nameof(paired_uavs))
	..()

/obj/item/modular_computer/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(computer_emagged)
		to_chat(user, "\The [src] was already emagged.")
		return OP_DECLINE
	else
		computer_emagged = 1
		to_chat(user, "You emag \the [src]. It's screen briefly shows a \"OVERRIDE ACCEPTED: New software downloads available.\" message.")
		return OP_OK

DECLARE_APPEARANCE_PROC(/obj/item/modular_computer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/modular_computer/appearance_overlays()
	. = list()
	icon_state = icon_state_unpowered


	. = list()

	if(bsod)
		. += mutable_appearance(overlay_icon, "bsod")
		. += emissive_appearance(overlay_icon, "bsod")
		return .
	if(!enabled)
		if(icon_state_screensaver)
			. += mutable_appearance(overlay_icon, icon_state_screensaver)
			. += emissive_appearance(overlay_icon, icon_state_screensaver)
		set_light(0)
		return .

	set_light(light_strength)

	if(active_program())
		var/program_state = active_program().program_icon_state ? active_program().program_icon_state : icon_state_menu
		. += mutable_appearance(overlay_icon, program_state)
		. += emissive_appearance(overlay_icon, program_state)
		if(active_program().program_key_state)
			. += mutable_appearance(overlay_icon, active_program().program_key_state)
	else
		. += mutable_appearance(overlay_icon, icon_state_menu)
		. += emissive_appearance(overlay_icon, icon_state_menu)

	return .

/obj/item/modular_computer/proc/turn_on(mob/user)
	if(bsod)
		return
	if(tesla_link)
		tesla_link.enabled = 1
	var/issynth = issilicon(user) // Robots and AIs get different activation messages.
	if(computer_broken())
		if(issynth)
			to_chat(user, "You send an activation signal to \the [src], but it responds with an error code. It must be damaged.")
		else
			to_chat(user, "You press the power button, but the computer fails to boot up, displaying variety of errors before shutting down again.")
		return
	if(processor_unit && (apc_power(0) || battery_power(0))) // Battery-run and charged or non-battery but powered by APC.
		if(issynth)
			to_chat(user, "You send an activation signal to \the [src], turning it on")
		else
			to_chat(user, "You press the power button and start up \the [src]")
		enable_computer(user)
		play_sfx(src, SFX_MACHINES_CONSOLE_POWER_ON, volume_channel = VOLUME_CHANNEL_MACHINERY)

	else // Unpowered
		if(issynth)
			to_chat(user, "You send an activation signal to \the [src] but it does not respond")
		else
			to_chat(user, "You press the power button but \the [src] does not respond")

// Relays kill program request to currently active program. Use this to quit current program.
/obj/item/modular_computer/proc/kill_program(forced = 0, mob/user)
	if(active_program())
		active_program().kill_program(forced)
		rel_clear(src, nameof(active_program))
	after(src, 0.1 SECONDS, PROC_REF(delayed_reopen_ui), with = list(user))
	update_icon()

/obj/item/modular_computer/proc/delayed_reopen_ui(mob/user)
	// Re-open the UI on this computer. It should show the main screen now.
	// Expected from kill_program()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!user || !istype(user))
		return
	tgui_interact(user)

// Returns 0 for No Signal, 1 for Low Signal and 2 for Good Signal. 3 is for wired connection (always-on)
/obj/item/modular_computer/proc/get_ntnet_status(specific_action = 0)
	if(network_card)
		return network_card.get_signal(specific_action)
	else
		return 0

/obj/item/modular_computer/proc/add_log(text)
	if(!get_ntnet_status())
		return 0
	return GLOB.ntnet_global.add_log(text, network_card)

/obj/item/modular_computer/proc/shutdown_computer(loud = 1)
	kill_program(1)
	for(var/datum/computer_file/program/P in idle_threads)
		P.kill_program(1)
		rel_remove(src, nameof(idle_threads), P)
	if(loud)
		visible_message("\The [src] shuts down.")
	set_enabled(FALSE)
	last_power_usage = 0
	update_icon()

/obj/item/modular_computer/proc/enable_computer(mob/user = null)
	set_enabled(TRUE)
	update_icon()

	// Autorun feature
	var/datum/computer_file/data/autorun = hard_drive ? hard_drive.find_file_by_name("autorun") : null
	if(istype(autorun))
		run_program(autorun.stored_data, user)

	if(user)
		tgui_interact(user)

/obj/item/modular_computer/proc/minimize_program(mob/user)
	if(!active_program() || !processor_unit)
		return

	rel_add(src, nameof(idle_threads), active_program())
	active_program().program_state = PROGRAM_STATE_BACKGROUND // Should close any existing UIs
	SStgui.close_uis(active_program().TM ? active_program().TM : active_program())
	rel_clear(src, nameof(active_program))
	update_icon()
	if(istype(user))
		tgui_interact(user) // Re-open the UI on this computer. It should show the main screen now.

/obj/item/modular_computer/proc/run_program(prog, mob/user)
	var/datum/computer_file/program/P = null
	if(hard_drive)
		P = hard_drive.find_file_by_name(prog)

	if(!P || !istype(P)) // Program not found or it's not executable program.
		to_chat(user, span_danger("\The [src]'s screen shows \"I/O ERROR - Unable to run [prog]\" warning."))
		return

	rel_set(P, nameof(P.computer), src)

	if(!P.is_supported_by_hardware(hardware_flag, 1, user))
		return
	if(P in idle_threads)
		P.program_state = PROGRAM_STATE_ACTIVE
		rel_set(src, nameof(active_program), P)
		rel_remove(src, nameof(idle_threads), P)
		update_icon()
		return

	if(length(idle_threads) >= processor_unit.max_idle_programs+1)
		to_chat(user, span_notice("\The [src] displays a \"Maximal CPU load reached. Unable to run another program.\" error"))
		return

	if(P.requires_ntnet && !get_ntnet_status(P.requires_ntnet_feature)) // The program requires NTNet connection, but we are not connected to NTNet.
		to_chat(user, span_danger("\The [src]'s screen shows \"NETWORK ERROR - Unable to connect to NTNet. Please retry. If problem persists contact your system administrator.\" warning."))
		return

	if(active_program())
		minimize_program(user)

	if(P.run_program(user))
		update_icon()
	return 1

/obj/item/modular_computer/proc/update_uis()
	if(active_program())
		SStgui.update_uis(active_program())
		if(active_program().TM)
			SStgui.update_uis(active_program().TM)
	else
		SStgui.update_uis(src)

/// TRUE if anyone is actually viewing this computer's tgui — the UI is hosted on
/// the active program (and its TM), or on the computer itself when idle.
/obj/item/modular_computer/proc/has_open_ui()
	if(active_program())
		if(LAZYLEN(active_program().open_tguis))
			return TRUE
		if(active_program().TM && LAZYLEN(active_program().TM.open_tguis))
			return TRUE
		return FALSE
	return LAZYLEN(open_tguis)

/obj/item/modular_computer/proc/check_update_ui_need()
	// Nobody's looking — don't build stationtime strings / header-icon lists every
	// 2s for a computer with no open tgui window. update_uis() is itself a no-op
	// without an open UI, so the only thing this proc accomplished for unviewed
	// computers was wasted allocation.
	if(!has_open_ui())
		return
	var/ui_update_needed = 0
	if(battery_module)
		var/batery_percent = battery_module.battery.percent()
		if(last_battery_percent != batery_percent) //Let's update UI on percent change
			ui_update_needed = 1
			last_battery_percent = batery_percent

	if(stationtime2text() != last_world_time)
		last_world_time = stationtime2text()
		ui_update_needed = 1

	if(length(idle_threads))
		var/list/current_header_icons = list()
		for(var/datum/computer_file/program/P in idle_threads)
			if(!P.ui_header)
				continue
			current_header_icons[P.type] = P.ui_header
		if(!last_header_icons)
			last_header_icons = current_header_icons

		else if(!listequal(last_header_icons, current_header_icons))
			last_header_icons = current_header_icons
			ui_update_needed = 1
		else
			for(var/x in last_header_icons|current_header_icons)
				if(last_header_icons[x]!=current_header_icons[x])
					last_header_icons = current_header_icons
					ui_update_needed = 1
					break

	if(ui_update_needed)
		update_uis()

// Used by camera monitor program
/obj/item/modular_computer/proc/set_autorun(program)
	if(!hard_drive)
		return
	var/datum/computer_file/data/autorun = hard_drive.find_file_by_name("autorun")
	if(!istype(autorun))
		autorun = new/datum/computer_file/data()
		autorun.filename = "autorun"
		hard_drive.store_file(autorun)
	if(autorun.stored_data == program)
		autorun.stored_data = null
	else
		autorun.stored_data = program

/obj/item/modular_computer/proc/find_file_by_uid(uid)
	if(hard_drive)
		. = hard_drive.find_file_by_uid(uid)
	if(portable_drive && !.)
		. = portable_drive.find_file_by_uid(uid)
