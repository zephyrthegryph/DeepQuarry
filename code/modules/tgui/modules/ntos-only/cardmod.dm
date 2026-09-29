// This really should be used for both regular ID computers and NTOS, but
// the data structures are just different enough right now that I can't be assed
/datum/tgui_module/cardmod
	name = "ID card modification program"
	ntos = TRUE
	tgui_id = "IdentificationComputer"
	var/mod_mode = 1
	var/is_centcom = 0

/datum/tgui_module/cardmod/tgui_static_data(mob/user)
	var/list/data =  ..()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data

UI_DATA(/datum/tgui_module/cardmod, "mode=mod_mode:num", "centcom_access=is_centcom:num", "merge:ui_data_datum_tgui_module_cardmod{station_name:text,printing:bool,have_id_slot:num,have_printer:num,authenticated:unknown,has_modify:bool,account_number:num,id_rank:text,target_owner:text,target_name:text,departments:list,all_centcom_access:list,regions:list}")

/// The computed part of /datum/tgui_module/cardmod's window data (declared on its UI_DATA row).
/datum/tgui_module/cardmod/proc/ui_data_datum_tgui_module_cardmod(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/datum/computer_file/program/card_mod/program = host()
	if(!istype(program))
		return 0
	var/list/data = list()
	data["station_name"] = station_name()
	data["printing"] = FALSE
	if(program && program.computer())
		data["have_id_slot"] = !!program.computer().card_slot
		data["have_printer"] = !!program.computer().nano_printer
		data["authenticated"] = program.can_run(user)
		if(!program.computer().card_slot)
			mod_mode = 0 //We can't modify IDs when there is no card reader
	else
		data["have_id_slot"] = 0
		data["have_printer"] = 0
		data["authenticated"] = 0


	data["has_modify"] = null
	data["account_number"] = null
	data["id_rank"] = null
	data["target_owner"] = null
	data["target_name"] = null
	if(program && program.computer() && program.computer().card_slot)
		var/obj/item/card/id/id_card = program.computer().card_slot.stored_card()
		data["has_modify"] = !!id_card
		data["account_number"] = id_card ? id_card.associated_account_number : null
		data["id_rank"] = id_card && id_card.assignment ? id_card.assignment : "Unassigned"
		data["target_owner"] = id_card && id_card.registered_name ? id_card.registered_name : "-----"
		data["target_name"] = id_card ? id_card.name : "-----"

	var/list/departments = list()
	for(var/datum/department/dept as anything in SSjob.get_all_department_datums())
		if(!dept.assignable) // No AI ID cards for you.
			continue
		if(dept.centcom_only && !is_centcom)
			continue
		departments.Add(list(list(
			"department_name" = dept.name,
			"jobs" = format_jobs(SSjob.get_job_titles_in_department(dept.name)),
		)))

	data["departments"] = departments

	var/list/all_centcom_access = list()
	var/list/regions = list()
	if(program.computer().card_slot && program.computer().card_slot.stored_card())
		var/obj/item/card/id/id_card = program.computer().card_slot.stored_card()
		if(is_centcom)
			for(var/access in SSaccess.get_all_centcom_access())
				all_centcom_access.Add(list(list(
					"desc" = replacetext(SSaccess.get_centcom_access_desc(access), " ", "&nbsp;"),
					"ref" = access,
					"allowed" = (access in id_card.GetAccess()) ? 1 : 0)))
			data["all_centcom_access"] = all_centcom_access
		else
			for(var/i in ACCESS_REGION_SECURITY to ACCESS_REGION_SUPPLY)
				var/list/accesses = list()
				for(var/access in SSaccess.get_region_accesses(i))
					if(SSaccess.get_access_desc(access))
						accesses.Add(list(list(
							"desc" = replacetext(SSaccess.get_access_desc(access), " ", "&nbsp;"),
							"ref" = access,
							"allowed" = (access in id_card.GetAccess()) ? 1 : 0)))

				regions.Add(list(list(
					"name" = SSaccess.get_region_accesses_name(i),
					"accesses" = accesses)))
			data["regions"] = regions

	data["regions"] = regions
	data["all_centcom_access"] = all_centcom_access

	return data

/datum/tgui_module/cardmod/proc/format_jobs(list/jobs)
	var/datum/computer_file/program/card_mod/program = host()
	if(!istype(program))
		return null

	var/obj/item/card/id/id_card = program.computer().card_slot ? program.computer().card_slot.stored_card() : null
	var/list/formatted = list()
	for(var/job in jobs)
		formatted.Add(list(list(
			"display_name" = replacetext(job, " ", "&nbsp;"),
			"target_rank" = id_card && id_card.assignment ? id_card.assignment : "Unassigned",
			"job" = job)))

	return formatted

/datum/tgui_module/cardmod/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	if(!istype(program))
		return FALSE
	if(!istype(computer))
		return FALSE
	return TRUE

UI_ACT(/datum/tgui_module/cardmod, "mode", ui_act_mode, UI_ARG_NUM("mode_target", 0, 1))
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_mode)
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	mod_mode = params["mode_target"]
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "print", ui_act_print)
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_print)
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/user_id_card = ui.user.GetIdCard()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && computer.nano_printer) //This option should never be called if there is no printer
		if(!mod_mode)
			if(program.can_run(ui.user, 1))
				var/report_text = {"<h4>Access Report</h4>
							<u>Prepared By:</u> [user_id_card.registered_name ? user_id_card.registered_name : "Unknown"]<br>
							<u>For:</u> [id_card.registered_name ? id_card.registered_name : "Unregistered"]<br>
							<hr>
							<u>Assignment:</u> [id_card.assignment]<br>
							<u>Account Number:</u> #[id_card.associated_account_number]<br>
							<u>Blood Type:</u> [id_card.blood_type]<br><br>
							<u>Access:</u><br>
						"}

				var/known_access_rights = SSaccess.get_access_ids(ACCESS_TYPE_STATION|ACCESS_TYPE_CENTCOM)
				for(var/A in id_card.GetAccess())
					if(A in known_access_rights)
						report_text += "  [SSaccess.get_access_desc(A)]"

				if(!computer.nano_printer.print_text(report_text,"access report"))
					to_chat(ui.user, span_notice("Hardware error: Printer was unable to print the file. It may be out of paper."))
					return
				else
					computer.visible_message(span_bold("\The [computer]") + " prints out paper.")
		else
			var/report_text = {"<h4>Crew Manifest</h4>
							<br>
							[GLOB.data_core ? GLOB.data_core.get_manifest(0) : ""]
							"}
			if(!computer.nano_printer.print_text(report_text,text("crew manifest ([])", stationtime2text())))
				to_chat(ui.user, span_notice("Hardware error: Printer was unable to print the file. It may be out of paper."))
				return
			else
				computer.visible_message(span_bold("\The [computer]") + " prints out paper.")
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "modify", ui_act_modify)
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_modify)
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && computer.card_slot)
		if(id_card)
			GLOB.data_core.manifest_modify(id_card.registered_name, id_card.assignment, id_card.rank)
		computer.proc_eject_id(ui.user)
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "terminate", ui_act_terminate)
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_terminate)
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(ui.user, 1) && id_card)
		id_card.assignment = "Dismissed" // setting adjustment
		id_card.access = list()
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "reg", ui_act_reg, UI_ARG_TEXT("reg"))
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_reg)
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(ui.user, 1) && id_card)
		var/temp_name = sanitizeName(params["reg"], allow_numbers = TRUE)
		if(temp_name)
			id_card.registered_name = temp_name
		else
			computer.visible_message(span_notice("[computer] buzzes rudely."))
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "account", ui_act_account, UI_ARG_NUM("account"))
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_account)
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(ui.user, 1) && id_card)
		var/account_num = params["account"]
		id_card.associated_account_number = account_num
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "assign", ui_act_assign, UI_ARG_TEXT("assign_target"))
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_assign)
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(ui.user, 1) && id_card)
		var/t1 = params["assign_target"]
		if(t1 == "Custom")
			var/temp_t = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Enter a custom job assignment.", title = "Assignment", default = id_card.assignment, max_length = 45)
			if(isnull(temp_t))
				return
			//let custom jobs function as an impromptu alt title, mainly for sechuds
			if(temp_t)
				id_card.assignment = temp_t
		else
			var/list/access = list()
			if(is_centcom)
				access = SSaccess.get_centcom_access(t1)
			else
				var/datum/job/jobdatum
				for(var/jobtype in typesof(/datum/job))
					var/datum/job/J = new jobtype
					if(ckey(J.title) == ckey(t1))
						jobdatum = J
						break
				if(!jobdatum)
					to_chat(ui.user, span_warning("No log exists for this job: [t1]"))
					return

				access = jobdatum.get_access()

			id_card.access = access
			id_card.assignment = t1
			id_card.rank = t1

	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

UI_ACT(/datum/tgui_module/cardmod, "access", ui_act_access, UI_ARG_NUM("access_target"), UI_ARG_NUM("allowed"))
UI_ACT_PROC(/datum/tgui_module/cardmod, ui_act_access)
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(ui.user, 1) && id_card)
		var/access_type = params["access_target"]
		var/access_allowed = params["allowed"]
		if(access_type in SSaccess.get_access_ids(ACCESS_TYPE_STATION|ACCESS_TYPE_CENTCOM))
			id_card.access -= access_type
			if(!access_allowed)
				id_card.access += access_type
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")
