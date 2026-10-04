/datum/computer_file/program/ntnetmonitor
	filename = "ntmonitor"
	filedesc = "NTNet Diagnostics and Monitoring"
	program_icon_state = "comm_monitor"
	program_key_state = "generic_key"
	program_menu_icon = "wrench"
	extended_desc = "This program monitors the local NTNet network, provides access to logging systems, and allows for configuration changes"
	size = 12
	requires_ntnet = TRUE
	required_access = ACCESS_NETWORK
	available_on_ntnet = TRUE
	tgui_id = "NtosNetMonitor"
	category = PROG_ADMIN

UI_DATA_REPLACE(/datum/computer_file/program/ntnetmonitor, "merge:ui_data_datum_computer_file_program_ntnetmonitor{ntnetstatus:unknown,ntnetrelays:num,idsstatus:num,idsalarm:num,config_softwaredownload:num,config_peertopeer:num,config_communication:num,config_systemcontrol:num,ntnetlogs:list,minlogs:num,maxlogs:num,banned_nids:bool,ntnetmaxlogs:num}")

/// The computed part of /datum/computer_file/program/ntnetmonitor's window data (declared on its UI_DATA row).
/datum/computer_file/program/ntnetmonitor/proc/ui_data_datum_computer_file_program_ntnetmonitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	if(!GLOB.ntnet_global)
		return
	var/list/data = get_header_data()

	data["ntnetstatus"] = GLOB.ntnet_global.check_function()
	data["ntnetrelays"] = length(GLOB.ntnet_global.relays)
	data["idsstatus"] = GLOB.ntnet_global.intrusion_detection_enabled
	data["idsalarm"] = GLOB.ntnet_global.intrusion_detection_alarm

	data["config_softwaredownload"] = GLOB.ntnet_global.setting_softwaredownload
	data["config_peertopeer"] = GLOB.ntnet_global.setting_peertopeer
	data["config_communication"] = GLOB.ntnet_global.setting_communication
	data["config_systemcontrol"] = GLOB.ntnet_global.setting_systemcontrol

	data["ntnetlogs"] = list()
	data["minlogs"] = MIN_NTNET_LOGS
	data["maxlogs"] = MAX_NTNET_LOGS

	data["banned_nids"] = list(GLOB.ntnet_global.banned_nids || list())

	for(var/i in GLOB.ntnet_global.logs)
		data["ntnetlogs"] += list(list("entry" = i))
	data["ntnetmaxlogs"] = GLOB.ntnet_global.setting_maxlogcount

	return data

CAPABILITIES(/datum/computer_file/program/ntnetmonitor)
	op("resetIDS", ui_act(), then(PROC_REF(native_ui_act_resetids)))
	op("toggleIDS", ui_act(), then(PROC_REF(native_ui_act_toggleids)))
	op("purgelogs", ui_act(), then(PROC_REF(native_ui_act_purgelogs)))

/datum/computer_file/program/ntnetmonitor/proc/native_ui_act_resetids(datum/act/op/A)
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.resetIDS()
	return OP_OK

/datum/computer_file/program/ntnetmonitor/proc/native_ui_act_toggleids(datum/act/op/A)
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.toggleIDS()
	return OP_OK

UI_ACT(/datum/computer_file/program/ntnetmonitor, "toggleWireless", ui_act_togglewireless)
UI_ACT_PROC(/datum/computer_file/program/ntnetmonitor, ui_act_togglewireless)
	if(!GLOB.ntnet_global)
		return

	// NTNet is disabled. Enabling can be done without user prompt
	if(GLOB.ntnet_global.setting_disabled)
		GLOB.ntnet_global.setting_disabled = FALSE
		return TRUE

	var/response = act_ask(ui.user, action, params, ui, "k63", /datum/om/prompt/choice/alert, message = "Really disable NTNet wireless? If your computer is connected wirelessly you won't be able to turn it back on! This will affect all connected wireless devices.", title = "NTNet shutdown", choices = list("Yes", "No"))
	if(isnull(response))
		return
	if(response == "Yes" && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		GLOB.ntnet_global.setting_disabled = TRUE
	return TRUE

/datum/computer_file/program/ntnetmonitor/proc/native_ui_act_purgelogs(datum/act/op/A)
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.purge_logs()
	return OP_OK

UI_ACT(/datum/computer_file/program/ntnetmonitor, "updatemaxlogs", ui_act_updatemaxlogs, UI_ARG_NUM("new_number"))
UI_ACT_PROC(/datum/computer_file/program/ntnetmonitor, ui_act_updatemaxlogs)
	var/logcount = params["new_number"]
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.update_max_log_count(logcount)
	return TRUE

UI_ACT(/datum/computer_file/program/ntnetmonitor, "toggle_function", ui_act_toggle_function, UI_ARG_NUM("id"))
UI_ACT_PROC(/datum/computer_file/program/ntnetmonitor, ui_act_toggle_function)
	if(!GLOB.ntnet_global)
		return
	GLOB.ntnet_global.toggle_function(params["id"])
	return TRUE

UI_ACT(/datum/computer_file/program/ntnetmonitor, "ban_nid", ui_act_ban_nid)
UI_ACT_PROC(/datum/computer_file/program/ntnetmonitor, ui_act_ban_nid)
	if(!GLOB.ntnet_global)
		return
	var/nid = act_ask(ui.user, action, params, ui, "k84", /datum/om/prompt/number, message = "Enter NID of device which you want to block from the network:", title = "Enter NID")
	if(isnull(nid))
		return
	if(nid && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		LAZYOR(GLOB.ntnet_global.banned_nids, nid)
	return TRUE

UI_ACT(/datum/computer_file/program/ntnetmonitor, "unban_nid", ui_act_unban_nid)
UI_ACT_PROC(/datum/computer_file/program/ntnetmonitor, ui_act_unban_nid)
	if(!GLOB.ntnet_global)
		return
	var/nid = act_ask(ui.user, action, params, ui, "k91", /datum/om/prompt/number, message = "Enter NID of device which you want to unblock from the network:", title = "Enter NID")
	if(isnull(nid))
		return
	if(nid && tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		LAZYREMOVE(GLOB.ntnet_global.banned_nids, nid)
	return TRUE
