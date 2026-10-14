GLOBAL_VAR_INIT(nttransfer_uid, 0)

/datum/computer_file/program/nttransfer
	filename = "nttransfer"
	filedesc = "NTNet P2P Transfer Client"
	extended_desc = "This program allows for simple file transfer via direct peer to peer connection."
	program_icon_state = "comm_logs"
	program_key_state = "generic_key"
	program_menu_icon = "transferthick-e-w"
	size = 7
	requires_ntnet = TRUE
	requires_ntnet_feature = NTNET_PEERTOPEER
	network_destination = "other device via P2P tunnel"
	available_on_ntnet = TRUE
	category = PROG_UTIL

	var/error = ""										// Error screen
	var/server_password = ""							// Optional password to download the file.
	var/tmp/datum/computer_file/provided_file	// File which is provided to clients.
	var/datum/computer_file/downloaded_file = null		// File which is being downloaded
	var/list/connected_clients					// List of connected clients.
	var/tmp/datum/computer_file/program/nttransfer/remote	// Client var, specifies who are we downloading from.
	var/download_completion = 0							// Download progress in GQ
	var/actual_netspeed = 0								// Displayed in the UI, this is the actual transfer speed.
	var/unique_token 									// UID of this program
	var/upload_menu = FALSE								// Whether we show the program list and upload menu

/datum/computer_file/program/nttransfer/New()
	unique_token = GLOB.nttransfer_uid
	GLOB.nttransfer_uid++
	..()

/datum/computer_file/program/nttransfer/process_tick()
	..()
	// Server mode
	if(provided_file())
		for(var/datum/computer_file/program/nttransfer/C in connected_clients)
			// Transfer speed is limited by device which uses slower connectivity.
			// We can have multiple clients downloading at same time, but let's assume we use some sort of multicast transfer
			// so they can all run on same speed.
			C.actual_netspeed = min(C.ntnet_speed, ntnet_speed)
			C.download_completion += C.actual_netspeed
			if(C.download_completion >= provided_file().size)
				C.finish_download()
	else if(downloaded_file) // Client mode
		if(!remote())
			crash_download("Connection to remote server lost")

/datum/computer_file/program/nttransfer/kill_program(forced = 0)
	if(downloaded_file) // Client mode, clean up variables for next use
		finalize_download()

	if(provided_file()) // Server mode, disconnect all clients
		for(var/datum/computer_file/program/nttransfer/P in connected_clients)
			P.crash_download("Connection terminated by remote server")
		own_clear(src, nameof(downloaded_file), OWN_DELETE)
		if(GLOB.ntnet_global)
			rel_remove(GLOB.ntnet_global, nameof(/datum/ntnet::fileservers), src)
	..(forced)

// Finishes download and attempts to store the file on HDD
/datum/computer_file/program/nttransfer/proc/finish_download()
	if(!computer() || !computer().hard_drive || !computer().hard_drive.store_file(downloaded_file))
		error = "I/O Error:  Unable to save file. Check your hard drive and try again."
	finalize_download()

//  Crashes the download and displays specific error message
/datum/computer_file/program/nttransfer/proc/crash_download(message)
	error = message ? message : "An unknown error has occurred during download"
	finalize_download()

// Cleans up variables for next use
/datum/computer_file/program/nttransfer/proc/finalize_download()
	if(remote())
		rel_remove(remote(), nameof(/datum/computer_file/data/email_account::connected_clients), src)
	own_clear(src, nameof(downloaded_file), OWN_DELETE) // null when finish_download() stored it
	rel_clear(src, nameof(remote))
	download_completion = 0

CAPABILITIES(/datum/computer_file/program/nttransfer)
	interface("NtosNetTransfer")
	op("PRG_downloadfile", ui_act("PRG_downloadfile", arg("uid", num())), then(PROC_REF(ui_act_prg_downloadfile)))
	op("PRG_reset", ui_act("PRG_reset"), then(PROC_REF(ui_act_prg_reset)))
	op("PRG_setpassword", ui_act("PRG_setpassword"), then(PROC_REF(ui_act_prg_setpassword)))
	op("PRG_uploadfile", ui_act("PRG_uploadfile", arg("uid", num())), then(PROC_REF(ui_act_prg_uploadfile)))
	op("PRG_uploadmenu", ui_act("PRG_uploadmenu"), then(PROC_REF(ui_act_prg_uploadmenu)))

/datum/computer_file/program/nttransfer/ui_data(datum/act/eval/A)
	var/list/data = get_header_data()
	data["error"] = error

	data["downloading"] = !!downloaded_file
	if(downloaded_file)
		data["download_size"] = downloaded_file.size
		data["download_progress"] = download_completion
		data["download_netspeed"] = actual_netspeed
		data["download_name"] = "[downloaded_file.filename].[downloaded_file.filetype]"

	data["uploading"] = !!provided_file()
	if(provided_file())
		data["upload_uid"] = unique_token
		data["upload_clients"] = length(connected_clients)
		data["upload_haspassword"] = server_password ? 1 : 0
		data["upload_filename"] = "[provided_file().filename].[provided_file().filetype]"

	data["upload_filelist"] = list()
	if(upload_menu)
		var/list/all_files = list()
		for(var/datum/computer_file/F in computer().hard_drive.stored_files)
			all_files.Add(list(list(
			"uid" = F.uid,
			"filename" = "[F.filename].[F.filetype]",
			"size" = F.size
			)))
		data["upload_filelist"] = all_files

	data["servers"] = list()
	if(!(downloaded_file || provided_file() || upload_menu))
		var/list/all_servers = list()
		for(var/datum/computer_file/program/nttransfer/P in GLOB.ntnet_global.fileservers)
			if(!P.provided_file())
				continue
			all_servers.Add(list(list(
				"uid" = P.unique_token,
				"filename" = "[P.provided_file().filename].[P.provided_file().filetype]",
				"size" = P.provided_file().size,
				"haspassword" = P.server_password ? 1 : 0
			)))
		data["servers"] = all_servers

	return data

/datum/computer_file/program/nttransfer/proc/ui_act_prg_downloadfile(datum/act/op/A, uid)
	var/mob/user = A.actor
	for(var/datum/computer_file/program/nttransfer/P in GLOB.ntnet_global.fileservers)
		if(P.unique_token == uid)
			rel_set(src, nameof(/datum/computer_file/program/nttransfer::remote), P)
			break
	if(!remote() || !remote().provided_file())
		return
	if(remote().server_password)
		open_request(src, /datum/prompt/text, PROC_REF(download_password_entered), valid = PROC_REF(request_usable), answerer = user, question = "Code 401 Unauthorized. Please enter password:", title = "Password required", timeout = 0)
		return
	start_download()
	return TRUE

/datum/computer_file/program/nttransfer/proc/download_password_entered(datum/act/request/A)
	download_password_entered_apply(A)
	SStgui.update_uis(src)

/datum/computer_file/program/nttransfer/proc/download_password_entered_apply(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value) || !remote() || !remote().provided_file())
		return
	if(A.answer.value != remote().server_password)
		error = "Incorrect Password"
		SStgui.update_uis(src)
		return
	start_download()

/datum/computer_file/program/nttransfer/proc/start_download()
	rel_set(src, nameof(src.downloaded_file), remote().provided_file().clone())
	rel_add(remote(), nameof(/datum/computer_file/data/email_account::connected_clients), src)

/datum/computer_file/program/nttransfer/proc/ui_act_prg_reset(datum/act/op/A)
	error = ""
	upload_menu = 0
	finalize_download()
	if(src in GLOB.ntnet_global.fileservers)
		rel_remove(GLOB.ntnet_global, nameof(/datum/ntnet::fileservers), src)
	for(var/datum/computer_file/program/nttransfer/T in connected_clients)
		T.crash_download("Remote server has forcibly closed the connection")
	rel_clear(src, nameof(/datum/computer_file/program/nttransfer::provided_file))
	return TRUE

/datum/computer_file/program/nttransfer/proc/ui_act_prg_setpassword(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(prg_setpassword_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Enter new server password. Leave blank to cancel, input 'none' to disable password.", title = "Server security", default = "none", timeout = 0)

/datum/computer_file/program/nttransfer/proc/prg_setpassword_answered(datum/act/request/A)
	prg_setpassword_answered_apply(A)
	SStgui.update_uis(src)

/datum/computer_file/program/nttransfer/proc/prg_setpassword_answered_apply(datum/act/request/A)
	if(!A.answer)
		return
	var/pass = A.answer.value
	if(!pass)
		return
	if(pass == "none")
		server_password = ""
		return
	server_password = pass
	return TRUE

/datum/computer_file/program/nttransfer/proc/ui_act_prg_uploadfile(datum/act/op/A, uid)
	for(var/datum/computer_file/F in computer().hard_drive.stored_files)
		if(F.uid == uid)
			if(F.unsendable)
				error = "I/O Error: File locked."
				return
			rel_set(src, nameof(/datum/computer_file/program/nttransfer::provided_file), F)
			rel_add(GLOB.ntnet_global, nameof(/datum/ntnet::fileservers), src)
			return
	error = "I/O Error: Unable to locate file on hard drive."
	return TRUE

/datum/computer_file/program/nttransfer/proc/ui_act_prg_uploadmenu(datum/act/op/A)
	upload_menu = 1
	return TRUE

/// File which is provided to clients. (a relation view: null once that is deleted).
/datum/computer_file/program/nttransfer/proc/provided_file() as /datum/computer_file
	return provided_file

/// Client var, specifies who are we downloading from. (a relation view: null once that is deleted).
/datum/computer_file/program/nttransfer/proc/remote() as /datum/computer_file/program/nttransfer
	return remote
