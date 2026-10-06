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
	required_access = ACCESS_NETWORK
	category = PROG_ADMIN

	var/tmp/datum/computer_file/data/email_account/current_account
	var/tmp/datum/computer_file/data/email_message/current_message
	var/error = ""

CAPABILITIES(/datum/computer_file/program/email_administration)
	ref_one(nameof(current_account), /datum/computer_file/data/email_account)
	interface("NtosEmailAdministration")
	op("back", ui_act("back"), needs(req(PROC_REF(network_admin_access), silent = TRUE)), then(PROC_REF(ui_act_back)))
	op("ban", ui_act("ban"), needs(req(PROC_REF(network_admin_access), silent = TRUE)), then(PROC_REF(ui_act_ban)))
	op("changepass", ui_act("changepass"), needs(req(PROC_REF(network_admin_access), silent = TRUE)), needs(req(PROC_REF(has_account), silent = TRUE)), asks(/datum/prompt/text, fields = list("title" = "Password", "question" = computed(PROC_REF(newpass_question)), "max_len" = 100)), then(PROC_REF(ui_act_changepass)))
	op("viewmail", ui_act("viewmail", arg("viewmail", num())), needs(req(PROC_REF(network_admin_access), silent = TRUE)), then(PROC_REF(ui_act_viewmail)))
	op("viewaccount", ui_act("viewaccount", arg("viewaccount", num())), needs(req(PROC_REF(network_admin_access), silent = TRUE)), then(PROC_REF(ui_act_viewaccount)))
	op("newaccount", ui_act("newaccount"), needs(req(PROC_REF(network_admin_access), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Domain name", "question" = "Pick domain:", "choices" = computed(PROC_REF(email_domains))), step = "domain"), asks(/datum/prompt/text, fields = list("title" = "Account name", "question" = computed(PROC_REF(account_question)), "max_len" = 100), step = "login", when = PROC_REF(domain_chosen)), then(PROC_REF(ui_act_newaccount)))

/datum/computer_file/program/email_administration/ui_data(datum/act/eval/A)
	var/list/data = get_header_data()
	data["error"] = error

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

/// Requirement on every button: the user's ID has network access (silent, as the old guard was).
/datum/computer_file/program/email_administration/proc/network_admin_access(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user?.GetIdCard()
	return istype(I) && (ACCESS_NETWORK in I.GetAccess())

/datum/computer_file/program/email_administration/proc/ui_act_back(datum/act/op/A)
	if(error)
		error = ""
	else if(current_message())
		rel_clear(src, nameof(/datum/tgui_module/email_client::current_message))
	else
		rel_clear(src, nameof(/datum/tgui_module/email_client::current_account))
	return TRUE

/datum/computer_file/program/email_administration/proc/ui_act_ban(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user.GetIdCard()
	if(!current_account())
		return TRUE

	current_account().suspended = !current_account().suspended
	GLOB.ntnet_global.add_log_with_ids_check("EMAIL LOG: SA-EDIT Account [current_account().login] has been [current_account().suspended ? "" : "un" ]suspended by SA [I.registered_name] ([I.assignment]).")
	error = "Account [current_account().login] has been [current_account().suspended ? "" : "un" ]suspended."
	return TRUE

/datum/computer_file/program/email_administration/proc/has_account(datum/act/op/A)
	return !!current_account()

/datum/computer_file/program/email_administration/proc/newpass_question(datum/act/op/A)
	return "Enter new password for account [current_account()?.login]"

/datum/computer_file/program/email_administration/proc/ui_act_changepass(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = user.GetIdCard()
	if(!current_account())
		return TRUE

	var/datum/prompt/P = A.answer
	var/newpass = P?.value
	if(!newpass)
		return TRUE
	current_account().password = newpass
	GLOB.ntnet_global.add_log_with_ids_check("EMAIL LOG: SA-EDIT Password for account [current_account().login] has been changed by SA [I.registered_name] ([I.assignment]).")
	return TRUE

/datum/computer_file/program/email_administration/proc/ui_act_viewmail(datum/act/op/A, viewmail)
	if(!current_account())
		return TRUE

	for(var/datum/computer_file/data/email_message/received_message in (current_account().inbox | current_account().spam | current_account().deleted))
		if(received_message.uid == viewmail)
			rel_set(src, nameof(/datum/tgui_module/email_client::current_message), received_message)
			break
	return TRUE

/datum/computer_file/program/email_administration/proc/ui_act_viewaccount(datum/act/op/A, viewaccount)
	for(var/datum/computer_file/data/email_account/email_account in GLOB.ntnet_global.email_accounts)
		if(email_account.uid == viewaccount)
			rel_set(src, nameof(/datum/tgui_module/email_client::current_account), email_account)
			break
	return TRUE

/datum/computer_file/program/email_administration/proc/email_domains(datum/act/op/A)
	return using_map.usable_email_tlds

/datum/computer_file/program/email_administration/proc/domain_chosen(datum/act/op/A)
	var/datum/prompt/P = A.step_answer("domain")
	return !!P?.value

/datum/computer_file/program/email_administration/proc/account_question(datum/act/op/A)
	var/datum/prompt/P = A.step_answer("domain")
	return "Pick account name (@[P?.value]):"

/datum/computer_file/program/email_administration/proc/ui_act_newaccount(datum/act/op/A)
	var/datum/prompt/domain_answer = A.step_answer("domain")
	var/datum/prompt/login_answer = A.step_answer("login")
	var/newdomain = domain_answer?.value
	var/newlogin = login_answer?.value
	if(!newdomain || !newlogin)
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
