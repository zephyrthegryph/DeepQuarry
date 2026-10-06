/client/proc/admin_teleport()
	set name = "Admin teleport"
	set category = VERB_CAT_ADMIN_GAME
	set desc = "Teleports an atom to a set of coordinates or to the contents of another atom"
	if(!GLOB.prompt_flow) // its questions re-run it (prompt_flow(), prompt_helpers.dm)
		return prompt_flow(src, PROC_REF(admin_teleport), args)

	var/list/value = vv_get_value(VV_ATOM_REFERENCE, key = "teleport:what")
	if(!value["class"] || !value["value"])
		return
	var/atom/target = value["value"]
	var/atom/destination
	switch(flow_ask(mob, "teleport:how", /datum/prompt/choice, question = "Would you like to teleport to a set of a coordinates, or to an atom?", choices = list("coordinates","atom"), buttons = TRUE))
		if("coordinates")
			var/coords_text = flow_ask(mob, "teleport:coords", /datum/prompt/text, question = "Please input the coordinates, seperated by commas")
			if(isnull(coords_text))
				return
			var/list/inputlist = text2numlist(sanitize(coords_text),",")
			var/list/coords = list()
			for(var/content in inputlist)
				if(content != null)
					coords += content
			if(coords.len>3)
				tgui_alert_async(src, "You entered too many coordinates! Only 3 are required.")
				return
			if(coords.len<3)
				tgui_alert_async(src, "You didn't enter enough coordinates! 3 are required.")
				return
			destination = locate(coords[1],coords[2],coords[3])
			if(!destination)
				tgui_alert_async(src, "Invalid coordinates!")
				return
		if("atom")
			value = vv_get_value(VV_ATOM_REFERENCE, key = "teleport:where")
			if(!value["class"] || !value["value"])
				return
			destination = value["value"]
	if(!destination)
		return
	do_teleport(target, destination, channel = TELEPORT_CHANNEL_QUANTUM)
