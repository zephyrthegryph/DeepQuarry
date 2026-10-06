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

CAPABILITIES(/datum/computer_file/program/chatclient)
	interface("NtosNetChat")
	op("PRG_speak", ui_act("PRG_speak", arg("message", schema_text(4096))), then(PROC_REF(ui_act_prg_speak)))
	op("PRG_joinchannel", ui_act("PRG_joinchannel", arg("id", num())), then(PROC_REF(ui_act_prg_joinchannel)))
	op("PRG_leavechannel", ui_act("PRG_leavechannel"), then(PROC_REF(ui_act_prg_leavechannel)))
	op("PRG_newchannel", ui_act("PRG_newchannel", arg("new_channel_name", schema_text(4096))), then(PROC_REF(ui_act_prg_newchannel)))
	op("PRG_toggleadmin", ui_act("PRG_toggleadmin"), then(PROC_REF(ui_act_prg_toggleadmin)))
	op("PRG_changename", ui_act("PRG_changename", arg("new_name", schema_text(4096))), then(PROC_REF(ui_act_prg_changename)))
	op("PRG_savelog", ui_act("PRG_savelog", arg("log_name", schema_text(4096))), then(PROC_REF(ui_act_prg_savelog)))
	op("PRG_renamechannel", ui_act("PRG_renamechannel", arg("new_name", schema_text(4096))), then(PROC_REF(ui_act_prg_renamechannel)))
	op("PRG_deletechannel", ui_act("PRG_deletechannel"), then(PROC_REF(ui_act_prg_deletechannel)))
	op("PRG_setpassword", ui_act("PRG_setpassword", arg("new_password", schema_text(4096))), then(PROC_REF(ui_act_prg_setpassword)))

/datum/computer_file/program/chatclient/proc/ui_act_prg_speak(datum/act/op/A, message_arg)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(!channel || isnull(active_channel))
		return
	var/message = reject_bad_text(message_arg)
	if(!message)
		return
	if(channel.password && !(src in channel.clients))
		if(channel.password == message)
			channel.add_client(src)
			return TRUE

	channel.add_message(message, username)
	return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_joinchannel(datum/act/op/A, id)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/new_target = id
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

/datum/computer_file/program/chatclient/proc/ui_act_prg_leavechannel(datum/act/op/A)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(channel)
		channel.remove_client(src)
		active_channel = null
		return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_newchannel(datum/act/op/A, new_channel_name)
	var/channel_title = reject_bad_text(new_channel_name)
	if(!channel_title)
		return
	var/datum/ntnet_conversation/C = new /datum/ntnet_conversation()
	C.add_client(src)
	rel_set(C, nameof(/datum/ntnet_conversation/::operator), src)
	C.title = channel_title
	active_channel = C.id
	return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_toggleadmin(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(netadmin_mode)
		netadmin_mode = FALSE
		if(channel)
			channel.remove_client(src) // We shouldn't be in channel's user list, but just in case...
		return TRUE
	if(isliving(user) && can_run(user, TRUE, ACCESS_NETWORK))
		for(var/datum/ntnet_conversation/chan as anything in GLOB.ntnet_global.chat_channels)
			chan.remove_client(src)
		netadmin_mode = TRUE
		return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_changename(datum/act/op/A, new_name)
	var/newname = sanitize(new_name)
	if(!newname)
		return
	for(var/datum/ntnet_conversation/chan as anything in GLOB.ntnet_global.chat_channels)
		if(src in chan.clients)
			chan.add_status_message("[username] is now known as [newname].")
	username = newname
	return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_savelog(datum/act/op/A, log_name)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	if(!channel)
		return
	var/logname = sanitize(log_name)
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

/datum/computer_file/program/chatclient/proc/ui_act_prg_renamechannel(datum/act/op/A, new_name)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/authed = FALSE
	if(channel && ((channel.channel_operator() == src) || netadmin_mode))
		authed = TRUE
	if(!authed)
		return
	var/newname = reject_bad_text(new_name)
	if(!newname || !channel)
		return
	channel.add_status_message("Channel renamed from [channel.title] to [newname] by operator.")
	channel.title = newname
	return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_deletechannel(datum/act/op/A)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/authed = FALSE
	if(channel && ((channel.channel_operator() == src) || netadmin_mode))
		authed = TRUE
	if(authed)
		spent(channel)
		active_channel = null
		return TRUE

/datum/computer_file/program/chatclient/proc/ui_act_prg_setpassword(datum/act/op/A, new_password_arg)
	var/datum/ntnet_conversation/channel = GLOB.ntnet_global.get_chat_channel_by_id(active_channel)
	var/authed = FALSE
	if(channel && ((channel.channel_operator() == src) || netadmin_mode))
		authed = TRUE
	if(!authed)
		return

	var/new_password = sanitize(new_password_arg)
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

/datum/computer_file/program/chatclient/ui_data(datum/act/eval/A)
	if(!GLOB.ntnet_global) // chat_channels is lazy; no channels still shows the client
		return list()

	var/list/data = get_header_data()
	data["active_channel"] = active_channel
	data["username"] = username
	data["adminmode"] = netadmin_mode

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
