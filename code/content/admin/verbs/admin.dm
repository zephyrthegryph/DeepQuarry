/client/proc/admin_teleport()
	set name = "Admin teleport"
	set category = VERB_CAT_ADMIN_GAME
	set desc = "Teleports an atom to a set of coordinates or to the contents of another atom"
	ask_admin(/datum/ask_sequence/admin/teleport, null)

/// Admin teleport: the atom to move, then where: a set of coordinates or another atom.
/datum/ask_sequence/admin/teleport

/datum/ask_sequence/admin/teleport/initial_steps()
	return list(
		TYPE_PROC_REF(/client, teleport_ask_what),
		TYPE_PROC_REF(/client, teleport_read_what),
		question_step("how", /datum/prompt/choice, question = "Would you like to teleport to a set of a coordinates, or to an atom?", choices = list("coordinates","atom"), buttons = TRUE),
		TYPE_PROC_REF(/client, teleport_ask_where),
		TYPE_PROC_REF(/client, teleport_read_where),
		TYPE_PROC_REF(/client, teleport_do))

/client/proc/teleport_ask_what(datum/ask_sequence/admin/teleport/asked)
	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "what", list("class" = VV_ATOM_REFERENCE))

/client/proc/teleport_read_what(datum/ask_sequence/admin/teleport/asked)
	var/list/value = asked.get("what")
	if(!value["class"] || !value["value"])
		return ASK_STOP
	return null

/client/proc/teleport_ask_where(datum/ask_sequence/admin/teleport/asked)
	switch(asked.get("how"))
		if("coordinates")
			return question_step("coords", /datum/prompt/text, question = "Please input the coordinates, seperated by commas")
		if("atom")
			return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "where", list("class" = VV_ATOM_REFERENCE))
	return null

/client/proc/teleport_read_where(datum/ask_sequence/admin/teleport/asked)
	var/atom/destination
	switch(asked.get("how"))
		if("coordinates")
			var/coords_text = asked.get("coords")
			var/list/inputlist = text2numlist(sanitize(coords_text),",")
			var/list/coords = list()
			for(var/content in inputlist)
				if(content != null)
					coords += content
			if(coords.len>3)
				tgui_alert_async(src, "You entered too many coordinates! Only 3 are required.")
				return ASK_STOP
			if(coords.len<3)
				tgui_alert_async(src, "You didn't enter enough coordinates! 3 are required.")
				return ASK_STOP
			destination = locate(coords[1],coords[2],coords[3])
			if(!destination)
				tgui_alert_async(src, "Invalid coordinates!")
				return ASK_STOP
		if("atom")
			var/list/value = asked.get("where")
			if(!value["class"] || !value["value"])
				return ASK_STOP
			destination = value["value"]
	if(!destination)
		return ASK_STOP
	asked.put("destination", destination)
	return null

/client/proc/teleport_do(datum/ask_sequence/admin/teleport/asked)
	var/list/value = asked.get("what")
	var/atom/target = value["value"]
	var/atom/destination = asked.get("destination")
	if(!target || !destination)
		return null
	do_teleport(target, destination, channel = TELEPORT_CHANNEL_QUANTUM)
	return null
