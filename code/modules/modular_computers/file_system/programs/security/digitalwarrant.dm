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
	category = PROG_SEC

	var/tmp/datum/data/record/warrant/activewarrant_ref

CAPABILITIES(/datum/computer_file/program/digitalwarrant)
	interface("NtosDigitalWarrant")
	op("back", ui_act("back"), then(PROC_REF(ui_act_back)))
	op("editwarrant", ui_act("editwarrant", arg("id", num())), then(PROC_REF(ui_act_editwarrant)))
	op("addwarrant", ui_act("addwarrant"), needs(req_bool(PROC_REF(warrant_id_ok), because = MSG(digitalwarrant/no_id))), asks(/datum/prompt/choice, fields = list("title" = "Warrant Type", "question" = "Do you want to create a search-, or an arrest warrant?", "choices" = list("Search", "Arrest", "Cancel"))), then(PROC_REF(ui_act_addwarrant)))
	op("savewarrant", ui_act("savewarrant"), then(PROC_REF(ui_act_savewarrant)))
	op("deletewarrant", ui_act("deletewarrant"), then(PROC_REF(ui_act_deletewarrant)))
	op("editwarrantname", ui_act("editwarrantname"), needs(req_bool(PROC_REF(warrant_id_ok), because = MSG(digitalwarrant/no_id))), asks(/datum/prompt/choice, fields = list("title" = "Name Choice", "question" = "Please input name:", "choices" = computed(PROC_REF(general_names)))), then(PROC_REF(ui_act_editwarrantname)))
	op("editwarrantnamecustom", ui_act("editwarrantnamecustom"), needs(req_bool(PROC_REF(warrant_id_ok), because = MSG(digitalwarrant/no_id))), asks(/datum/prompt/text, fields = list("title" = "Name", "question" = "Please input name")), then(PROC_REF(ui_act_editwarrantnamecustom)))
	op("editwarrantcharges", ui_act("editwarrantcharges"), needs(req_bool(PROC_REF(warrant_id_ok), because = MSG(digitalwarrant/no_id))), asks(/datum/prompt/text, fields = list("title" = "Charges", "question" = "Please input charges", "default" = computed(PROC_REF(charges_default)))), then(PROC_REF(ui_act_editwarrantcharges)))
	op("editwarrantauth", ui_act("editwarrantauth"), then(PROC_REF(ui_act_editwarrantauth)))

/datum/computer_file/program/digitalwarrant/ui_data(datum/act/eval/A)
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

/datum/computer_file/program/digitalwarrant/proc/ui_act_back(datum/act/op/A)
	rel_clear(src, nameof(/datum/computer_file/program/digitalwarrant::activewarrant_ref))
	return OP_OK

/datum/computer_file/program/digitalwarrant/proc/ui_act_editwarrant(datum/act/op/A, id)
	. = TRUE
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		if(W.warrant_id == id)
			rel_set(src, nameof(/datum/computer_file/program/digitalwarrant::activewarrant_ref), W)
			break

	// The following actions will only be possible if the user has an ID with security access equipped. This is in line with modular computer framework's authentication methods,
	// which also use RFID scanning to allow or disallow access to some functions. Anyone can view warrants, editing requires ID. This also prevents situations where you show a tablet
	// to someone who is to be arrested, which allows them to change the stuff there.

/// The person holds an ID with security access (editing warrants needs one: anyone may view them).
/datum/computer_file/program/digitalwarrant/proc/warrant_id_ok(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user.GetIdCard()
	return istype(I) && I.registered_name && (ACCESS_SECURITY in I.GetAccess())

MSG_DEF_SELF(digitalwarrant/no_id, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")

/datum/computer_file/program/digitalwarrant/proc/general_names(datum/act/op/A)
	var/namelist = list()
	for(var/datum/data/record/t in GLOB.data_core.general)
		namelist += t.fields["name"]
	return namelist

/datum/computer_file/program/digitalwarrant/proc/charges_default(datum/act/op/A)
	return activewarrant()?.fields["charges"]

/datum/computer_file/program/digitalwarrant/proc/ui_act_addwarrant(datum/act/op/A)
	. = TRUE
	var/datum/prompt/P = A.answer
	var/temp = P?.value
	if(!temp || temp == "Cancel")
		return
	var/datum/data/record/warrant/W = new()
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
	rel_set(src, nameof(/datum/computer_file/program/digitalwarrant::activewarrant_ref), W)

/datum/computer_file/program/digitalwarrant/proc/ui_act_savewarrant(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	LAZYOR(GLOB.data_core.warrants, activewarrant())
	rel_clear(src, nameof(/datum/computer_file/program/digitalwarrant::activewarrant_ref))

/datum/computer_file/program/digitalwarrant/proc/ui_act_deletewarrant(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	LAZYREMOVE(GLOB.data_core.warrants, activewarrant())
	rel_clear(src, nameof(/datum/computer_file/program/digitalwarrant::activewarrant_ref))

/datum/computer_file/program/digitalwarrant/proc/ui_act_editwarrantname(datum/act/op/A)
	. = TRUE
	var/datum/prompt/P = A.answer
	var/new_name = P?.value
	if(!new_name || !activewarrant())
		return
	activewarrant().fields["namewarrant"] = new_name

/datum/computer_file/program/digitalwarrant/proc/ui_act_editwarrantnamecustom(datum/act/op/A)
	. = TRUE
	var/datum/prompt/P = A.answer
	var/new_name = P?.value
	if(!new_name || !activewarrant())
		return
	activewarrant().fields["namewarrant"] = new_name

/datum/computer_file/program/digitalwarrant/proc/ui_act_editwarrantcharges(datum/act/op/A)
	. = TRUE
	if(!activewarrant())
		return
	var/datum/prompt/P = A.answer
	var/new_charges = P?.value
	if(!new_charges || !activewarrant())
		return
	activewarrant().fields["charges"] = new_charges

/datum/computer_file/program/digitalwarrant/proc/ui_act_editwarrantauth(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user.GetIdCard()
	if(!istype(I) || !I.registered_name || !(ACCESS_SECURITY in I.GetAccess()))
		to_chat(user, "Authentication error: Unable to locate ID with appropriate access to allow this operation.")
		return
	. = TRUE
	if(!activewarrant())
		return
	if(!(ACCESS_HOS in I.GetAccess())) // begin
		to_chat(user, span_warning("You don't have the access to do this!"))
		return // end
	activewarrant().fields["auth"] = "[I.registered_name] - [I.assignment ? I.assignment : "(Unknown)"]"

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/computer_file/program/digitalwarrant/proc/activewarrant() as /datum/data/record/warrant
	return activewarrant_ref
