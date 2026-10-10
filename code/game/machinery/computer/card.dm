//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/card
	name = "\improper ID card modification console"
	desc = "Terminal for programming employee ID cards to access parts of the station."
	icon_keyboard = "id_key"
	icon_screen = "id"
	light_color = "#0099ff"
	req_access = list(ACCESS_CHANGE_IDS)
	circuit = /obj/item/circuitboard/card
	var/obj/item/card/id/scan = null
	var/obj/item/card/id/modify = null
	mode = 0.0
	var/printing = FALSE

/obj/machinery/computer/card/proc/is_centcom()
	return 0

/obj/machinery/computer/card/proc/is_authenticated()
	return scan ? check_access(scan) : 0

/obj/machinery/computer/card/proc/get_target_rank()
	return modify && modify.assignment ? modify.assignment : "Unassigned"

/obj/machinery/computer/card/proc/format_jobs(list/jobs)
	var/list/formatted = list()
	for(var/job in jobs)
		formatted.Add(list(list(
			"display_name" = replacetext(job, " ", "&nbsp;"),
			"target_rank" = get_target_rank(),
			"job" = job)))

	return formatted

MSG_DEF_SELF(card_console/cannot_assign, "The console refuses: it needs an authenticated operator and a card to change.")
MSG_DEF_SELF(card_console/empty, "There is nothing to remove from the console.")
MSG_DEF(card_console/ejected, "You remove the card from %T%.", "")
MSG_DEF_SELF(card_console/no_log, "No log exists for that job.")
MSG_DEF_SELF(card_console/bad_name, "The console buzzes rudely: that is no name.")
MSG_DEF_SELF(card_console/slots_full, "Both card slots are full.")

TRACKED(/obj/machinery/computer/card, printing)

// The ID card modification console (doc/rewrite/final_api.html, sections 9, 13): an ID card used on it goes in (one with the change-IDs access
// is scanned as the operator's, any other is loaded to be changed) and opens the window; "Eject ID Card" gives back the operator's card, then
// the subject's. Every change to the loaded card needs an authenticated operator and a card (assign_possible()), and the card's name follows
// its owner and assignment after every button.
CAPABILITIES(/obj/machinery/computer/card)
	interface("IdentificationComputer")
	op("insert_id", item(/obj/item/card/id), needs(req(PROC_REF(has_free_slot), because = MSG(card_console/slots_full))), then(PROC_REF(card_inserted)), opens_ui())
	op("eject", menu(), label("Eject ID Card"), needs(req(PROC_REF(has_a_card), because = MSG(card_console/empty))), says(MSG(card_console/ejected)), then(PROC_REF(eject_first_card)))
	extend(TAG_UI, then(PROC_REF(refresh_card_name)))
	op("modify", ui_act("modify"), then(PROC_REF(ui_act_modify)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("access", ui_act("access", arg("access_target", num()), arg("allowed", num())), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign))), then(PROC_REF(ui_act_access)))
	op("assign", ui_act("assign", arg("assign_target", schema_text(4096))), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign)), req(PROC_REF(job_known), because = MSG(card_console/no_log))), then(PROC_REF(ui_act_assign)))
	op("assign_custom", ui_act("assign_custom"), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign))), asks(/datum/prompt/text, fields = list("title" = "Assignment", "question" = "Enter a custom job assignment.", "default" = "", "max_len" = 45)), then(PROC_REF(ui_act_assign_custom)))
	op("reg", ui_act("reg", arg("reg", schema_text(4096))), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign)), req(PROC_REF(name_valid), because = MSG(card_console/bad_name))), then(PROC_REF(ui_act_reg)))
	op("account", ui_act("account", arg("account", num())), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign))), then(PROC_REF(ui_act_account)))
	op("mode", ui_act("mode", arg("mode_target", num())), then(PROC_REF(ui_act_mode)))
	op("print", ui_act("print"), when(cond_not(nameof(printing))), then(PROC_REF(ui_act_print)))
	op("terminate", ui_act("terminate"), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign))), then(PROC_REF(ui_act_terminate)))

/// needs: a slot is free for the card (the operator's slot for a card with the access, else the subject's).
/obj/machinery/computer/card/proc/has_free_slot(datum/act/op/A)
	var/obj/item/card/id/I = A.held
	return istype(I) && (!modify || (!scan && (ACCESS_CHANGE_IDS in I.GetAccess())))

/// The offered card goes in: the operator's slot when it has the access and the slot is free, else the subject's.
/obj/machinery/computer/card/proc/card_inserted(datum/act/op/A)
	var/obj/item/card/id/I = A.held
	if(!scan && (ACCESS_CHANGE_IDS in I.GetAccess()))
		move_into(src, nameof(scan), I, A.actor)
	else
		move_into(src, nameof(modify), I, A.actor)
	return OP_OK

/// needs: a card is in the console.
/obj/machinery/computer/card/proc/has_a_card(datum/act/op/A)
	return scan || modify

/// "Eject ID Card": the operator's card, else the subject's, into the empty hand or onto the floor.
/obj/machinery/computer/card/proc/eject_first_card(datum/act/op/A)
	if(scan)
		give_back_scan(A.actor)
	else
		give_back_modify(A.actor)
	return OP_OK

/// The operator's card comes out, into a person's empty hand, else onto the floor.
/obj/machinery/computer/card/proc/give_back_scan(mob/user)
	var/obj/item/card/id/I = scan
	if(!I)
		return
	rel_take(src, nameof(scan))
	hand_over(user, I)

/// The subject's card comes out, into a person's empty hand, else onto the floor.
/obj/machinery/computer/card/proc/give_back_modify(mob/user)
	var/obj/item/card/id/I = modify
	if(!I)
		return
	rel_take(src, nameof(modify))
	hand_over(user, I)

/obj/machinery/computer/card/proc/hand_over(mob/user, obj/item/card/id/I)
	I.forceMove(get_turf(src))
	if(ishuman(user) && !user.get_active_hand())
		user.put_in_hands(I)

/// After any button: the loaded card's name follows its owner and assignment.
/obj/machinery/computer/card/proc/refresh_card_name(datum/act/op/A)
	modify?.update_name()
	return OP_OK

/obj/machinery/computer/card/tgui_static_data(mob/user)
	var/list/data =  ..()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data

/obj/machinery/computer/card/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["printing"] = printing

	data["station_name"] = station_name()
	data["mode"] = mode
	data["target_name"] = modify ? modify.name : "-----"
	data["target_owner"] = modify && modify.registered_name ? modify.registered_name : "-----"
	data["target_rank"] = get_target_rank()
	data["scan_name"] = scan ? scan.name : "-----"
	data["authenticated"] = is_authenticated()
	data["has_modify"] = !!modify
	data["account_number"] = modify ? modify.associated_account_number : null
	data["centcom_access"] = is_centcom()
	data["all_centcom_access"] = null
	data["regions"] = null
	data["id_rank"] = modify && modify.assignment ? modify.assignment : "Unassigned"

	var/list/departments = list()
	for(var/datum/department/dept as anything in SSjob.get_all_department_datums())
		if(!dept.assignable) // No AI ID cards for you.
			continue
		if(dept.centcom_only && !is_centcom())
			continue
		departments.Add(list(list(
			"department_name" = dept.name,
			"jobs" = format_jobs(SSjob.get_job_titles_in_department(dept.name))
		)))
	data["departments"] = departments

	var/list/all_centcom_access = list()
	var/list/regions = list()
	if(modify && is_centcom())
		for(var/access in SSaccess.get_all_centcom_access())
			all_centcom_access.Add(list(list(
				"desc" = replacetext(SSaccess.get_centcom_access_desc(access), " ", "&nbsp;"),
				"ref" = access,
				"allowed" = (access in modify.GetAccess()) ? 1 : 0)))
	else if(modify)
		for(var/i in ACCESS_REGION_SECURITY to ACCESS_REGION_SUPPLY)
			var/list/accesses = list()
			for(var/access in SSaccess.get_region_accesses(i))
				if (SSaccess.get_access_desc(access))
					accesses.Add(list(list(
						"desc" = replacetext(SSaccess.get_access_desc(access), " ", "&nbsp;"),
						"ref" = access,
						"allowed" = (access in modify.GetAccess()) ? 1 : 0)))

			regions.Add(list(list(
				"name" = SSaccess.get_region_accesses_name(i),
				"accesses" = accesses)))

	data["regions"] = regions
	data["all_centcom_access"] = all_centcom_access

	return data

/// The subject's slot: a loaded card goes back (the manifest notes its changes), else the card in the hand goes in.
/obj/machinery/computer/card/proc/ui_act_modify(datum/act/op/A)
	if(modify)
		GLOB.data_core.manifest_modify(modify.registered_name, modify.assignment, modify.rank)
		modify.update_name()
		give_back_modify(A.actor)
		return OP_OK
	var/obj/item/I = A.actor.get_active_hand()
	if(istype(I, /obj/item/card/id))
		move_into(src, nameof(modify), I, A.actor)
	return OP_OK

/// The operator's slot: a scanned card goes back, else the card in the hand is scanned.
/obj/machinery/computer/card/proc/ui_act_scan(datum/act/op/A)
	if(scan)
		give_back_scan(A.actor)
		return OP_OK
	var/obj/item/I = A.actor.get_active_hand()
	if(istype(I, /obj/item/card/id))
		move_into(src, nameof(scan), I, A.actor)
	return OP_OK

/// An access of the console's set flips on the loaded card (`allowed`: the card has it now).
/obj/machinery/computer/card/proc/ui_act_access(datum/act/op/A, access_target, allowed)
	if(access_target in (is_centcom() ? SSaccess.get_all_centcom_access() : SSaccess.get_all_station_access()))
		modify.access -= access_target
		if(!allowed)
			modify.access += access_target
	return OP_OK

/// needs: the job has a log (a CentCom console takes any of its own titles).
/obj/machinery/computer/card/proc/job_known(datum/act/op/A)
	return is_centcom() || !!SSjob.get_job(A.args["assign_target"])

/// The loaded card takes the job: its access, assignment and rank.
/obj/machinery/computer/card/proc/ui_act_assign(datum/act/op/A, assign_target)
	var/datum/job/J = SSjob.get_job(assign_target)
	modify.access = is_centcom() ? SSaccess.get_centcom_access(assign_target) : J.get_access()
	modify.assignment = assign_target
	modify.rank = assign_target
	return OP_OK

/// needs: the name typed is a name.
/obj/machinery/computer/card/proc/name_valid(datum/act/op/A)
	return !!sanitizeName(A.args["reg"])

/obj/machinery/computer/card/proc/ui_act_reg(datum/act/op/A, reg)
	modify.registered_name = sanitizeName(reg)
	return OP_OK

/obj/machinery/computer/card/proc/ui_act_account(datum/act/op/A, account)
	modify.associated_account_number = account
	return OP_OK

/obj/machinery/computer/card/proc/ui_act_mode(datum/act/op/A, mode_target)
	set_mode(mode_target)
	return OP_OK

/// The printer starts: the manifest or the access report comes out five seconds later.
/obj/machinery/computer/card/proc/ui_act_print(datum/act/op/A)
	set_printing(TRUE)
	after(src, 5 SECONDS, PROC_REF(finish_printing), key = "printing")
	return OP_OK

/// The loaded card's owner is dismissed: no assignment, no access.
/obj/machinery/computer/card/proc/ui_act_terminate(datum/act/op/A)
	modify.assignment = "Dismissed"
	modify.access = list()
	return OP_OK

/// The operator is authenticated and a card is loaded.
/obj/machinery/computer/card/proc/assign_possible(datum/act/op/A)
	return is_authenticated() && modify

/// A custom assignment, typed: it works as an impromptu alt title, mainly for sechuds.
/obj/machinery/computer/card/proc/ui_act_assign_custom(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/temp_t = R?.value
	if(temp_t && modify && is_authenticated())
		modify.assignment = temp_t
	return OP_OK

/obj/machinery/computer/card/centcom
	name = "\improper CentCom ID card modification console"
	circuit = /obj/item/circuitboard/card/centcom
	req_access = list(ACCESS_CENT_CAPTAIN)

/obj/machinery/computer/card/centcom/is_centcom()
	return 1

/obj/machinery/computer/card/proc/finish_printing()
	set_printing(FALSE)

	var/obj/item/paper/P = new(loc)
	if(mode)
		P.name = text("crew manifest ([])", stationtime2text())
		P.set_info({"<h4>Crew Manifest</h4>
			<br>
			[GLOB.data_core ? GLOB.data_core.get_manifest(0) : ""]
		"})
	else if(modify)
		P.name = "access report"
		P.set_info({"<h4>Access Report</h4>
			<u>Prepared By:</u> [scan?.registered_name || "Unknown"]<br>
			<u>For:</u> [modify.registered_name ? modify.registered_name : "Unregistered"]<br>
			<hr>
			<u>Assignment:</u> [modify.assignment]<br>
			<u>Account Number:</u> #[modify.associated_account_number]<br>
			<u>Blood Type:</u> [modify.blood_type]<br><br>
			<u>Access:</u><br>
		"})

		for(var/A in modify.access)
			P.set_info(P.info + ("  [SSaccess.get_access_desc(A)]"))

/obj/machinery/computer/card/ownership()
	. = ..()
	. += owns(nameof(scan), policy = OWN_CONTAINED)
	. += owns(nameof(modify), policy = OWN_CONTAINED)
