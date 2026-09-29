/datum/computer_file/program/chatclient
	filename = "ntnrc_client"
	filedesc = "NTNet Relay Chat Client"
	program_icon_state = "command"
	program_key_state = "med_key"
	program_menu_icon = "comment"
	extended_desc = "This program allows communication over NTNRC network"
	size = 8
	requires_ntnet = 1
	requires_ntnet_feature = NTNET_COMMUNICATION
	network_destination = "NTNRC server"
	ui_header = "ntnrc_idle.gif"
	available_on_ntnet = 1
	tgui_id = "NtosNetChat"
	/// Used to generate the toolbar icon
	var/last_message
	var/username
	var/active_channel
	var/list/channel_history
	/// Channel operator mode
	var/operator_mode = FALSE
	/// Administrator mode (invisible to other users + bypasses passwords)
	var/netadmin_mode = FALSE
	usage_flags = PROGRAM_ALL

/datum/computer_file/program/chatclient/New()
	username = "DefaultUser[rand(100, 999)]"

UI_ACT(/datum/computer_file/program/chatclient, "PRG_speak", ui_act_prg_speak, UI_ARG_TEXT("message"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_speak)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(!channel || isnull(active_channel))
		return
	var/message = reject_bad_text(params["message"])
	if(!message)
		return
	if(channel.password && !(src in channel.clients))
		if(channel.password == message)
			channel.add_client(src)
			return TRUE

	channel.add_message(message, username)
	return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_joinchannel", ui_act_prg_joinchannel, UI_ARG_NUM("id"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_joinchannel)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/new_target = params["id"]
	if(isnull(new_target) || new_target == active_channel)
		return

	if(netadmin_mode)
		active_channel = new_target // Bypasses normal leave/join and passwords. Technically makes the user invisible to others.
		return TRUE

	active_channel =  new_target
	channel = GLOB.ntnet_global.get_chat_channel_by_id(new_target)
	if(!(src in channel.clients) && !channel.password)
		channel.add_client(src)
	return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_leavechannel", ui_act_prg_leavechannel)
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_leavechannel)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(channel)
		channel.remove_client(src)
		active_channel = null
		return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_newchannel", ui_act_prg_newchannel, UI_ARG_TEXT("new_channel_name"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_newchannel)
	var/channel_title = reject_bad_text(params["new_channel_name"])
	if(!channel_title)
		return
	var/datum/ntnet_conversation/C = new /datum/ntnet_conversation()
	C.add_client(src)
	rel_set(C, "operator", src)
	C.title = channel_title
	active_channel = C.id
	return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_toggleadmin", ui_act_prg_toggleadmin)
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_toggleadmin)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(netadmin_mode)
		netadmin_mode = FALSE
		if(channel)
			channel.remove_client(src) // We shouldn't be in channel's user list, but just in case...
		return TRUE
	if(isliving(ui.user) && can_run(ui.user, TRUE, ACCESS_NETWORK))
		for(var/datum/ntnet_conversation/chan as anything in GLOB.ntnet_global.chat_channels)
			chan.remove_client(src)
		netadmin_mode = TRUE
		return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_changename", ui_act_prg_changename, UI_ARG_TEXT("new_name"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_changename)
	var/newname = sanitize(params["new_name"])
	if(!newname)
		return
	for(var/datum/ntnet_conversation/chan as anything in GLOB.ntnet_global.chat_channels)
		if(src in chan.clients)
			chan.add_status_message("[username] is now known as [newname].")
	username = newname
	return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_savelog", ui_act_prg_savelog, UI_ARG_TEXT("log_name"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_savelog)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(!channel)
		return
	var/logname = sanitize(params["log_name"])
	if(!logname)
		return
	var/datum/computer_file/data/logfile = new /datum/computer_file/data/logfile()
	// Now we will generate HTML-compliant file that can actually be viewed/printed.
	logfile.filename = logname
	logfile.stored_data = "\[b\]Logfile dump from NTNRC channel [channel.title]\[/b\]\[BR\]"
	for(var/logstring in channel.messages)
		logfile.stored_data = "[logfile.stored_data][logstring]\[BR\]"
	logfile.stored_data = "[logfile.stored_data]\[b\]Logfile dump completed.\[/b\]"
	logfile.calculate_size()
	if(!computer() || !computer().hard_drive || !computer().hard_drive.store_file(logfile))
		if(!computer())
			// This program shouldn't even be runnable without computer.
			CRASH("Var computer is null!")
		if(!computer().hard_drive)
			computer().visible_message(span_warning("\The [computer()] shows an \"I/O Error - Hard drive connection error\" warning."))
		else	// In 99.9% cases this will mean our HDD is full
			computer().visible_message(span_warning("\The [computer()] shows an \"I/O Error - Hard drive may be full. Please free some space and try again. Required space: [logfile.size]GQ\" warning."))
	return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_renamechannel", ui_act_prg_renamechannel, UI_ARG_TEXT("new_name"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_renamechannel)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/authed = FALSE
	if(channel && ((channel.channel_operator() == src) || netadmin_mode))
		authed = TRUE
	if(!authed)
		return
	var/newname = reject_bad_text(params["new_name"])
	if(!newname || !channel)
		return
	channel.add_status_message("Channel renamed from [channel.title] to [newname] by operator.")
	channel.title = newname
	return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_deletechannel", ui_act_prg_deletechannel)
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_deletechannel)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/authed = FALSE
	if(channel && ((channel.channel_operator() == src) || netadmin_mode))
		authed = TRUE
	if(authed)
		qdel(channel)
		active_channel = null
		return TRUE

UI_ACT(/datum/computer_file/program/chatclient, "PRG_setpassword", ui_act_prg_setpassword, UI_ARG_TEXT("new_password"))
UI_ACT_PROC(/datum/computer_file/program/chatclient, ui_act_prg_setpassword)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/authed = FALSE
	if(channel && ((channel.channel_operator() == src) || netadmin_mode))
		authed = TRUE
	if(!authed)
		return

	var/new_password = sanitize(params["new_password"])
	if(!authed)
		return

	channel.password = new_password
	return TRUE

/datum/computer_file/program/chatclient/process_tick()
	..()
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(program_state != PROGRAM_STATE_KILLED)
		ui_header = "ntnrc_idle.gif"
		if(channel)
			// Remember the last message. If there is no message in the channel remember null.
			last_message = length(channel.messages) ? channel.messages[channel.messages.len] : null
		else
			last_message = null
		return 1
	if(channel?.messages?.len)
		ui_header = last_message == channel.messages[channel.messages.len] ? "ntnrc_idle.gif" : "ntnrc_new.gif"
	else
		ui_header = "ntnrc_idle.gif"

/datum/computer_file/program/chatclient/kill_program(forced = FALSE)
	for(var/datum/ntnet_conversation/channel as anything in GLOB.ntnet_global.chat_channels)
		channel.remove_client(src)
	..()

/datum/computer_file/program/chatclient/tgui_static_data(mob/user)
	var/list/data = list()
	data["can_admin"] = can_run(user, FALSE, ACCESS_NETWORK)
	return data

UI_DATA_REPLACE(/datum/computer_file/program/chatclient, "active_channel", "username", "adminmode=netadmin_mode:num", "merge:ui_data_datum_computer_file_program_chatclient{all_channels:list,title:text,authed:bool,clients:list,messages:list,is_operator:bool}")

/// The computed part of /datum/computer_file/program/chatclient's window data (declared on its UI_DATA row).
/datum/computer_file/program/chatclient/proc/ui_data_datum_computer_file_program_chatclient(mob/user, datum/tgui/ui, datum/tgui_state/state)
	if(!GLOB.ntnet_global) // chat_channels is lazy; no channels still shows the client
		return list()

	var/list/data = get_header_data()

	var/list/all_channels = list()
	for(var/datum/ntnet_conversation/conv as anything in GLOB.ntnet_global.chat_channels)
		if(conv && conv.title)
			all_channels.Add(list(list(
				"chan" = conv.title,
				"id" = conv.id
			)))
	data["all_channels"] = all_channels

	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(channel)
		data["title"] = channel.title
		var/authed = FALSE
		if(!channel.password)
			authed = TRUE
		if(netadmin_mode)
			authed = TRUE
		var/list/clients = list()
		for(var/C in channel.clients)
			if(C == src)
				authed = TRUE
			var/datum/computer_file/program/chatclient/cl = C
			clients.Add(list(list(
				"name" = cl.username
			)))
		data["authed"] = authed
		//no fishing for ui data allowed
		if(authed)
			data["clients"] = clients
			var/list/messages = list()
			for(var/M in channel.messages)
				messages.Add(list(list(
					"msg" = M
				)))
			data["messages"] = messages
			data["is_operator"] = (channel.channel_operator() == src) || netadmin_mode
		else
			data["clients"] = list()
			data["messages"] = list()
	else
		data["clients"] = list()
		data["authed"] = FALSE
		data["messages"] = list()

	return data
