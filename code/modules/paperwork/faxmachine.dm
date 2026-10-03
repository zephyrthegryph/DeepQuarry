GLOBAL_LIST_INIT(admin_departments, list("[using_map.boss_name]", "Solar Central Government", "Central Command Job Boards", "Supply"))
GLOBAL_LIST_EMPTY(alldepartments)
GLOBAL_VAR(last_fax_role_request)

GLOBAL_LIST_EMPTY(adminfaxes)	//cache for faxes that have been sent to admins

/obj/machinery/photocopier/faxmachine
	name = "fax machine"
	desc = "Send papers and pictures far away! Or to your co-worker's office a few doors down."
	icon = 'icons/obj/library.dmi'
	icon_state = "fax"
	insert_anim = "faxsend"
	req_one_access = list()
	density = 0

	use_power = USE_POWER_IDLE
	idle_power_usage = 30
	active_power_usage = 200
	circuit = /obj/item/circuitboard/fax

	var/obj/item/card/id/scan = null
	var/authenticated = null
	var/rank = null

	var/sendcooldown = 0 // to avoid spamming fax messages
	var/department = "Unknown" // our department
	var/destination = null // the department we're sending to
	var/talon = 0 // So that the talon can access their own crew roles for the request

REGISTRY_MEMBERSHIP(/obj/machinery/photocopier/faxmachine, REGISTRY_FAXES)

/obj/machinery/photocopier/faxmachine/Initialize(mapload)
	. = ..()
	if(!destination) destination = "[using_map.boss_name]"
	if( !(("[department]" in GLOB.alldepartments) || ("[department]" in GLOB.admin_departments)) )
		GLOB.alldepartments |= department

/obj/machinery/photocopier/faxmachine/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/faxmachine_insert_id,
		/datum/interaction/machine_item/faxmachine_insert_toner,
		/datum/interaction/machine_hand/ungated/faxmachine_open_ui,
		/datum/interaction/machine_verb/faxmachine_remove_card,
		/datum/interaction/machine_verb/faxmachine_request_roles,
	)
	..()

/datum/interaction/machine_hand/ungated/faxmachine_open_ui
	id = "faxmachine_open_ui"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/photocopier/faxmachine/proc/interaction_open_ui_impl

/obj/machinery/photocopier/faxmachine/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user)) // this allows borgs to use fax machines, meant for the Unity and Clerical modules.
		authenticated = user.name
	tgui_interact(user)
	return TRUE

/datum/interaction/machine_verb/faxmachine_remove_card
	id = "faxmachine_remove_card"
	name = "Remove ID card"
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/photocopier/faxmachine/proc/interaction_remove_card
	also_requires = list(REQ_FIELD("scan", "there is no ID card to remove"))

/obj/machinery/photocopier/faxmachine/proc/interaction_remove_card(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/L = user

	if(!L || !isturf(L.loc) || !isliving(L))
		return TRUE
	if(!ishuman(L) && !issilicon(L))
		return TRUE
	if(L.stat || L.restrained())
		return TRUE

	scan.forceMove(loc)
	if(ishuman(L) && !L.get_active_hand())
		L.put_in_hands(scan)
		own_take(src, nameof(scan))
	authenticated = null
	return TRUE

/datum/interaction/machine_verb/faxmachine_request_roles
	id = "faxmachine_request_roles"
	name = "Staff Request Form"
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/photocopier/faxmachine/proc/interaction_request_roles

/obj/machinery/photocopier/faxmachine/proc/interaction_request_roles(mob/user, obj/item/held, datum/interaction/interaction)
	request_roles(user)
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/request_roles(mob/living/L)

	if(!L || !isturf(L.loc) || !isliving(L))
		return
	if(!ishuman(L) && !issilicon(L))
		return
	if(L.stat || L.restrained())
		return
	if(GLOB.last_fax_role_request && (ELAPSED_SINCE(src, GLOB.last_fax_role_request, CLOCK_WORLD) < 5 MINUTES))
		to_chat(L, span_warning("The global automated relays are still recalibrating. Try again later or relay your request in written form for processing."))
		return

	var/confirmation = rerun_ask(L, "k109", PROC_REF(request_roles), args, /datum/om/prompt/choice/alert, message = "Are you sure you want to send automated crew request?", title = "Confirmation", choices = list("Yes", "No", "Cancel"))
	if(isnull(confirmation))
		return
	if(confirmation != "Yes")
		return

	var/list/jobs = list()
	for(var/datum/department/dept as anything in SSjob.get_all_department_datums())
		if(!src.talon)
			if(!dept.assignable || dept.centcom_only)
				continue
			for(var/job in SSjob.get_job_titles_in_department(dept.name))
				var/datum/job/J = SSjob.get_job(job)
				if(J.requestable)
					jobs |= job
		else
			for(var/job in SSjob.get_job_titles_in_department(dept.name))
				var/datum/job/J = SSjob.get_job(job)
				if(J.offmap_spawn)
					jobs |= job

	var/role = rerun_ask(L, "k128", PROC_REF(request_roles), args, /datum/om/prompt/choice, message = "Pick the job to request.", title = "Job Request", choices = jobs)
	if(isnull(role))
		return
	if(!role)
		return

	var/datum/job/job_to_request = SSjob.get_job(role)
	var/reason = "Unspecified"
	var/list/possible_reasons = list("Unspecified", "General duties", "Emergency situation")
	possible_reasons += TYPE_TABLE_GET(job_to_request, get_request_reasons)
	var/_answer_k136 = rerun_ask(L, "k136", PROC_REF(request_roles), args, /datum/om/prompt/choice, message = "Pick request reason.", title = "Request reason", choices = possible_reasons)
	if(isnull(_answer_k136))
		return
	reason = _answer_k136

	var/final_conf = rerun_ask(L, "k138", PROC_REF(request_roles), args, /datum/om/prompt/choice/alert, message = "You are about to request [role]. Are you sure?", title = "Confirmation", choices = list("Yes", "No", "Cancel"))
	if(isnull(final_conf))
		return
	if(final_conf != "Yes")
		return

	var/datum/department/ping_dept = SSjob.get_ping_role(role)
	if(!ping_dept)
		to_chat(L, span_warning("Selected job cannot be requested for \[ERRORDEPTNOTFOUND] reason. Please report this to system administrator."))
		return
	var/message_color = "#FFFFFF"
	var/ping_name = null
	switch(ping_dept.name)
		if(DEPARTMENT_COMMAND)
			ping_name = "Command"
		if(DEPARTMENT_SECURITY)
			ping_name = "Security"
		if(DEPARTMENT_ENGINEERING)
			ping_name = "Engineering"
		if(DEPARTMENT_MEDICAL)
			ping_name = "Medical"
		if(DEPARTMENT_RESEARCH)
			ping_name = "Research"
		if(DEPARTMENT_CARGO)
			ping_name = "Supply"
		if(DEPARTMENT_CIVILIAN)
			ping_name = "Service"
		if(DEPARTMENT_PLANET)
			ping_name = "Expedition"
		if(DEPARTMENT_SYNTHETIC)
			ping_name = "Silicon"
		if(DEPARTMENT_TALON)
			ping_name = "Offmap"
	if(!ping_name)
		to_chat(L, span_warning("Selected job cannot be requested for \[ERRORUNKNOWNDEPT] reason. Please report this to system administrator."))
		return
	message_color = ping_dept.color

	message_chat_rolerequest(message_color, ping_name, reason, role)
	GLOB.last_fax_role_request = EXPIRY_AT(src, CLOCK_WORLD, 0)
	to_chat(L, span_notice("Your request was transmitted."))

DECLARE_UI(/obj/machinery/photocopier/faxmachine, "Fax")

UI_DATA(/obj/machinery/photocopier/faxmachine, "authenticated", "rank", "copyItem=copyitem", "cooldown=sendcooldown:num", "destination", "merge:ui_data_obj_machinery_photocopier_faxmachine{scan:text,isAI:num,isRobot:num,adminDepartments:unknown,bossName:text}")

/// The computed part of /obj/machinery/photocopier/faxmachine's window data (declared on its UI_DATA row).
/obj/machinery/photocopier/faxmachine/proc/ui_data_obj_machinery_photocopier_faxmachine(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scan"] = scan ? scan.name : null
	data["isAI"] = isAI(user)
	data["isRobot"] = isrobot(user)
	data["adminDepartments"] = GLOB.admin_departments

	data["bossName"] = using_map.boss_name

	return data

UI_ACT(/obj/machinery/photocopier/faxmachine, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_scan)
	if(scan)
		scan.forceMove(loc)
		if(ishuman(ui.user) && !ui.user.get_active_hand())
			ui.user.put_in_hands(scan)
		own_take(src, nameof(/obj/item/extrapolator::scan))
	else
		var/obj/item/I = ui.user.get_active_hand()
		if(istype(I, /obj/item/card/id))
			own_set(src, nameof(src.scan), I, user = ui.user)
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "login", ui_act_login, UI_ARG_NUM("login_type"))
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_login)
	var/login_type = params["login_type"]
	if(login_type == LOGIN_TYPE_NORMAL && istype(scan))
		if(check_access(scan))
			authenticated = scan.registered_name
			rank = scan.assignment
	else if(login_type == LOGIN_TYPE_AI && isAI(ui.user))
		authenticated = ui.user.name
		rank = JOB_AI
	else if(login_type == LOGIN_TYPE_ROBOT && isrobot(ui.user))
		authenticated = ui.user.name
		var/mob/living/silicon/robot/R = ui.user
		rank = "[R.modtype] [R.braintype]"
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "logout", ui_act_logout)
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_logout)
	if(scan)
		scan.forceMove(loc)
		if(ishuman(ui.user) && !ui.user.get_active_hand())
			ui.user.put_in_hands(scan)
		own_take(src, nameof(/obj/item/extrapolator::scan))
	authenticated = null
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "remove", ui_act_remove)
UI_ACT_OVERRIDE(/obj/machinery/photocopier/faxmachine, ui_act_remove)
	. = ..()
	if(.)
		return
	if(copyitem)
		if(get_dist(ui.user, src) >= 2)
			to_chat(ui.user, "\The [copyitem] is too far away for you to remove it.")
			return
		copyitem.forceMove(loc)
		ui.user.put_in_hands(copyitem)
		to_chat(ui.user, span_notice("You take \the [copyitem] out of \the [src]."))
		own_take(src, nameof(/obj/machinery/photocopier::copyitem))
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "send_automated_staff_request", ui_act_send_automated_staff_request)
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_send_automated_staff_request)
	request_roles(ui.user)
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "rename", ui_act_rename)
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_rename)
	if(!authenticated)
		return
	if(copyitem)
		var/new_name = act_ask(ui.user, action, params, ui, "k258", /datum/om/prompt/text, message = "Enter new paper title", title = "This will show up in the preview for staff chat on discord when sending to central.", default = copyitem.name, max_length = MAX_NAME_LEN)
		if(isnull(new_name))
			return
		if(!new_name)
			return
		copyitem.name = new_name
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "send", ui_act_send)
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_send)
	if(!authenticated)
		return
	if(copyitem)
		if (destination in GLOB.admin_departments)
			if(check_if_default_title_and_rename(ui.user, action, params, ui))
				return
			send_admin_fax(ui.user, destination)
		else
			sendfax(destination, ui.user)

		if (sendcooldown)
			om_after(src, sendcooldown, PROC_REF(cooldown_over))
	return TRUE

UI_ACT(/obj/machinery/photocopier/faxmachine, "dept", ui_act_dept)
UI_ACT_PROC(/obj/machinery/photocopier/faxmachine, ui_act_dept)
	if(!authenticated)
		return
	var/lastdestination = destination
	var/_answer_k276 = act_ask(ui.user, action, params, ui, "k276", /datum/om/prompt/choice, message = "Which department?", title = "Choose a department", choices = (GLOB.alldepartments + GLOB.admin_departments))
	if(isnull(_answer_k276))
		return
	destination = _answer_k276
	if(!destination)
		destination = lastdestination
	return TRUE


/// Returns TRUE on "Cancel", an invalid newname or while the questions wait (their answers re-run the
/// send action with the same params), else returns null/false.
/// Extracted to its own procedure for easier logic handling with paper bundles.
/obj/machinery/photocopier/faxmachine/proc/check_if_default_title_and_rename(mob/user, action, list/params, datum/tgui/ui)
	var/question_text = "Your fax is set to its default name. It's advisable to rename it to something self-explanatory to"

	if(istype(copyitem, /obj/item/paper_bundle))
		var/obj/item/paper_bundle/B = copyitem
		if(B.name != initial(B.name))
			var/atom/page1 = B.pages[1]	//atom is enough for us to ensure it has name var. would've used ?. opertor, but linter doesnt like.
			var/atom/page2 = B.pages[2]
			if((istype(page1) && B.name == page1.name) || (istype(page2) && B.name == page2.name) )
				question_text = "Your fax is set to use the title of its first or second page. It's advisable to rename it to something \
				summarizing the entire bundle succintly to"
			else
				return FALSE
	else if(copyitem.name != initial(copyitem.name))
		return FALSE

	var/choice = act_ask(user, action, params, ui, "default_title", /datum/om/prompt/choice/alert, message = "[question_text] improve response time from staff when sending to discord. Renaming it changes its preview in staff chat.", title = "Default name detected", choices = list("Change Title","Continue", "Cancel"))
	if(!choice || choice == "Cancel")
		return TRUE
	else if(choice == "Change Title")
		var/new_name = act_ask(user, action, params, ui, "new_title", /datum/om/prompt/text, message = "Enter new fax title", title = "This will show up in the preview for staff chat on discord when sending to central.", default = copyitem.name, max_length = MAX_NAME_LEN)
		if(!new_name)
			return TRUE
		copyitem.name = new_name


/datum/interaction/machine_item/faxmachine_insert_id
	id = "faxmachine_insert_id"
	name = "Insert ID"
	held_type = /obj/item/card/id
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/photocopier/faxmachine/proc/no_id_inserted, null))
	effect = /obj/machinery/photocopier/faxmachine/proc/interaction_insert_id

/obj/machinery/photocopier/faxmachine/proc/no_id_inserted(mob/actor, atom/target, obj/item/held)
	return !scan

/obj/machinery/photocopier/faxmachine/proc/interaction_insert_id(mob/user, obj/item/held, datum/interaction/interaction)
	own_set(src, nameof(src.scan), held, user = user)
	return TRUE

/datum/interaction/machine_item/faxmachine_insert_toner
	id = "faxmachine_insert_toner"
	name = "Insert toner"
	held_type = /obj/item/toner
	effect = /obj/machinery/photocopier/faxmachine/proc/interaction_insert_toner_impl

/obj/machinery/photocopier/faxmachine/proc/interaction_insert_toner_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(toner <= 10) //allow replacing when low toner is affecting the print darkness
		if(!istype(held, /obj/item/toner))
			return TRUE
		var/obj/item/toner/T = held
		var/refill_amount = T.toner_amount
		if(!consume(held, user))
			return TRUE
		to_chat(user, span_notice("You insert the toner cartridge into \the [src]."))
		play_sfx(loc, SFX_MACHINES_CLICK)
		toner += refill_amount
	else
		to_chat(user, span_notice("This cartridge is not yet ready for replacement! Use up the rest of the toner."))
		play_sfx(loc, SFX_MACHINES_BUZZ_TWO, 1.5, vary = TRUE)
	return TRUE

/obj/machinery/photocopier/faxmachine/multitool_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	var/input = rerun_ask(user, "k352", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/text, message = "What Department ID would you like to give this fax machine?", title = "Multitool-Fax Machine Interface", default = department)
	if(isnull(input))
		return ITEM_INTERACT_BLOCKING
	if(!input)
		to_chat(user, "No input found. Please hang up and try your call again.")
		return ITEM_INTERACT_BLOCKING
	department = input
	if(!(("[department]" in GLOB.alldepartments) || ("[department]" in GLOB.admin_departments)) && department != "Unknown")
		GLOB.alldepartments |= department
	return ITEM_INTERACT_SUCCESS

/obj/machinery/photocopier/faxmachine/proc/sendfax(destination, mob/living/sender)
	if(!operable())
		return

	use_power(200)

	var/obj/item/card/id/authenticated_id = scan
	var/success = process_contract_fax(copyitem, destination, authenticated_id?.associated_account_number, sender)
	for(var/obj/machinery/photocopier/faxmachine/F in REGISTRY_MEMBERS(REGISTRY_FAXES))
		if( F.department == destination )
			success = F.receivefax(copyitem) || success

	if (success)
		emit_contract_event(CONTRACT_EVENT_FAX_ACCEPTED, list(
			"actor_account" = authenticated_id?.associated_account_number,
			"destination" = destination,
			"detail" = "Accepted fax transmission to [destination]",
		), "fax-accepted:[REF(copyitem)]:[destination]", copyitem, sender)
		visible_message("[src] beeps, \"Message transmitted successfully.\"")
	else
		visible_message("[src] beeps, \"Error transmitting message.\"")
	return success

/obj/machinery/photocopier/faxmachine/proc/receivefax(obj/item/incoming)
	if(!operable())
		return 0

	if(department == "Unknown")
		return 0	//You can't send faxes to "Unknown"

	if(!istype(incoming, /obj/item/paper) && !istype(incoming, /obj/item/photo) && !istype(incoming, /obj/item/paper_bundle))
		return 0

	flick("faxreceive", src)
	playsound(src, "sound/machines/printer.ogg", 50, 1)

	// give the sprite some time to flick
	om_after(src, 2 SECONDS, PROC_REF(print_received), incoming)
	return 1

/obj/machinery/photocopier/faxmachine/proc/print_received(obj/item/incoming)
	if (istype(incoming, /obj/item/paper))
		copy(incoming)
	else if (istype(incoming, /obj/item/photo))
		photocopy(incoming)
	else if (istype(incoming, /obj/item/paper_bundle))
		bundlecopy(incoming)
	use_power(active_power_usage)

/obj/machinery/photocopier/faxmachine/proc/send_admin_fax(mob/sender, destination)
	if(!operable())
		return

	use_power(200)

	//received copies should not use toner since it's being used by admins only.
	var/obj/item/rcvdcopy
	if (istype(copyitem, /obj/item/paper))
		rcvdcopy = copy(copyitem, 0)
	else if (istype(copyitem, /obj/item/photo))
		rcvdcopy = photocopy(copyitem, 0)
	else if (istype(copyitem, /obj/item/paper_bundle))
		rcvdcopy = bundlecopy(copyitem, 0)
	else
		visible_message("[src] beeps, \"Error transmitting message.\"")
		return

	rcvdcopy.moveToNullspace() //hopefully this shouldn't cause trouble
	GLOB.adminfaxes += rcvdcopy

	//message badmins that a fax has arrived

	// Sadly, we can't use a switch statement here due to not using a constant value for the current map's centcom name.
	if(destination == using_map.boss_name)
		message_admins(sender, "[uppertext(using_map.boss_short)] FAX", rcvdcopy, "CentComFaxReply", "#006100")
	else if(destination == "Solar Central Government")
		message_admins(sender, "Solar Central Government FAX", rcvdcopy, "CentComFaxReply", "#1F66A0")
	else if(destination == "Supply")
		message_admins(sender, "[uppertext(using_map.boss_short)] SUPPLY FAX", rcvdcopy, "CentComFaxReply", "#5F4519")
	else if(destination == "Talon Headquarters")
		message_admins(sender, "TALON HEADQUARTERS FAX", rcvdcopy, "CentComFaxReply", "#e96046")
	else
		message_admins(sender, "[uppertext(destination)] FAX", rcvdcopy, "UNKNOWN")

	sendcooldown = 1800
	om_after(src, 5 SECONDS, TYPE_PROC_REF(/atom, visible_message), "[src] beeps, \"Message transmitted successfully.\"")

// Turns objects into just text.
/obj/machinery/photocopier/faxmachine/proc/make_summary(obj/item/sent)
	if(istype(sent, /obj/item/paper))
		var/obj/item/paper/P = sent
		return P.info
	if(istype(sent, /obj/item/paper_bundle))
		. = ""
		var/obj/item/paper_bundle/B = sent
		for(var/i in 1 to B.pages.len)
			var/obj/item/paper/P = B.pages[i]
			if(istype(P)) // Photos can show up here too.
				if(.) // Space out different pages.
					. += "<br>"
				. += "PAGE [i] - [P.name]<br>"
				. += P.info

/obj/machinery/photocopier/faxmachine/proc/message_admins(mob/sender, faxname, obj/item/sent, reply_type, font_colour="#006100")
	var/msg = "<font color='[font_colour]'>[faxname]: </font>[get_options_bar(sender, 2,1,1)]"
	msg += "(<a href='byond://?_src_=holder;[HrefToken()];FaxReply=\ref[sender];originfax=\ref[src];replyorigin=[reply_type]'>REPLY</a>)"
	msg = span_bold(msg) + ": "
	msg += "Receiving '[sent.name]' via secure connection ... <a href='byond://?_src_=holder;[HrefToken(TRUE)];AdminFaxView=\ref[sent]'>view message</a>"
	msg = span_notice(msg)

	for(var/client/C in GLOB.admins)
		if(check_rights_for(C, (R_ADMIN|R_MOD|R_EVENT)))
			to_chat(C,msg)
			C << 'sound/machines/printer.ogg'
	sender.client << 'sound/machines/printer.ogg' // The pain must be felt

	var/faxid = export_fax(sent)
	message_chat_admins(sender, faxname, sent, faxid, font_colour) //Sends to admin chat

	// Webhooks don't parse the HTML on the paper, so we gotta strip them out so it's still readable.
	var/summary = make_summary(sent)
	summary = paper_html_to_plaintext(summary)

	log_game("Fax to [lowertext(faxname)] was sent by [key_name(sender)].")
	log_game(summary)

	var/webhook_length_limit = 1900 // The actual limit is a little higher.
	if(length(summary) > webhook_length_limit)
		summary = copytext(summary, 1, webhook_length_limit + 1)
		summary += "\n\[Truncated\]"

/*
								#####						####
								##### Webhook Functionality ####
								#####						####
*/

/datum/configuration
	var/chat_webhook_url = ""		// URL of the webhook for sending announcements/faxes to discord chat.
	var/chat_webhook_key = ""		// Shared secret for authenticating to the chat webhook
	var/fax_export_dir = "data/faxes"	// Directory in which to write exported fax HTML files.


/**
 * Write the fax to disk as (potentially multiple) HTML files.
 * If the fax is a paper_bundle, do so recursively for each page.
 * returns a random unique faxid.
 */
/obj/machinery/photocopier/faxmachine/proc/export_fax(fax)
	var faxid = "[num2text(world.realtime,12)]_[rand(10000)]"
	if (istype(fax, /obj/item/paper))
		var/obj/item/paper/P = fax
		var/text = "<HTML><HEAD><TITLE>[P.name]</TITLE></HEAD><BODY>[P.info][P.stamps]</BODY></HTML>";
		file("[CONFIG_GET(string/fax_export_dir)]/fax_[faxid].html") << text;
	else if (istype(fax, /obj/item/photo))
		var/obj/item/photo/H = fax
		fcopy(H.img, "[CONFIG_GET(string/fax_export_dir)]/photo_[faxid].png")
		var/text = "<html><head><title>[H.name]</title></head>" \
			+ "<body style='overflow:hidden;margin:0;text-align:center'>" \
			+ "<img src='photo_[faxid].png'>" \
			+ "[H.scribble ? "<br>Written on the back:<br><i>[H.scribble]</i>" : ""]"\
			+ "</body></html>"
		file("[CONFIG_GET(string/fax_export_dir)]/fax_[faxid].html") << text
	else if (istype(fax, /obj/item/paper_bundle))
		var/obj/item/paper_bundle/B = fax
		var/data = ""
		for (var/page = 1, page <= B.pages.len, page++)
			var/obj/pageobj = B.pages[page]
			var/page_faxid = export_fax(pageobj)
			data += "<a href='fax_[page_faxid].html'>Page [page] - [pageobj.name]</a><br>"
		var/text = "<html><head><title>[B.name]</title></head><body>[data]</body></html>"
		file("[CONFIG_GET(string/fax_export_dir)]/fax_[faxid].html") << text
	return faxid



/proc/get_role_request_channel()
	var/channel_tag
	if(CONFIG_GET(string/role_request_channel_tag))
		channel_tag = CONFIG_GET(string/role_request_channel_tag)

	var/datum/tgs_api/v5/api = TGS_READ_GLOBAL(tgs)
	if(istype(api) && channel_tag)
		for(var/datum/tgs_chat_channel/channel in api.chat_channels)
			if(channel.custom_tag == channel_tag)
				return list(channel)
	return 0

/proc/role_request_discord_message(message)
	if(!message)
		return
	var/datum/tgs_chat_channel/channel = get_role_request_channel()
	if(channel)
		world.TgsChatBroadcast(message,channel)

/proc/get_fax_channel()
	var/channel_tag
	if(CONFIG_GET(string/fax_channel_tag))
		channel_tag = CONFIG_GET(string/fax_channel_tag)

	var/datum/tgs_api/v5/api = TGS_READ_GLOBAL(tgs)
	if(istype(api) && channel_tag)
		for(var/datum/tgs_chat_channel/channel in api.chat_channels)
			if(channel.custom_tag == channel_tag)
				return list(channel)
	return 0

/proc/fax_discord_message(message)
	if(!message)
		return
	var/datum/tgs_chat_channel/channel = get_fax_channel()
	if(channel)
		world.TgsChatBroadcast(message,channel)

/proc/get_discord_role_id_from_department(department)
	switch(department)
		if("Command")
			if(CONFIG_GET(string/role_request_id_command))
				return CONFIG_GET(string/role_request_id_command)

		if("Security")
			if(CONFIG_GET(string/role_request_id_security))
				return CONFIG_GET(string/role_request_id_security)

		if("Engineering")
			if(CONFIG_GET(string/role_request_id_engineering))
				return CONFIG_GET(string/role_request_id_engineering)

		if("Medical")
			if(CONFIG_GET(string/role_request_id_medical))
				return CONFIG_GET(string/role_request_id_medical)

		if("Research")
			if(CONFIG_GET(string/role_request_id_research))
				return CONFIG_GET(string/role_request_id_research)

		if("Supply")
			if(CONFIG_GET(string/role_request_id_supply))
				return CONFIG_GET(string/role_request_id_supply)

		if("Service")
			if(CONFIG_GET(string/role_request_id_service))
				return CONFIG_GET(string/role_request_id_service)

		if("Expedition")
			if(CONFIG_GET(string/role_request_id_expedition))
				return CONFIG_GET(string/role_request_id_expedition)

		if("Silicon")
			if(CONFIG_GET(string/role_request_id_silicon))
				return CONFIG_GET(string/role_request_id_silicon)

	return FALSE


/**
 * Transmit a notification of an admin fax to the admin Discord channel.
 */
/obj/machinery/photocopier/faxmachine/proc/message_chat_admins(mob/sender, faxname, obj/item/sent, faxid, font_colour="#006100")
	var/faxmsg
	if(faxid && fexists("[CONFIG_GET(string/fax_export_dir)]/fax_[faxid].html"))
		faxmsg = file2text("[CONFIG_GET(string/fax_export_dir)]/fax_[faxid].html")

	if(faxmsg)
		fax_discord_message("A fax; '[faxname]' was sent.\nSender: [sender.name]\nFax name: [sent.name]\nFax ID: **[faxid]**\nFax: ```[strip_html_properly(faxmsg)]```")
	else
		fax_discord_message("A fax; '[faxname]' was sent.\nSender: [sender.name]\nFax name: [sent.name]\nFax ID: **[faxid]**")


/**
 * Transmit a notification of a job request to the role-request Discord channel.
 */
/obj/machinery/photocopier/faxmachine/proc/message_chat_rolerequest(font_colour="#006100", role_to_ping, reason, jobname)
	var/roleid = get_discord_role_id_from_department(role_to_ping)

	if(roleid)
		role_request_discord_message("An automated request for crew has been made.\nJob: [jobname]\nReason: [reason]\n\n<@&[roleid]>")
	else
		role_request_discord_message("An automated request for crew has been made.\nJob: [jobname]\nReason: [reason]")

/obj/machinery/photocopier/faxmachine/proc/cooldown_over()
	sendcooldown = 0

/obj/machinery/photocopier/faxmachine/ownership()
	. = ..()
	. += owns(nameof(scan), policy = OWN_CONTAINED)
