// Operates TGUI
/obj/item/modular_computer/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/headers)
	)

DECLARE_UI(/obj/item/modular_computer, "NtosMain", UI_AUTOUPDATE)

/obj/item/modular_computer/ui_prepare(mob/user, datum/tgui/ui)
	if(!screen_on || !enabled)
		return FALSE
	if(!apc_power(0) && !battery_power(0))
		return FALSE

	// If we have an active program switch to it now.
	if(active_program())
		active_program().tgui_interact(user)
		return FALSE

	// We are still here, that means there is no program loaded. Load the BIOS/ROM/OS/whatever you want to call it.
	// This screen simply lists available programs and user may select them.
	if(!hard_drive || !hard_drive.stored_files || !length(hard_drive.stored_files))
		visible_message("\The [src] beeps three times, it's screen displaying \"DISK ERROR\" warning.")
		return FALSE

	return TRUE

UI_DATA_REPLACE(/obj/item/modular_computer, "device_theme:text", "merge:ui_data_obj_item_modular_computer{login:list,removable_media:list,programs:list,has_light:bool,light_on:bool,comp_light_color:unknown}")

/// The computed part of /obj/item/modular_computer's window data (declared on its UI_DATA row).
/obj/item/modular_computer/proc/ui_data_obj_item_modular_computer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = get_header_data()

	data["login"] = list()
	var/obj/item/computer_hardware/card_slot/cardholder = card_slot
	if(cardholder)
		var/obj/item/card/id/stored_card = cardholder.stored_card()
		if(stored_card)
			var/stored_name = stored_card.registered_name
			var/stored_title = stored_card.assignment
			if(!stored_name)
				stored_name = "Unknown"
			if(!stored_title)
				stored_title = "Unknown"
			data["login"] = list(
				IDName = stored_name,
				IDJob = stored_title,
			)

	data["removable_media"] = list()

	var/datum/computer_file/data/autorun = hard_drive.find_file_by_name("autorun")
	data["programs"] = list()
	for(var/datum/computer_file/program/P in hard_drive.stored_files)
		var/running = FALSE
		if(P in idle_threads)
			running = TRUE

		data["programs"] += list(list(
			"name" = P.filename,
			"desc" = P.filedesc,
			"icon" = P.program_menu_icon,
			"running" = running,
			"autorun" = (istype(autorun) && (autorun.stored_data == P.filename)) ? 1 : 0
		))

	data["has_light"] = FALSE // has_light
	data["light_on"] = FALSE // light_on
	data["comp_light_color"] = null // comp_light_color

	return data

// Handles user's GUI input
UI_ACT(/obj/item/modular_computer, "PC_exit", ui_act_pc_exit)
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_exit)
	kill_program()
	return TRUE

UI_ACT(/obj/item/modular_computer, "PC_shutdown", ui_act_pc_shutdown)
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_shutdown)
	shutdown_computer()
	return TRUE

UI_ACT(/obj/item/modular_computer, "PC_minimize", ui_act_pc_minimize)
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_minimize)
	minimize_program(ui.user)

UI_ACT(/obj/item/modular_computer, "PC_killprogram", ui_act_pc_killprogram, UI_ARG_TEXT("name"))
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_killprogram)
	var/prog = params["name"]
	var/datum/computer_file/program/P = null
	if(hard_drive)
		P = hard_drive.find_file_by_name(prog)

	if(!istype(P) || P.program_state == PROGRAM_STATE_KILLED)
		return

	P.kill_program(1)
	to_chat(ui.user, span_notice("Program [P.filename].[P.filetype] with PID [rand(100,999)] has been killed."))
	return TRUE

UI_ACT(/obj/item/modular_computer, "PC_runprogram", ui_act_pc_runprogram, UI_ARG_TEXT("name"))
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_runprogram)
	return run_program(params["name"])

UI_ACT(/obj/item/modular_computer, "PC_setautorun", ui_act_pc_setautorun, UI_ARG_TEXT("name"))
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_setautorun)
	if(!hard_drive)
		return
	set_autorun(params["name"])
	return TRUE

UI_ACT(/obj/item/modular_computer, "PC_Eject_Disk", ui_act_pc_eject_disk, UI_ARG_TEXT("name"))
UI_ACT_PROC(/obj/item/modular_computer, ui_act_pc_eject_disk)
	var/param = params["name"]
	switch(param)
		if("ID")
			proc_eject_id(ui.user)
			return TRUE

// Function used by TGUI's to obtain data for header. All relevant entries begin with "PC_"
/obj/item/modular_computer/proc/get_header_data()
	var/list/data = list()

	if(battery_module)
		switch(battery_module.battery.percent())
			if(80 to 200) // 100 should be maximal but just in case..
				data["PC_batteryicon"] = "batt_100.gif"
			if(60 to 80)
				data["PC_batteryicon"] = "batt_80.gif"
			if(40 to 60)
				data["PC_batteryicon"] = "batt_60.gif"
			if(20 to 40)
				data["PC_batteryicon"] = "batt_40.gif"
			if(5 to 20)
				data["PC_batteryicon"] = "batt_20.gif"
			else
				data["PC_batteryicon"] = "batt_5.gif"
		data["PC_batterypercent"] = "[round(battery_module.battery.percent())] %"
		data["PC_showbatteryicon"] = 1
	else
		data["PC_batteryicon"] = "batt_5.gif"
		data["PC_batterypercent"] = "N/C"
		data["PC_showbatteryicon"] = battery_module ? 1 : 0

	if(tesla_link && tesla_link.enabled && apc_powered)
		data["PC_apclinkicon"] = "charging.gif"

	if(network_card && network_card.is_banned())
		data["PC_ntneticon"] = "sig_warning.gif"
	else
		switch(get_ntnet_status())
			if(0)
				data["PC_ntneticon"] = "sig_none.gif"
			if(1)
				data["PC_ntneticon"] = "sig_low.gif"
			if(2)
				data["PC_ntneticon"] = "sig_high.gif"
			if(3)
				data["PC_ntneticon"] = "sig_lan.gif"

	var/list/program_headers = list()
	for(var/datum/computer_file/program/P in idle_threads)
		if(!P.ui_header)
			continue
		program_headers.Add(list(list(
			"icon" = P.ui_header
		)))
	if(active_program() && active_program().ui_header)
		program_headers.Add(list(list(
			"icon" = active_program().ui_header
		)))
	data["PC_programheaders"] = program_headers

	data["PC_stationtime"] = stationtime2text()
	data["PC_hasheader"] = 1
	data["PC_showexitprogram"] = active_program() ? 1 : 0 // Hides "Exit Program" button on mainscreen
	return data
