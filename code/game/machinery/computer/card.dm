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
	var/printing = null

/obj/machinery/computer/card/proc/is_centcom()
	return 0

/obj/machinery/computer/card/proc/is_authenticated()
	return scan ? check_access(scan) : 0 // ALLOW(reads): the scanned card is asked when the button is pressed and again when the answer arrives, never cached

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

/obj/machinery/computer/card/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/card_insert_id,
		/datum/interaction/machine_verb/card_eject_id,
		/datum/interaction/machine_hand/card_open_ui,
	)
	..()

/// Old attackby: an ID card scanned or set to be modified.
/datum/interaction/machine_item/card_insert_id
	id = "card_insert_id"
	name = "Insert ID"
	held_type = /obj/item/card/id
	effect = /obj/machinery/computer/card/proc/interaction_insert_id

/obj/machinery/computer/card/proc/interaction_insert_id(mob/user, obj/item/card/id/id_card, datum/interaction/interaction)
	if(!scan && (ACCESS_CHANGE_IDS in id_card.GetAccess()))
		move_into(src, nameof(src.scan), id_card, user)
	else if(!modify)
		move_into(src, nameof(src.modify), id_card, user)

	SStgui.update_uis(src)
	attack_hand(user)
	return TRUE

/// Old object verb.
/datum/interaction/machine_verb/card_eject_id
	id = "card_eject_id"
	name = "Eject ID Card"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/computer/card/proc/interaction_eject_id

/obj/machinery/computer/card/proc/interaction_eject_id(mob/user, obj/item/held, datum/interaction/interaction)
	if(scan)
		to_chat(user, "You remove \the [scan] from \the [src].")
		scan.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(scan)
		own_take(src, nameof(scan))
	else if(modify)
		to_chat(user, "You remove \the [modify] from \the [src].")
		modify.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(modify)
		own_take(src, nameof(modify))
	else
		to_chat(user, "There is nothing to remove from the console.")
	return TRUE

/// Old attack_hand: `if(..()) return; if(stat & (NOPOWER|BROKEN)) return; tgui_interact(user)`.
/datum/interaction/machine_hand/card_open_ui
	id = "card_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/card/proc/interaction_open_ui_impl

/obj/machinery/computer/card/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/card)
	interface("IdentificationComputer")
	op("modify", ui_act("modify"), then(PROC_REF(ui_act_modify)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("access", ui_act("access", arg("access_target", num()), arg("allowed", num())), then(PROC_REF(ui_act_access)))
	op("assign", ui_act("assign", arg("assign_target", schema_text(4096))), then(PROC_REF(ui_act_assign)))
	op("assign_custom", ui_act("assign_custom"), needs(req(PROC_REF(assign_possible), because = MSG(card_console/cannot_assign))), asks(/datum/prompt/text, fields = list("title" = "Assignment", "question" = "Enter a custom job assignment.", "default" = "", "max_len" = 45)), then(PROC_REF(ui_act_assign_custom)))
	op("reg", ui_act("reg", arg("reg", schema_text(4096))), then(PROC_REF(ui_act_reg)))
	op("account", ui_act("account", arg("account", num())), then(PROC_REF(ui_act_account)))
	op("mode", ui_act("mode", arg("mode_target", num())), then(PROC_REF(ui_act_mode)))
	op("print", ui_act("print"), then(PROC_REF(ui_act_print)))
	op("terminate", ui_act("terminate"), then(PROC_REF(ui_act_terminate)))

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

/obj/machinery/computer/card/proc/ui_act_modify(datum/act/op/A)
	if(modify)
		GLOB.data_core.manifest_modify(modify.registered_name, modify.assignment, modify.rank)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"
		if(ishuman(A.actor))
			modify.forceMove(get_turf(src))
			if(!A.actor.get_active_hand())
				A.actor.put_in_hands(modify)
			own_take(src, nameof(/obj/machinery/computer/card::modify))
		else
			modify.forceMove(get_turf(src))
			own_take(src, nameof(/obj/machinery/computer/card::modify))
	else
		var/obj/item/I = A.actor.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.modify), I, A.actor)
	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_scan(datum/act/op/A)
	if(scan)
		if(ishuman(A.actor))
			scan.forceMove(get_turf(src))
			if(!A.actor.get_active_hand())
				A.actor.put_in_hands(scan)
			own_take(src, nameof(/obj/item/extrapolator::scan))
		else
			scan.forceMove(get_turf(src))
			own_take(src, nameof(/obj/item/extrapolator::scan))
	else
		var/obj/item/I = A.actor.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.scan), I, A.actor)
	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_access(datum/act/op/A, access_target, allowed)
	if(is_authenticated())
		var/access_type = access_target
		var/access_allowed = allowed
		if(access_type in (is_centcom() ? SSaccess.get_all_centcom_access() : SSaccess.get_all_station_access()))
			modify.access -= access_type
			if(!access_allowed)
				modify.access += access_type
	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_assign(datum/act/op/A, assign_target)
	if(is_authenticated() && modify)
		var/t1 = assign_target
		var/list/access = list()
		if(is_centcom())
			access = SSaccess.get_centcom_access(t1)
		else
			var/datum/job/jobdatum = SSjob.get_job(t1)
			if(!jobdatum)
				to_chat(A.actor, span_warning("No log exists for this job: [t1]"))
				return
			access = jobdatum.get_access()

		modify.access = access
		modify.assignment = t1
		modify.rank = t1

	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_reg(datum/act/op/A, reg)
	if(is_authenticated())
		var/temp_name = sanitizeName(reg)
		if(temp_name)
			modify.registered_name = temp_name
		else
			visible_message(span_notice("[src] buzzes rudely."))
	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_account(datum/act/op/A, account)
	if(is_authenticated())
		var/account_num = account
		modify.associated_account_number = account_num
	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_mode(datum/act/op/A, mode_target)
	set_mode(mode_target)
	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_print(datum/act/op/A)
	if(!printing)
		printing = 1
		after(src, 5 SECONDS, PROC_REF(finish_printing))
		. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/proc/ui_act_terminate(datum/act/op/A)
	if(is_authenticated())
		modify.assignment = "Dismissed" // setting adjustment
		modify.access = list()

	. = TRUE
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/// The operator is authenticated and a card is loaded.
/obj/machinery/computer/card/proc/assign_possible(datum/act/op/A)
	return is_authenticated() && modify // ALLOW(reads): the loaded card is asked when the button is pressed, never cached

/// A custom assignment, typed: it works as an impromptu alt title, mainly for sechuds.
/obj/machinery/computer/card/proc/ui_act_assign_custom(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/temp_t = R?.value
	if(temp_t && modify && is_authenticated())
		modify.assignment = temp_t
	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"
	return OP_OK

MSG_DEF_SELF(card_console/cannot_assign, "The console refuses: it needs an authenticated operator and a card to change.")

/obj/machinery/computer/card/centcom
	name = "\improper CentCom ID card modification console"
	circuit = /obj/item/circuitboard/card/centcom
	req_access = list(ACCESS_CENT_CAPTAIN)

/obj/machinery/computer/card/centcom/is_centcom()
	return 1

/obj/machinery/computer/card/proc/finish_printing()
	printing = null
	SStgui.update_uis(src)

	var/obj/item/paper/P = new(loc)
	if(mode)
		P.name = text("crew manifest ([])", stationtime2text())
		P.info = {"<h4>Crew Manifest</h4>
			<br>
			[GLOB.data_core ? GLOB.data_core.get_manifest(0) : ""]
		"}
	else if(modify)
		P.name = "access report"
		P.info = {"<h4>Access Report</h4>
			<u>Prepared By:</u> [scan.registered_name ? scan.registered_name : "Unknown"]<br>
			<u>For:</u> [modify.registered_name ? modify.registered_name : "Unregistered"]<br>
			<hr>
			<u>Assignment:</u> [modify.assignment]<br>
			<u>Account Number:</u> #[modify.associated_account_number]<br>
			<u>Blood Type:</u> [modify.blood_type]<br><br>
			<u>Access:</u><br>
		"}

		for(var/A in modify.access)
			P.info += "  [SSaccess.get_access_desc(A)]"

/obj/machinery/computer/card/ownership()
	. = ..()
	. += owns(nameof(scan), policy = OWN_CONTAINED)
	. += owns(nameof(modify), policy = OWN_CONTAINED)
