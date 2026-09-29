/datum/computer_file/program/ntnetdownload
	filename = "ntndownloader"
	filedesc = "NTNet Software Download Tool"
	program_icon_state = "generic"
	program_key_state = "generic_key"
	program_menu_icon = "arrowthickstop-1-s"
	extended_desc = "This program allows downloads of software from official NT repositories"
	unsendable = TRUE
	undeletable = TRUE
	size = 4
	requires_ntnet = TRUE
	requires_ntnet_feature = NTNET_SOFTWAREDOWNLOAD
	available_on_ntnet = FALSE
	ui_header = "downloader_finished.gif"
	tgui_id = "NtosNetDownloader"

	var/datum/computer_file/program/downloaded_file = null
	var/hacked_download = 0
	///GQ of downloaded data.
	var/download_completion = 0
	var/download_netspeed = 0
	var/downloaderror = ""
	var/list/downloads_queue

	var/file_info
	var/server
	usage_flags = PROGRAM_ALL
	category = PROG_UTIL

	var/tmp/obj/item/modular_computer/my_computer

/datum/computer_file/program/ntnetdownload/kill_program()
	..()
	abort_file_download()

/datum/computer_file/program/ntnetdownload/proc/begin_file_download(filename)
	if(downloaded_file)
		return 0

	var/datum/computer_file/program/PRG = GLOB.ntnet_global.find_ntnet_file_by_name(filename)

	if(!check_file_download(filename))
		return 0

	ui_header = "downloader_running.gif"

	if(PRG in GLOB.ntnet_global.available_station_software)
		generate_network_log("Began downloading file [PRG.filename].[PRG.filetype] from NTNet Software Repository.")
		hacked_download = 0
	else if(PRG in GLOB.ntnet_global.available_antag_software)
		generate_network_log("Began downloading file **ENCRYPTED**.[PRG.filetype] from unspecified server.")
		hacked_download = 1
	else
		generate_network_log("Began downloading file [PRG.filename].[PRG.filetype] from unspecified server.")
		hacked_download = 0

	own_set(src, nameof(downloaded_file), PRG.clone())

/datum/computer_file/program/ntnetdownload/proc/check_file_download(filename)
	//returns 1 if file can be downloaded, returns 0 if download prohibited
	var/datum/computer_file/program/PRG = GLOB.ntnet_global.find_ntnet_file_by_name(filename)

	if(!PRG || !istype(PRG))
		return 0

	// Attempting to download antag only program, but without having emagged computer. No.
	if(PRG.available_on_syndinet && !computer_emagged)
		return 0

	if(!computer() || !computer().hard_drive || !computer().hard_drive.try_store_file(PRG))
		return 0

	return 1

/datum/computer_file/program/ntnetdownload/proc/abort_file_download()
	if(!downloaded_file)
		return
	generate_network_log("Aborted download of file [hacked_download ? "**ENCRYPTED**" : downloaded_file.filename].[downloaded_file.filetype].")
	own_clear(src, nameof(downloaded_file), OWN_DELETE) // null already when store_file() took it
	download_completion = 0
	ui_header = "downloader_finished.gif"

/datum/computer_file/program/ntnetdownload/proc/complete_file_download()
	if(!downloaded_file)
		return
	generate_network_log("Completed download of file [hacked_download ? "**ENCRYPTED**" : downloaded_file.filename].[downloaded_file.filetype].")
	if(!computer() || !computer().hard_drive || !computer().hard_drive.store_file(downloaded_file))
		// The download failed
		downloaderror = "I/O ERROR - Unable to save file. Check whether you have enough free space on your hard drive and whether your hard drive is properly connected. If the issue persists contact your system administrator for assistance."
	own_clear(src, nameof(downloaded_file), OWN_DELETE) // null already when store_file() took it
	download_completion = 0
	ui_header = "downloader_finished.gif"

/datum/computer_file/program/ntnetdownload/process_tick()
	if(!downloaded_file)
		return
	if(download_completion >= downloaded_file.size)
		complete_file_download()
		if(length(downloads_queue) > 0)
			begin_file_download(LAZYACCESS(downloads_queue, 1))
			LAZYREMOVE(downloads_queue, LAZYACCESS(downloads_queue, 1))

	// Download speed according to connectivity state. NTNet server is assumed to be on unlimited speed so we're limited by our local connectivity
	download_netspeed = 0
	// Speed defines are found in misc.dm
	switch(ntnet_status)
		if(1)
			download_netspeed = NTNETSPEED_LOWSIGNAL
		if(2)
			download_netspeed = NTNETSPEED_HIGHSIGNAL
		if(3)
			download_netspeed = NTNETSPEED_ETHERNET
	download_completion += download_netspeed

UI_ACT(/datum/computer_file/program/ntnetdownload, "PRG_downloadfile", ui_act_prg_downloadfile, UI_ARG_TEXT("filename"))
UI_ACT_PROC(/datum/computer_file/program/ntnetdownload, ui_act_prg_downloadfile)
	if(!downloaded_file)
		begin_file_download(params["filename"])
	else if(check_file_download(params["filename"]) && !LAZYFIND(downloads_queue, params["filename"]) && downloaded_file.filename != params["filename"])
		LAZYADD(downloads_queue, params["filename"])
	return TRUE

UI_ACT(/datum/computer_file/program/ntnetdownload, "PRG_removequeued", ui_act_prg_removequeued, UI_ARG_TEXT("filename"))
UI_ACT_PROC(/datum/computer_file/program/ntnetdownload, ui_act_prg_removequeued)
	LAZYREMOVE(downloads_queue, params["filename"])
	return TRUE

UI_ACT(/datum/computer_file/program/ntnetdownload, "PRG_reseterror", ui_act_prg_reseterror)
UI_ACT_PROC(/datum/computer_file/program/ntnetdownload, ui_act_prg_reseterror)
	if(downloaderror)
		download_completion = 0
		download_netspeed = 0
		own_clear(src, nameof(/datum/computer_file/program/ntnetdownload::downloaded_file), OWN_DELETE) // null already when store_file() took it
		downloaderror = ""
	return TRUE

UI_DATA_REPLACE(/datum/computer_file/program/ntnetdownload, "merge:ui_data_datum_computer_file_program_ntnetdownload{downloading:bool,error:bool,downloadname:text,downloaddesc:text,downloadsize:num,downloadspeed:num,downloadcompletion:num,disk_size:num,disk_used:num,hackedavailable:bool,hacked_programs:list,downloadable_programs:list,downloads_queue:bool}")

/// The computed part of /datum/computer_file/program/ntnetdownload's window data (declared on its UI_DATA row).
/datum/computer_file/program/ntnetdownload/proc/ui_data_datum_computer_file_program_ntnetdownload(mob/user, datum/tgui/ui, datum/tgui_state/state)
	rel_set(src, nameof(my_computer), computer())
	if(!istype(my_computer(), /obj/item/modular_computer))
		return

	var/list/data = get_header_data()

	data["downloading"] = !!downloaded_file
	data["error"] = downloaderror || FALSE

	if(downloaded_file) // Download running. Wait please..
		data["downloadname"] = downloaded_file.filename
		data["downloaddesc"] = downloaded_file.filedesc
		data["downloadsize"] = downloaded_file.size
		data["downloadspeed"] = download_netspeed
		data["downloadcompletion"] = round(download_completion, 0.1)

	data["disk_size"] = my_computer().hard_drive.max_capacity
	data["disk_used"] = my_computer().hard_drive.used_capacity
	var/list/all_entries = list()
	for(var/datum/computer_file/program/P in GLOB.ntnet_global.available_station_software)
		// Only those programs our user can run will show in the list.
		// Pass the card inserted in the laptop's slot so slotted IDs are respected.
		if(!P.can_run(user, 0, null, my_computer().card_slot?.stored_card()) && P.requires_access_to_download || my_computer().hard_drive.find_file_by_name(P.filename))
			continue
		all_entries.Add(list(list(
			"filename" = P.filename,
			"filedesc" = P.filedesc,
			"fileinfo" = P.extended_desc,
			"compatibility" = check_compatibility(P),
			"size" = P.size,
			"icon" = P.program_menu_icon
		)))
	data["hackedavailable"] = FALSE
	if(computer_emagged) // If we are running on emagged computer we have access to some "bonus" software
		var/list/hacked_programs = list()
		for(var/datum/computer_file/program/P in GLOB.ntnet_global.available_antag_software)
			if(my_computer().hard_drive.find_file_by_name(P.filename))
				continue
			data["hackedavailable"] = TRUE
			hacked_programs.Add(list(list(
				"filename" = P.filename,
				"filedesc" = P.filedesc,
				"fileinfo" = P.extended_desc,
				"compatibility" = check_compatibility(P),
				"size" = P.size,
				"icon" = P.program_menu_icon
			)))
		data["hacked_programs"] = hacked_programs

	data["downloadable_programs"] = all_entries
	data["downloads_queue"] = (downloads_queue || list())

	return data

/datum/computer_file/program/ntnetdownload/proc/check_compatibility(datum/computer_file/program/P)
	var/hardflag = computer().hardware_flag

	if(P && P.is_supported_by_hardware(hardflag,0))
		return "Compatible"
	return "Incompatible!"


/// The my_computer this refers to (a relation view: null once that is deleted).
/datum/computer_file/program/ntnetdownload/proc/my_computer() as /obj/item/modular_computer
	return my_computer
