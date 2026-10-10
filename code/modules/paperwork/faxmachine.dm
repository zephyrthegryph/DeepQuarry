#define FAX_DEPARTMENT_EMPTY "No input found. Please hang up and try your call again."
#define FAX_PANEL_CLOSED "the service panel is closed"

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

/// Requirement (was REQ_* no_id_inserted): the legacy check answers TRUE to pass.
/obj/machinery/photocopier/faxmachine/proc/no_id_inserted_holds(datum/act/op/A)
	var/answer = no_id_inserted(A.actor, src, A.held)
	return !istext(answer) && !!answer

MSG_DEF_SELF(faxmachine/no_scan, "there is no ID card to remove")

/obj/machinery/photocopier/faxmachine/proc/interaction_open_ui_impl(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_OK

/// A silicon's touch logs it in under its own name and opens the window (borgs use fax machines: the Unity and Clerical modules).
/obj/machinery/photocopier/faxmachine/proc/silicon_open_ui(datum/act/op/A)
	authenticated = A.actor.name
	tgui_interact(A.actor)
	return OP_OK

/obj/machinery/photocopier/faxmachine/proc/interaction_remove_card(datum/act/op/A)
	var/mob/living/L = A.actor
	if(!isturf(L.loc) || L.restrained())
		return TRUE

	scan.forceMove(loc)
	if(ishuman(L) && !L.get_active_hand())
		L.put_in_hands(scan)
		rel_take(src, nameof(scan))
	authenticated = null
	return TRUE

MSG_DEF_SELF(fax/relays_recalibrating, "The global automated relays are still recalibrating. Try again later or relay your request in written form for processing.")

/// The staff request is open: the global relays are not recalibrating after the last request.
/obj/machinery/photocopier/faxmachine/proc/role_request_ready(datum/act/op/A)
	return !GLOB.last_fax_role_request || ELAPSED_SINCE(src, GLOB.last_fax_role_request, CLOCK_WORLD) >= 5 MINUTES

/// The jobs a fax may request (the talon's offmap crew on its own fax).
/obj/machinery/photocopier/faxmachine/proc/requestable_jobs(datum/act/A)
	. = list()
	for(var/datum/department/dept as anything in SSjob.get_all_department_datums())
		if(!src.talon)
			if(!dept.assignable || dept.centcom_only)
				continue
			for(var/job in SSjob.get_job_titles_in_department(dept.name))
				var/datum/job/J = SSjob.get_job(job)
				if(J.requestable)
					. |= job
		else
			for(var/job in SSjob.get_job_titles_in_department(dept.name))
				var/datum/job/J = SSjob.get_job(job)
				if(J.offmap_spawn)
					. |= job

/// Each later question opens only while the request is still going: the first was answered "Yes" and a job was picked.
/obj/machinery/photocopier/faxmachine/proc/request_confirmed(datum/act/op/A)
	return A.step_value("confirm") == "Yes"

/obj/machinery/photocopier/faxmachine/proc/request_role_picked(datum/act/op/A)
	return A.step_value("confirm") == "Yes" && A.step_value("role")

/// The reasons the picked job may be requested for.
/obj/machinery/photocopier/faxmachine/proc/request_reasons(datum/act/op/A)
	var/datum/job/job_to_request = SSjob.get_job(A.step_value("role"))
	. = list("Unspecified", "General duties", "Emergency situation")
	if(job_to_request)
		. += TYPE_TABLE_GET(job_to_request, get_request_reasons)

/obj/machinery/photocopier/faxmachine/proc/request_final_question(datum/act/op/A)
	return "You are about to request [A.step_value("role")]. Are you sure?"

/// The staff request form, after its four answers: the request pings the job's department.
/obj/machinery/photocopier/faxmachine/proc/role_request_sent(datum/act/op/A)
	var/mob/living/L = A.actor
	SStgui.update_uis(src)
	if(!istype(L) || !isturf(L.loc) || L.stat || L.restrained())
		return OP_OK
	if(A.step_value("confirm") != "Yes" || A.step_value("final") != "Yes")
		return OP_OK
	var/role = A.step_value("role")
	if(!role)
		return OP_OK
	var/reason = A.step_value("reason") || "Unspecified"
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
	return OP_OK

// The fax's window: the copier's buttons and its own. The paper title and the department are asked in their ops (asks()); sending a
// default-titled fax to an admin department asks whether to rename it first.
CAPABILITIES(/obj/machinery/photocopier/faxmachine)
	interface("Fax")
	without("ui_open")
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("login", ui_act("login", arg("login_type", num())), then(PROC_REF(ui_act_login)))
	op("logout", ui_act("logout"), then(PROC_REF(ui_act_logout)))
	// the staff request form: the window's button and the menu's verb, four questions, then the ping
	op("send_automated_staff_request", inputs(ui_act("send_automated_staff_request"), menu()), label("Staff Request Form"),
		needs(req_actor_kind(list(/mob/living/carbon/human, /mob/living/silicon), because = /datum/msg/req_failed), req_on_origin(ORIGIN_MENU | ORIGIN_VERB, req_adjacent()), req_bool(PROC_REF(role_request_ready), because = MSG(fax/relays_recalibrating))),
		asks(/datum/prompt/choice/fax_role_request, fields = list("question" = "Are you sure you want to send automated crew request?", "title" = "Confirmation", "choices" = list("Yes", "No", "Cancel"), "buttons" = TRUE), step = "confirm"),
		asks(/datum/prompt/choice/fax_role_request, fields = list("question" = "Pick the job to request.", "title" = "Job Request", "choices" = computed(PROC_REF(requestable_jobs)), "buttons" = FALSE), step = "role", when = PROC_REF(request_confirmed)),
		asks(/datum/prompt/choice/fax_role_request, fields = list("question" = "Pick request reason.", "title" = "Request reason", "choices" = computed(PROC_REF(request_reasons)), "buttons" = FALSE), step = "reason", when = PROC_REF(request_role_picked)),
		asks(/datum/prompt/choice/fax_role_request, fields = list("question" = computed(PROC_REF(request_final_question)), "title" = "Confirmation", "choices" = list("Yes", "No", "Cancel"), "buttons" = TRUE), step = "final", when = PROC_REF(request_role_picked)),
		then(PROC_REF(role_request_sent)))
	op("rename", ui_act("rename"), asks(/datum/prompt/text/fax_paper_title, fields = list("default" = computed(PROC_REF(paper_title_default))), step = "title", when = PROC_REF(can_title)),
		then(PROC_REF(ui_act_rename)))
	op("send", ui_act("send"),
		asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(default_title_question)), "title" = "Default name detected", "choices" = list("Change Title", "Continue", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "default_title", when = PROC_REF(default_title_to_admins)),
		asks(/datum/prompt/text, fields = list("question" = "Enter new fax title", "title" = "This will show up in the preview for staff chat on discord when sending to central.", "default" = computed(PROC_REF(paper_title_default)), "max_len" = MAX_NAME_LEN, "timeout" = 0), step = "new_title", when = PROC_REF(changing_title)),
		then(PROC_REF(ui_act_send)))
	op("dept", ui_act("dept"), asks(/datum/prompt/choice/fax_department, fields = list("choices" = computed(PROC_REF(department_choices))), step = "department", when = PROC_REF(fax_logged_in)),
		then(PROC_REF(ui_act_dept)))
	// behind the open service panel the multitool sets the department; with the panel shut it takes the click and does nothing
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Set department"), needs(req_bool(PROC_REF(maintenance_panel_open), silent = TRUE)),
		asks(/datum/prompt/text/fax_department_id, fields = list("default" = nameof(department))),
		then(PROC_REF(fax_department_id_answered)))
	op("faxmachine_insert_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Insert ID"), when(req_bool(PROC_REF(no_id_inserted_holds))), then(PROC_REF(interaction_insert_id)))
	op("faxmachine_insert_toner", item(/obj/item/toner), priority(OP_PRIORITY_DEFAULT - 1), label("Insert toner"), then(PROC_REF(interaction_insert_toner_impl)))
	op("faxmachine_open_ui_silicon", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), when(req_actor_kind(/mob/living/silicon)), label("Use"), then(PROC_REF(silicon_open_ui)))
	op("faxmachine_open_ui", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), then(PROC_REF(interaction_open_ui_impl)))
	op("faxmachine_remove_card", menu(), label("Remove ID card"), needs(req_adjacent(), req_capable(), req_actor_kind(list(/mob/living/carbon/human, /mob/living/silicon), because = /datum/msg/req_failed), req_is(nameof(scan), TRUE, because = MSG(faxmachine/no_scan))), then(PROC_REF(interaction_remove_card)))

/// The window data.
/obj/machinery/photocopier/faxmachine/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["authenticated"] = authenticated
	data["rank"] = rank
	data["copyItem"] = copyitem
	data["cooldown"] = sendcooldown
	data["destination"] = destination
	var/list/computed = ui_data_obj_machinery_photocopier_faxmachine(A.actor, null, null)
	for(var/key in computed)
		data[key] = computed[key]
	return data

/datum/prompt/choice/fax_role_request
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/fax_role_request/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/fax_role_request/refusal(given)
	return null

/// The computed part of the window data (ui_data()).
/obj/machinery/photocopier/faxmachine/proc/ui_data_obj_machinery_photocopier_faxmachine(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scan"] = scan ? scan.name : null
	data["isAI"] = isAI(user)
	data["isRobot"] = isrobot(user)
	data["adminDepartments"] = GLOB.admin_departments

	data["bossName"] = using_map.boss_name

	return data

/obj/machinery/photocopier/faxmachine/proc/ui_act_scan(datum/act/op/A)
	var/mob/user = A.actor
	if(scan)
		scan.forceMove(loc)
		if(ishuman(user) && !user.get_active_hand())
			user.put_in_hands(scan)
		rel_take(src, nameof(scan))
	else
		var/obj/item/I = user.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.scan), I, user)
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/ui_act_login(datum/act/op/A, login_type)
	var/mob/user = A.actor
	log_in_as(user, login_type)
	return TRUE

/// Logs the fax in under the card in it, or under a silicon's own identity (the login names who the operator is).
/obj/machinery/photocopier/faxmachine/proc/log_in_as(mob/user, login_type)
	if(login_type == LOGIN_TYPE_NORMAL && istype(scan))
		if(check_access(scan))
			authenticated = scan.registered_name
			rank = scan.assignment
	else if(login_type == LOGIN_TYPE_AI && isAI(user))
		authenticated = user.name
		rank = JOB_AI
	else if(login_type == LOGIN_TYPE_ROBOT && isrobot(user))
		authenticated = user.name
		var/mob/living/silicon/robot/R = user
		rank = "[R.modtype] [R.braintype]"

/obj/machinery/photocopier/faxmachine/proc/ui_act_logout(datum/act/op/A)
	var/mob/user = A.actor
	if(scan)
		scan.forceMove(loc)
		if(ishuman(user) && !user.get_active_hand())
			user.put_in_hands(scan)
		rel_take(src, nameof(scan))
	authenticated = null
	return TRUE

/obj/machinery/photocopier/faxmachine/ui_act_remove(datum/act/op/A)
	var/mob/user = A.actor
	if(copyitem)
		if(get_dist(user, src) >= 2)
			to_chat(user, "\The [copyitem] is too far away for you to remove it.")
			return
		copyitem.forceMove(loc)
		user.put_in_hands(copyitem)
		to_chat(user, span_notice("You take \the [copyitem] out of \the [src]."))
		rel_take(src, nameof(copyitem))
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/fax_logged_in(datum/act/op/A)
	return !!authenticated // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/obj/machinery/photocopier/faxmachine/proc/can_title(datum/act/op/A)
	return authenticated && copyitem // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/obj/machinery/photocopier/faxmachine/proc/paper_title_default(datum/act/op/A)
	return copyitem?.name

/obj/machinery/photocopier/faxmachine/proc/department_choices(datum/act/op/A)
	return GLOB.alldepartments + GLOB.admin_departments

/obj/machinery/photocopier/faxmachine/proc/ui_act_rename(datum/act/op/A)
	if(!can_title(A))
		return
	apply_paper_title(A.step_value("title"))
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/apply_paper_title(new_name)
	if(!authenticated)
		return
	if(copyitem)
		if(isnull(new_name))
			return
		if(!new_name)
			return
		copyitem.name = new_name
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/ui_act_send(datum/act/op/A)
	var/mob/user = A.actor
	if(!authenticated)
		return
	if(copyitem)
		if (destination in GLOB.admin_departments)
			if(default_title_to_admins(A))
				var/choice = A.step_value("default_title")
				if(!choice || choice == "Cancel")
					return TRUE
				if(choice == "Change Title")
					var/new_name = A.step_value("new_title")
					if(!new_name)
						return TRUE
					copyitem.name = new_name
			send_admin_fax(user, destination)
		else
			sendfax(destination, user)

		if (sendcooldown)
			after(src, sendcooldown, PROC_REF(cooldown_over))
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/ui_act_dept(datum/act/op/A)
	if(!authenticated)
		return
	apply_department_answer(A.step_value("department"))
	return TRUE

/obj/machinery/photocopier/faxmachine/proc/apply_department_answer(selected_department)
	if(!authenticated)
		return
	var/lastdestination = destination
	destination = selected_department
	if(!destination)
		destination = lastdestination
	return TRUE

/// Returns TRUE on "Cancel", an invalid newname or while the questions wait (their answers re-run the
/// send action with the same params), else returns null/false.
/// Extracted to its own procedure for easier logic handling with paper bundles.
/// Sending this fax to an admin department, under its default title (or a bundle under its first page's): the send asks to rename it.
/obj/machinery/photocopier/faxmachine/proc/default_title_to_admins(datum/act/op/A)
	if(!authenticated || !copyitem || !(destination in GLOB.admin_departments)) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens
		return FALSE
	if(istype(copyitem, /obj/item/paper_bundle))
		var/obj/item/paper_bundle/B = copyitem
		if(B.name != initial(B.name)) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens
			var/atom/page1 = B.pages[1] // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens
			var/atom/page2 = B.pages[2]
			return (istype(page1) && B.name == page1.name) || (istype(page2) && B.name == page2.name) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens
		return TRUE
	return copyitem.name == initial(copyitem.name)

/obj/machinery/photocopier/faxmachine/proc/default_title_question(datum/act/op/A)
	var/question_text = "Your fax is set to its default name. It's advisable to rename it to something self-explanatory to"
	if(istype(copyitem, /obj/item/paper_bundle) && copyitem.name != initial(copyitem.name))
		question_text = "Your fax is set to use the title of its first or second page. It's advisable to rename it to something \
			summarizing the entire bundle succintly to"
	return "[question_text] improve response time from staff when sending to discord. Renaming it changes its preview in staff chat."

/// The send asks for the new title after "Change Title".
/obj/machinery/photocopier/faxmachine/proc/changing_title(datum/act/op/A)
	return A.step_value("default_title") == "Change Title"

/obj/machinery/photocopier/faxmachine/proc/no_id_inserted(mob/actor, atom/target, obj/item/held)
	return !scan

/obj/machinery/photocopier/faxmachine/proc/interaction_insert_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	move_into(src, nameof(src.scan), held, user)
	return OP_OK

/obj/machinery/photocopier/faxmachine/proc/interaction_insert_toner_impl(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(toner <= 10) //allow replacing when low toner is affecting the print darkness
		if(!istype(held, /obj/item/toner))
			return OP_OK
		var/obj/item/toner/T = held
		var/refill_amount = T.toner_amount
		if(!consume(held, user))
			return OP_OK
		to_chat(user, span_notice("You insert the toner cartridge into \the [src]."))
		play_sfx(loc, SFX_MACHINES_CLICK)
		toner += refill_amount
	else
		to_chat(user, span_notice("This cartridge is not yet ready for replacement! Use up the rest of the toner."))
		play_sfx(loc, SFX_MACHINES_BUZZ_TWO, 1.5, vary = TRUE)
	return OP_OK

/// The multitool's answer: the fax's department (an empty answer changes nothing).
/obj/machinery/photocopier/faxmachine/proc/fax_department_id_answered(datum/act/op/A)
	var/input = A.answer?.value
	if(!input)
		to_chat(A.actor, FAX_DEPARTMENT_EMPTY)
		SStgui.update_uis(src)
		return OP_OK
	apply_department_id(input)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/photocopier/faxmachine/proc/apply_department_id(input)
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
	after(src, 2 SECONDS, PROC_REF(print_received), with = list(incoming))
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
	after(src, 5 SECONDS, TYPE_PROC_REF(/atom, visible_message), with = list("[src] beeps, \"Message transmitted successfully.\""))

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

/datum/prompt/text/fax_paper_title
	question = "Enter new paper title"
	title = "This will show up in the preview for staff chat on discord when sending to central."
	max_len = MAX_NAME_LEN
	name_text = TRUE
	timeout = 0

/datum/prompt/text/fax_paper_title/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/choice/fax_department
	question = "Which department?"
	title = "Choose a department"
	timeout = 0

/// The department the multitool's question asks for; answered only while the service panel is still open.
/datum/prompt/text/fax_department_id
	question = "What Department ID would you like to give this fax machine?"
	title = "Multitool-Fax Machine Interface"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/fax_department_id/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/fax_department_id/recheck_extra()
	var/obj/machinery/photocopier/faxmachine/fax = owner
	if(istype(fax) && !fax.panel_open)
		return FAX_PANEL_CLOSED
	return null

#undef FAX_DEPARTMENT_EMPTY
#undef FAX_PANEL_CLOSED
