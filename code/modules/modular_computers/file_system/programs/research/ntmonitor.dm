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
	category = PROG_ADMIN

CAPABILITIES(/datum/computer_file/program/ntnetmonitor)
	interface("NtosNetMonitor")
	op("resetIDS", ui_act("resetIDS"), then(PROC_REF(ui_act_resetids)))
	op("toggleIDS", ui_act("toggleIDS"), then(PROC_REF(ui_act_toggleids)))
	op("toggleWireless", ui_act("toggleWireless"), asks(/datum/prompt/yes_no, fields = list("title" = "NTNet shutdown", "question" = "Really disable NTNet wireless? If your computer is connected wirelessly you won't be able to turn it back on! This will affect all connected wireless devices."), when = PROC_REF(wireless_enabled)), then(PROC_REF(ui_act_togglewireless)))
	op("purgelogs", ui_act("purgelogs"), then(PROC_REF(ui_act_purgelogs)))
	op("updatemaxlogs", ui_act("updatemaxlogs", arg("new_number", num())), then(PROC_REF(ui_act_updatemaxlogs)))
	op("toggle_function", ui_act("toggle_function", arg("id", num())), then(PROC_REF(ui_act_toggle_function)))
	op("ban_nid", ui_act("ban_nid"), needs(req(PROC_REF(ntnet_present))), asks(/datum/prompt/number, fields = list("title" = "Enter NID", "question" = "Enter NID of device which you want to block from the network:")), then(PROC_REF(ui_act_ban_nid)))
	op("unban_nid", ui_act("unban_nid"), needs(req(PROC_REF(ntnet_present))), asks(/datum/prompt/number, fields = list("title" = "Enter NID", "question" = "Enter NID of device which you want to unblock from the network:")), then(PROC_REF(ui_act_unban_nid)))

/datum/computer_file/program/ntnetmonitor/ui_data(datum/act/eval/A)
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

/datum/computer_file/program/ntnetmonitor/proc/ui_act_resetids(datum/act/op/A)
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.resetIDS()
	return OP_OK

/datum/computer_file/program/ntnetmonitor/proc/ui_act_toggleids(datum/act/op/A)
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.toggleIDS()
	return OP_OK

/// Disabling the network is confirmed; enabling it is not.
/datum/computer_file/program/ntnetmonitor/proc/wireless_enabled(datum/act/op/A)
	return GLOB.ntnet_global && !GLOB.ntnet_global.setting_disabled

/datum/computer_file/program/ntnetmonitor/proc/ui_act_togglewireless(datum/act/op/A)
	if(!GLOB.ntnet_global)
		return

	// NTNet is disabled. Enabling can be done without user prompt
	if(GLOB.ntnet_global.setting_disabled)
		GLOB.ntnet_global.setting_disabled = FALSE
		return TRUE

	var/datum/prompt/P = A.answer
	if(P?.value)
		GLOB.ntnet_global.setting_disabled = TRUE
	return TRUE

/datum/computer_file/program/ntnetmonitor/proc/ui_act_purgelogs(datum/act/op/A)
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.purge_logs()
	return OP_OK

/datum/computer_file/program/ntnetmonitor/proc/ui_act_updatemaxlogs(datum/act/op/A, new_number)
	var/logcount = new_number
	if(GLOB.ntnet_global)
		GLOB.ntnet_global.update_max_log_count(logcount)
	return TRUE

/datum/computer_file/program/ntnetmonitor/proc/ui_act_toggle_function(datum/act/op/A, id)
	if(!GLOB.ntnet_global)
		return
	GLOB.ntnet_global.toggle_function(id)
	return TRUE

/datum/computer_file/program/ntnetmonitor/proc/ntnet_present(datum/act/op/A)
	return (!!GLOB.ntnet_global) ? null : /datum/msg/req_silent

/datum/computer_file/program/ntnetmonitor/proc/ui_act_ban_nid(datum/act/op/A)
	if(!GLOB.ntnet_global)
		return
	var/datum/prompt/P = A.answer
	var/nid = P?.value
	if(nid)
		LAZYOR(GLOB.ntnet_global.banned_nids, nid)
	return TRUE

/datum/computer_file/program/ntnetmonitor/proc/ui_act_unban_nid(datum/act/op/A)
	if(!GLOB.ntnet_global)
		return
	var/datum/prompt/P = A.answer
	var/nid = P?.value
	if(nid)
		LAZYREMOVE(GLOB.ntnet_global.banned_nids, nid)
	return TRUE
