/datum/computer_file/program/comm
	filename = "comm"
	filedesc = "Command and Communications Program"
	program_icon_state = "comm"
	program_key_state = "med_key"
	program_menu_icon = "flag"
	tguimodule_path =  /datum/tgui_module/communications/ntos
	extended_desc = "Used to command and control. Can relay long-range communications. This program can not be run on tablet computers."
	required_access = ACCESS_HEADS
	requires_ntnet = TRUE
	size = 12
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	network_destination = "long-range communication array"
	category = PROG_COMMAND
	var/datum/comm_message_listener/message_core

/datum/computer_file/program/comm/New(obj/item/modular_computer/comp = null)
	..()
	own_set(src, nameof(message_core), new /datum/comm_message_listener)


/datum/computer_file/program/comm/clone()
	var/datum/computer_file/program/comm/temp = ..()
	temp.message_core.messages = null
	temp.message_core.messages = message_core.messages.Copy()
	return temp

/*
General message handling stuff
*/

/proc/get_comm_message_id()
	GLOB.last_message_id = GLOB.last_message_id + 1
	return GLOB.last_message_id

/proc/post_comm_message(message_title, message_text)
	var/list/message = list()
	message["id"] = get_comm_message_id()
	message["title"] = message_title
	message["contents"] = message_text

	for(var/datum/comm_message_listener/l in REGISTRY_MEMBERS(REGISTRY_COMM_MESSAGE_LISTENERS))
		l.Add(message)

/datum/comm_message_listener
	var/list/messages

/datum/comm_message_listener/New()
	..()
	messages = list()
	join_registries()

REGISTRY_MEMBERSHIP(/datum/comm_message_listener, REGISTRY_COMM_MESSAGE_LISTENERS)

/datum/comm_message_listener/proc/Add(list/message)
	messages[++messages.len] = message

/datum/comm_message_listener/proc/Remove(list/message)
	messages -= list(message)
