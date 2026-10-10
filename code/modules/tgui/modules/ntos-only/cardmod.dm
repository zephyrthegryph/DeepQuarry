// This really should be used for both regular ID computers and NTOS, but
// the data structures are just different enough right now that I can't be assed
/datum/tgui_module/cardmod
	name = "ID card modification program"
	ntos = TRUE
	var/mod_mode = 1
	var/is_centcom = 0

/datum/tgui_module/cardmod/tgui_static_data(mob/user)
	var/list/data =  ..()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data

CAPABILITIES(/datum/tgui_module/cardmod)
	extend(TAG_UI, needs(req_bool(PROC_REF(ui_gate), silent = TRUE)))
	interface("IdentificationComputer")
	op("mode", ui_act("mode", arg("mode_target", num(0, 1))), then(PROC_REF(ui_act_mode)))
	op("print", ui_act("print"), then(PROC_REF(ui_act_print)))
	op("modify", ui_act("modify"), then(PROC_REF(ui_act_modify)))
	op("terminate", ui_act("terminate"), then(PROC_REF(ui_act_terminate)))
	op("reg", ui_act("reg", arg("reg", schema_text(4096))), then(PROC_REF(ui_act_reg)))
	op("account", ui_act("account", arg("account", num())), then(PROC_REF(ui_act_account)))
	op("assign", ui_act("assign", arg("assign_target", schema_text(4096))), asks(/datum/prompt/text, fields = list("title" = "Assignment", "question" = "Enter a custom job assignment.", "default" = computed(PROC_REF(assign_default)), "max_len" = 45), when = PROC_REF(assign_is_custom)), then(PROC_REF(ui_act_assign)))
	op("access", ui_act("access", arg("access_target", num()), arg("allowed", num())), then(PROC_REF(ui_act_access)))

/datum/tgui_module/cardmod/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	if(!istype(program))
		return 0
	var/list/data = list()
	data["mode"] = mod_mode
	data["centcom_access"] = is_centcom
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

/// The program runs on a computer: anything else is silently not answered.
/datum/tgui_module/cardmod/proc/ui_gate(datum/act/op/A)
	return istype(host(), /datum/computer_file/program/card_mod) && istype(tgui_host(), /obj/item/modular_computer)

/// The "Custom" assignment asks for a text first; the others are picked from the list.
/datum/tgui_module/cardmod/proc/assign_is_custom(datum/act/op/A)
	return A.args["assign_target"] == "Custom"

/datum/tgui_module/cardmod/proc/assign_default(datum/act/op/A)
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card = computer?.card_slot?.stored_card()
	return id_card?.assignment

/datum/tgui_module/cardmod/proc/ui_act_mode(datum/act/op/A, mode_target)
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	mod_mode = mode_target
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_print(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/user_id_card = user.GetIdCard()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && computer.nano_printer) //This option should never be called if there is no printer
		if(!mod_mode)
			if(program.can_run(user, 1))
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
				for(var/A2 in id_card.GetAccess())
					if(A2 in known_access_rights)
						report_text += "  [SSaccess.get_access_desc(A2)]"

				if(!computer.nano_printer.print_text(report_text,"access report"))
					to_chat(user, span_notice("Hardware error: Printer was unable to print the file. It may be out of paper."))
					return
				else
					computer.visible_message(span_bold("\The [computer]") + " prints out paper.")
		else
			var/report_text = {"<h4>Crew Manifest</h4>
							<br>
							[GLOB.data_core ? GLOB.data_core.get_manifest(0) : ""]
							"}
			if(!computer.nano_printer.print_text(report_text,text("crew manifest ([])", stationtime2text())))
				to_chat(user, span_notice("Hardware error: Printer was unable to print the file. It may be out of paper."))
				return
			else
				computer.visible_message(span_bold("\The [computer]") + " prints out paper.")
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_modify(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && computer.card_slot)
		if(id_card)
			GLOB.data_core.manifest_modify(id_card.registered_name, id_card.assignment, id_card.rank)
		computer.proc_eject_id(user)
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_terminate(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(user, 1) && id_card)
		id_card.assignment = "Dismissed" // setting adjustment
		id_card.access = list()
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_reg(datum/act/op/A, reg)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(user, 1) && id_card)
		var/temp_name = sanitizeName(reg, allow_numbers = TRUE)
		if(temp_name)
			id_card.registered_name = temp_name
		else
			computer.visible_message(span_notice("[computer] buzzes rudely."))
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_account(datum/act/op/A, account)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(user, 1) && id_card)
		var/account_num = account
		id_card.associated_account_number = account_num
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_assign(datum/act/op/A, assign_target)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(user, 1) && id_card)
		var/t1 = assign_target
		if(t1 == "Custom")
			var/datum/prompt/P = A.answer
			var/temp_t = P?.value
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
					to_chat(user, span_warning("No log exists for this job: [t1]"))
					return

				access = jobdatum.get_access()

			id_card.access = access
			id_card.assignment = t1
			id_card.rank = t1

	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")

/datum/tgui_module/cardmod/proc/ui_act_access(datum/act/op/A, access_target, allowed)
	var/mob/user = A.actor
	var/datum/computer_file/program/card_mod/program = host()
	var/obj/item/modular_computer/computer = tgui_host()
	var/obj/item/card/id/id_card
	if(computer.card_slot)
		id_card = computer.card_slot.stored_card()
	if(computer && program.can_run(user, 1) && id_card)
		var/access_type = access_target
		var/access_allowed = allowed
		if(access_type in SSaccess.get_access_ids(ACCESS_TYPE_STATION|ACCESS_TYPE_CENTCOM))
			id_card.access -= access_type
			if(!access_allowed)
				id_card.access += access_type
	. = TRUE
	if(id_card)
		id_card.name = text("[id_card.registered_name]'s ID Card ([id_card.assignment])")
