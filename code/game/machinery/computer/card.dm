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
	var/mode = 0.0
	var/printing = null

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
	if(!scan && (ACCESS_CHANGE_IDS in id_card.GetAccess()) && (user.unEquip(id_card) || (id_card.loc == user && istype(user,/mob/living/silicon/robot)))) //Grippers. Again. ~Mechoid
		user.drop_item()
		id_card.forceMove(src)
		scan = id_card
	else if(!modify)
		user.drop_item()
		id_card.forceMove(src)
		modify = id_card

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
		scan = null
	else if(modify)
		to_chat(user, "You remove \the [modify] from \the [src].")
		modify.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(modify)
		modify = null
	else
		to_chat(user, "There is nothing to remove from the console.")
	return TRUE

/// Old attack_hand: `if(..()) return; if(stat & (NOPOWER|BROKEN)) return; tgui_interact(user)`.
/datum/interaction/machine_hand/card_open_ui
	id = "card_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/card/proc/interaction_open_ui_impl

/obj/machinery/computer/card/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat & (NOPOWER|BROKEN))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/card/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "IdentificationComputer", name)
		ui.open()

/obj/machinery/computer/card/tgui_static_data(mob/user)
	var/list/data =  ..()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data

/obj/machinery/computer/card/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["station_name"] = station_name()
	data["mode"] = mode
	data["printing"] = printing
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

/obj/machinery/computer/card/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("modify")
			if(modify)
				GLOB.data_core.manifest_modify(modify.registered_name, modify.assignment, modify.rank)
				modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"
				if(ishuman(ui.user))
					modify.forceMove(get_turf(src))
					if(!ui.user.get_active_hand())
						ui.user.put_in_hands(modify)
					modify = null
				else
					modify.forceMove(get_turf(src))
					modify = null
			else
				var/obj/item/I = ui.user.get_active_hand()
				if(istype(I, /obj/item/card/id) && ui.user.unEquip(I))
					I.forceMove(src)
					modify = I
			. = TRUE

		if("scan")
			if(scan)
				if(ishuman(ui.user))
					scan.forceMove(get_turf(src))
					if(!ui.user.get_active_hand())
						ui.user.put_in_hands(scan)
					scan = null
				else
					scan.forceMove(get_turf(src))
					scan = null
			else
				var/obj/item/I = ui.user.get_active_hand()
				if(istype(I, /obj/item/card/id))
					ui.user.drop_item()
					I.forceMove(src)
					scan = I
			. = TRUE

		if("access")
			if(is_authenticated())
				var/access_type = text2num(params["access_target"])
				var/access_allowed = text2num(params["allowed"])
				if(access_type in (is_centcom() ? SSaccess.get_all_centcom_access() : SSaccess.get_all_station_access()))
					modify.access -= access_type
					if(!access_allowed)
						modify.access += access_type
			. = TRUE

		if("assign")
			if(is_authenticated() && modify)
				var/t1 = params["assign_target"]
				if(t1 == "Custom")
					var/temp_t = tgui_input_text(ui.user, "Enter a custom job assignment.","Assignment", "", 45)
					//let custom jobs function as an impromptu alt title, mainly for sechuds
					if(temp_t && modify)
						modify.assignment = temp_t
				else
					var/list/access = list()
					if(is_centcom())
						access = SSaccess.get_centcom_access(t1)
					else
						var/datum/job/jobdatum = SSjob.get_job(t1)
						if(!jobdatum)
							to_chat(ui.user, span_warning("No log exists for this job: [t1]"))
							return
						access = jobdatum.get_access()

					modify.access = access
					modify.assignment = t1
					modify.rank = t1

			. = TRUE

		if("reg")
			if(is_authenticated())
				var/temp_name = sanitizeName(params["reg"])
				if(temp_name)
					modify.registered_name = temp_name
				else
					visible_message(span_notice("[src] buzzes rudely."))
			. = TRUE

		if("account")
			if(is_authenticated())
				var/account_num = text2num(params["account"])
				modify.associated_account_number = account_num
			. = TRUE

		if("mode")
			mode = text2num(params["mode_target"])
			. = TRUE

		if("print")
			if(!printing)
				printing = 1
				spawn(50)
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
				. = TRUE

		if("terminate")
			if(is_authenticated())
				modify.assignment = "Dismissed" // setting adjustment
				modify.access = list()

			. = TRUE

	if(modify)
		modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"

/obj/machinery/computer/card/centcom
	name = "\improper CentCom ID card modification console"
	circuit = /obj/item/circuitboard/card/centcom
	req_access = list(ACCESS_CENT_CAPTAIN)


/obj/machinery/computer/card/centcom/is_centcom()
	return 1
