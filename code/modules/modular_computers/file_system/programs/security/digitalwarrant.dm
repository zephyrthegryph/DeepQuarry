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

UI_ACT(/datum/computer_file/program/digitalwarrant, "back", ui_act_back)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_back)
	. = TRUE
	activewarrant_ref = null

UI_ACT(/datum/computer_file/program/digitalwarrant, "editwarrant", ui_act_editwarrant, UI_ARG_NUM("id"))
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_editwarrant)
	. = TRUE
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		if(W.warrant_id == params["id"])
			activewarrant_ref = W
			break

	// The following actions will only be possible if the user has an ID with security access equipped. This is in line with modular computer framework's authentication methods,
	// which also use RFID scanning to allow or disallow access to some functions. Anyone can view warrants, editing requires ID. This also prevents situations where you show a tablet
	// to someone who is to be arrested, which allows them to change the stuff there.

UI_ACT(/datum/computer_file/program/digitalwarrant, "addwarrant", ui_act_addwarrant)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_addwarrant)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	var/datum/data/record/warrant/W = new()
	var/temp = act_ask(ui.user, action, params, ui, "k85", /datum/om/prompt/choice/alert, message = "Do you want to create a search-, or an arrest warrant?", title = "Warrant Type", choices = list("Search","Arrest","Cancel"))
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

UI_ACT(/datum/computer_file/program/digitalwarrant, "savewarrant", ui_act_savewarrant)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_savewarrant)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	LAZYOR(GLOB.data_core.warrants, activewarrant())
	activewarrant_ref = null

UI_ACT(/datum/computer_file/program/digitalwarrant, "deletewarrant", ui_act_deletewarrant)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_deletewarrant)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	LAZYREMOVE(GLOB.data_core.warrants, activewarrant())
	activewarrant_ref = null

UI_ACT(/datum/computer_file/program/digitalwarrant, "editwarrantname", ui_act_editwarrantname)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_editwarrantname)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	var/namelist = list()
	for(var/datum/data/record/t in GLOB.data_core.general)
		namelist += t.fields["name"]
	var/new_name = act_ask(ui.user, action, params, ui, "k116", /datum/om/prompt/choice, message = "Please input name:", title = "Name Choice", choices = namelist)
	if(isnull(new_name))
		return
	if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		if (!new_name)
			return
		activewarrant().fields["namewarrant"] = new_name

UI_ACT(/datum/computer_file/program/digitalwarrant, "editwarrantnamecustom", ui_act_editwarrantnamecustom)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_editwarrantnamecustom)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	var/new_name = act_ask(ui.user, action, params, ui, "k124", /datum/om/prompt/text, message = "Please input name")
	if(isnull(new_name))
		return
	if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		if (!new_name)
			return
		activewarrant().fields["namewarrant"] = new_name

UI_ACT(/datum/computer_file/program/digitalwarrant, "editwarrantcharges", ui_act_editwarrantcharges)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_editwarrantcharges)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	if(!activewarrant())
		return
	var/new_charges = act_ask(ui.user, action, params, ui, "k134", /datum/om/prompt/text, message = "Please input charges", title = "Charges", default = activewarrant().fields["charges"])
	if(isnull(new_charges))
		return
	if(tgui_status(ui.user, state) == STATUS_INTERACTIVE)
		if (!new_charges || !activewarrant())
			return
		activewarrant().fields["charges"] = new_charges

UI_ACT(/datum/computer_file/program/digitalwarrant, "editwarrantauth", ui_act_editwarrantauth)
UI_ACT_PROC(/datum/computer_file/program/digitalwarrant, ui_act_editwarrantauth)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(ui.user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
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

DECLARE_REF(/datum/computer_file/program/digitalwarrant, "activewarrant_ref", BACK, null)
