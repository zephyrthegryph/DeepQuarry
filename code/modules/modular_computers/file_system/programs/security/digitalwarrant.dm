GLOBAL_VAR_INIT(warrant_uid, 0)

/datum/datacore
	var/list/warrants

/datum/data/record/warrant
	var/warrant_id

/datum/data/record/warrant/New()
	..()
	warrant_id = GLOB.warrant_uid++

/datum/computer_file/program/digitalwarrant
	filename = "digitalwarrant"
	filedesc = "Warrant Assistant"
	extended_desc = "Official NTsec program for creation and handling of warrants."
	size = 8
	program_icon_state = "warrant"
	program_key_state = "security_key"
	program_menu_icon = "star"
	requires_ntnet = TRUE
	available_on_ntnet = TRUE
	required_access = ACCESS_SECURITY
	usage_flags = PROGRAM_ALL
	tgui_id = "NtosDigitalWarrant"
	category = PROG_SEC

	var/tmp/datum/data/record/warrant/activewarrant_ref

/datum/computer_file/program/digitalwarrant/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = get_header_data()

	data["warrantname"] = null
	data["warrantcharges"] = null
	data["warrantauth"] = null
	data["type"] = null

	if(activewarrant())
		data["warrantname"] = activewarrant().fields["namewarrant"]
		data["warrantcharges"] = activewarrant().fields["charges"]
		data["warrantauth"] = activewarrant().fields["auth"]
		data["type"] = activewarrant().fields["arrestsearch"]

	var/list/allwarrants = list()
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		allwarrants.Add(list(list(
			"warrantname" = W.fields["namewarrant"],
			"charges" = "[copytext(W.fields["charges"],1,min(length(W.fields["charges"]) + 1, 50))]...",
			"auth" = W.fields["auth"],
			"id" = W.warrant_id,
			"arrestsearch" = W.fields["arrestsearch"]
		)))
	data["allwarrants"] = allwarrants

	return data

/datum/computer_file/program/digitalwarrant/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("back")
			. = TRUE
			activewarrant_ref = null

		if("editwarrant")
			. = TRUE
			for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
				if(W.warrant_id == text2num(params["id"]))
					activewarrant_ref = W
					break

	// The following actions will only be possible if the user has an ID with security access equipped. This is in line with modular computer framework's authentication methods,
	// which also use RFID scanning to allow or disallow access to some functions. Anyone can view warrants, editing requires ID. This also prevents situations where you show a tablet
	// to someone who is to be arrested, which allows them to change the stuff there.
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return

	switch(action)
		if("addwarrant")
			. = TRUE
			var/datum/data/record/warrant/W = new()
			var/temp = act_prompt(ui.user, action, params, ui, "k85", list("message" = "Do you want to create a search-, or an arrest warrant?", "title" = "Warrant Type", "choices" = list("Search","Arrest","Cancel")))
			if(isnull(temp))
				return
			if(!temp)
				return
			if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				if(temp == "Arrest")
					W.fields["namewarrant"] = "Unknown"
					W.fields["charges"] = "No charges present"
					W.fields["auth"] = "Unauthorized"
					W.fields["arrestsearch"] = "arrest"
				if(temp == "Search")
					W.fields["namewarrant"] = "No suspect/location given"
					W.fields["charges"] = "No reason given"
					W.fields["auth"] = "Unauthorized"
					W.fields["arrestsearch"] = "search"
				activewarrant_ref = W

		if("savewarrant")
			. = TRUE
			LAZYOR(GLOB.data_core.warrants, activewarrant())
			activewarrant_ref = null

		if("deletewarrant")
			. = TRUE
			LAZYREMOVE(GLOB.data_core.warrants, activewarrant())
			activewarrant_ref = null

		if("editwarrantname")
			. = TRUE
			var/namelist = list()
			for(var/datum/data/record/t in GLOB.data_core.general)
				namelist += t.fields["name"]
			var/new_name = act_prompt(ui.user, action, params, ui, "k116", list("kind" = "list", "message" = "Please input name:", "title" = "Name Choice", "choices" = namelist))
			if(isnull(new_name))
				return
			if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				if (!new_name)
					return
				activewarrant().fields["namewarrant"] = new_name

		if("editwarrantnamecustom")
			. = TRUE
			var/new_name = act_prompt(ui.user, action, params, ui, "k124", list("kind" = "text", "message" = "Please input name", "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_name))
				return
			if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				if (!new_name)
					return
				activewarrant().fields["namewarrant"] = new_name

		if("editwarrantcharges")
			. = TRUE
			if(!activewarrant())
				return
			var/new_charges = act_prompt(ui.user, action, params, ui, "k134", list("kind" = "text", "message" = "Please input charges", "title" = "Charges", "default" = activewarrant().fields["charges"], "max_length" = MAX_MESSAGE_LEN))
			if(isnull(new_charges))
				return
			if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
				if (!new_charges || !activewarrant())
					return
				activewarrant().fields["charges"] = new_charges

		if("editwarrantauth")
			. = TRUE
			if(!activewarrant())
				return
			if(!(ACCESS_HOS in I.GetAccess())) // begin
				to_chat(ui.user, span_warning("You don't have the access to do this!"))
				return // end
			activewarrant().fields["auth"] = "[I.registered_name] - [I.assignment ? I.assignment : "(Unknown)"]"

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/computer_file/program/digitalwarrant/proc/activewarrant() as /datum/data/record/warrant
	return activewarrant_ref
