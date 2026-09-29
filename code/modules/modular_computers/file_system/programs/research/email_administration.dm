/datum/computer_file/program/email_administration
	filename = "emailadmin"
	filedesc = "Email Administration Utility"
	extended_desc = "This program may be used to administrate NTNet's emailing service."
	program_icon_state = "comm_monitor"
	program_key_state = "generic_key"
	program_menu_icon = "mail-open"
	size = 12
	requires_ntnet = TRUE
	available_on_ntnet = TRUE
	tgui_id = "NtosEmailAdministration"
	required_access = ACCESS_NETWORK
	category = PROG_ADMIN

	var/tmp/datum/computer_file/data/email_account/current_account
	var/tmp/datum/computer_file/data/email_message/current_message
	var/error = ""

UI_DATA_REPLACE(/datum/computer_file/program/email_administration, "error:text", "merge:ui_data_datum_computer_file_program_email_administration{cur_title:text,cur_body:unknown,cur_timestamp:unknown,cur_source:text,current_account:text,cur_suspended:num,messages:list,accounts:list}")

/// The computed part of /datum/computer_file/program/email_administration's window data (declared on its UI_DATA row).
/datum/computer_file/program/email_administration/proc/ui_data_datum_computer_file_program_email_administration(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = get_header_data()


	data["cur_title"] = null
	data["cur_body"] = null
	data["cur_timestamp"] = null
	data["cur_source"] = null

	if(istype(current_message(), /datum/computer_file/data/email_message))
		data["cur_title"] = current_message().title
		data["cur_body"] = pencode2html(current_message().stored_data)
		data["cur_timestamp"] = current_message().timestamp
		data["cur_source"] = current_message().source

	data["current_account"] = null
	data["cur_suspended"] = null
	data["messages"] = null

	if(istype(current_account(), /datum/computer_file/data/email_account))
		data["current_account"] = current_account().login
		data["cur_suspended"] = current_account().suspended
		var/list/all_messages = list()
		for(var/datum/computer_file/data/email_message/message in (current_account().inbox | current_account().spam | current_account().deleted))
			all_messages.Add(list(list(
				"title" = message.title,
				"source" = message.source,
				"timestamp" = message.timestamp,
				"uid" = message.uid
			)))
		data["messages"] = all_messages

	var/list/all_accounts = list()
	for(var/datum/computer_file/data/email_account/account in GLOB.ntnet_global.email_accounts)
		if(!account.can_login)
			continue
		all_accounts.Add(list(list(
			"login" = account.login,
			"uid" = account.uid
		)))
	data["accounts"] = all_accounts

	return data

/datum/computer_file/program/email_administration/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!istype(I) || !(ACCESS_NETWORK in I.GetAccess()))
		return FALSE
	return TRUE

UI_ACT(/datum/computer_file/program/email_administration, "back", ui_act_back)
UI_ACT_PROC(/datum/computer_file/program/email_administration, ui_act_back)
	if(error)
		error = ""
	else if(current_message())
		rel_clear(src, "current_message")
	else
		rel_clear(src, "current_account")
	return TRUE

UI_ACT(/datum/computer_file/program/email_administration, "ban", ui_act_ban)
UI_ACT_PROC(/datum/computer_file/program/email_administration, ui_act_ban)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!current_account())
		return TRUE

	current_account().suspended = !current_account().suspended
	GLOB.ntnet_global.add_log_with_ids_check("EMAIL LOG: SA-EDIT Account [current_account().login] has been [current_account().suspended ? "" : "un" ]suspended by SA [I.registered_name] ([I.assignment]).")
	error = "Account [current_account().login] has been [current_account().suspended ? "" : "un" ]suspended."
	return TRUE

UI_ACT(/datum/computer_file/program/email_administration, "changepass", ui_act_changepass)
UI_ACT_PROC(/datum/computer_file/program/email_administration, ui_act_changepass)
	var/obj/item/card/id/I = ui.user.GetIdCard()
	if(!current_account())
		return TRUE

	var/newpass = act_ask(ui.user, action, params, ui, "k96", /datum/om/prompt/text, message = "Enter new password for account [current_account().login]", title = "Password", max_length = 100)
	if(isnull(newpass))
		return
	if(!newpass)
		return TRUE
	current_account().password = newpass
	GLOB.ntnet_global.add_log_with_ids_check("EMAIL LOG: SA-EDIT Password for account [current_account().login] has been changed by SA [I.registered_name] ([I.assignment]).")
	return TRUE

UI_ACT(/datum/computer_file/program/email_administration, "viewmail", ui_act_viewmail, UI_ARG_NUM("viewmail"))
UI_ACT_PROC(/datum/computer_file/program/email_administration, ui_act_viewmail)
	if(!current_account())
		return TRUE

	for(var/datum/computer_file/data/email_message/received_message in (current_account().inbox | current_account().spam | current_account().deleted))
		if(received_message.uid == params["viewmail"])
			rel_set(src, "current_message", received_message)
			break
	return TRUE

UI_ACT(/datum/computer_file/program/email_administration, "viewaccount", ui_act_viewaccount, UI_ARG_NUM("viewaccount"))
UI_ACT_PROC(/datum/computer_file/program/email_administration, ui_act_viewaccount)
	for(var/datum/computer_file/data/email_account/email_account in GLOB.ntnet_global.email_accounts)
		if(email_account.uid == params["viewaccount"])
			rel_set(src, "current_account", email_account)
			break
	return TRUE

UI_ACT(/datum/computer_file/program/email_administration, "newaccount", ui_act_newaccount)
UI_ACT_PROC(/datum/computer_file/program/email_administration, ui_act_newaccount)
	var/newdomain = act_ask(ui.user, action, params, ui, "k121", /datum/om/prompt/choice, message = "Pick domain:", title = "Domain name", choices = using_map.usable_email_tlds)
	if(isnull(newdomain))
		return
	if(!newdomain)
		return TRUE
	var/newlogin = act_ask(ui.user, action, params, ui, "k124", /datum/om/prompt/text, message = "Pick account name (@[newdomain]):", title = "Account name", max_length = 100)
	if(isnull(newlogin))
		return
	if(!newlogin)
		return TRUE

	var/complete_login = "[newlogin]@[newdomain]"
	if(GLOB.ntnet_global.does_email_exist(complete_login))
		error = "Error creating account: An account with same address already exists."
		return TRUE

	var/datum/computer_file/data/email_account/new_account = new/datum/computer_file/data/email_account()
	new_account.login = complete_login
	new_account.password = GenerateKey()
	error = "Email [new_account.login] has been created, with generated password [new_account.password]"
	return TRUE

/// The current_account this refers to (a relation view: null once that is deleted).
/datum/computer_file/program/email_administration/proc/current_account() as /datum/computer_file/data/email_account
	return current_account

/// The current_message this refers to (a relation view: null once that is deleted).
/datum/computer_file/program/email_administration/proc/current_message() as /datum/computer_file/data/email_message
	return current_message
