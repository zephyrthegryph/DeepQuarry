#define MED_DATA_R_LIST	2	// Record list
#define MED_DATA_MAINT	3	// Records maintenance
#define MED_DATA_RECORD	4	// Record
#define MED_DATA_V_DATA	5	// Virus database
#define MED_DATA_MEDBOT	6	// Medbot monitor

#define FIELD(N, V, E) list(field = N, value = V, edit = E)
#define MED_FIELD(N, V, E, LB) list(field = N, value = V, edit = E, line_break = LB)

/obj/machinery/computer/med_data//TODO:SANITY
	name = "medical records console"
	desc = "Used to view, edit and maintain medical records."
	icon_keyboard = "med_key"
	icon_screen = "medcomp"
	light_color = "#315ab4"
	req_one_access = list(ACCESS_MEDICAL, ACCESS_FORENSICS_LOCKERS, ACCESS_ROBOTICS)
	circuit = /obj/item/circuitboard/med_data
	var/obj/item/card/id/scan = null
	var/authenticated = null
	var/rank = null
	var/screen = null
	var/datum/data/record/active1
	var/datum/data/record/active2
	var/list/temp = null
	var/printing = null
	// The below are used to make modal generation more convenient
	var/static/list/field_edit_questions
	var/static/list/field_edit_choices

/obj/machinery/computer/med_data/Initialize(mapload)
	. = ..()
	field_edit_questions = list(
		// General
		"sex" = "Please select new sex:",
		"species" = "Please input new species:",
		"age" = "Please input new age:",
		"fingerprint" = "Please input new fingerprint hash:",
		"p_stat" = "Please select new physical status:",
		"m_stat" = "Please select new mental status:",
		// Medical
		"id_gender" = "Please select new gender identity:",
		"blood_type" = "Please select new blood type:",
		"blood_reagent" = "Please select new blood basis:",
		"b_dna" = "Please input new DNA:",
		"mi_dis" = "Please input new minor disabilities:",
		"mi_dis_d" = "Please summarize minor disabilities:",
		"ma_dis" = "Please input new major disabilities:",
		"ma_dis_d" = "Please summarize major disabilities:",
		"alg" = "Please input new allergies:",
		"alg_d" = "Please summarize allergies:",
		"cdi" = "Please input new current diseases:",
		"cdi_d" = "Please summarize current diseases:",
		"notes" = "Please input new important notes:",
	)
	field_edit_choices = list(
		// General
		"sex" = all_genders_text_list,
		"p_stat" = list("*Deceased*", "*SSD*", "Active", "Physically Unfit", "Disabled"),
		"m_stat" = list("*Insane*", "*Unstable*", "*Watch*", "Stable"),
		// Medical
		"id_gender" = all_genders_text_list,
		"blood_type" = list("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"),
	)

/// Old verb "Eject ID Card".
/obj/machinery/computer/med_data/proc/med_data_eject_id(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user || user.stat || user.lying)	return

	if(scan)
		to_chat(user, "You remove \the [scan] from \the [src].")
		scan.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(scan)
		own_take(src, nameof(scan))
	else
		to_chat(user, "There is nothing to remove from the console.")
	return

EXTEND_INTERACTIONS(/obj/machinery/computer/med_data, \
	INTERACT_ITEM(null, PROC_REF(med_data_interaction_item)), \
	INTERACT_HAND(null, TYPE_PROC_REF(/atom, interaction_open_ui_fingerprint)), \
	INTERACT_VERB("Eject ID Card", PROC_REF(med_data_eject_id)), \
)

/// Old attackby.
/obj/machinery/computer/med_data/proc/med_data_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(istype(O, /obj/item/card/id) && !scan && own_set(src, nameof(src.scan), O, user = user))
		to_chat(user, "You insert \the [O].")
		tgui_interact(user)
		return TRUE
	return FALSE

DECLARE_UI(/obj/machinery/computer/med_data, "MedicalRecords", UI_TITLE("Medical Records"))

UI_DATA_REPLACE(/obj/machinery/computer/med_data, "temp:text", "authenticated", "rank", "screen:num", "printing:num", "merge:ui_data_obj_machinery_computer_med_data{scan:text,isAI:num,isRobot:num,records:list,general:list,medical:list,virus:list,medbots:list,modal:unknown}")

/// The computed part of /obj/machinery/computer/med_data's window data (declared on its UI_DATA row).
/obj/machinery/computer/med_data/proc/ui_data_obj_machinery_computer_med_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scan"] = scan ? scan.name : null
	data["isAI"] = isAI(user)
	data["isRobot"] = isrobot(user)
	if(authenticated)
		switch(screen)
			if(MED_DATA_R_LIST)
				if(!isnull(GLOB.data_core.general))
					var/list/records = list()
					data["records"] = records
					for(var/datum/data/record/R in sortRecord(GLOB.data_core.general))
						records[++records.len] = list("ref" = "\ref[R]", "id" = R.fields["id"], "name" = R.fields["name"])
			if(MED_DATA_RECORD)
				var/list/general = list()
				data["general"] = general
				if(istype(active1(), /datum/data/record) && (active1() in GLOB.data_core.general))
					var/list/fields = list()
					general["fields"] = fields
					fields[++fields.len] = FIELD("Name", active1().fields["name"], null)
					fields[++fields.len] = FIELD("ID", active1().fields["id"], null)
					fields[++fields.len] = FIELD("Sex", active1().fields["sex"], "sex")
					fields[++fields.len] = FIELD("Species", active1().fields["species"], "species")
					fields[++fields.len] = FIELD("Age", "[active1().fields["age"]]", "age")
					fields[++fields.len] = FIELD("Fingerprint", active1().fields["fingerprint"], "fingerprint")
					fields[++fields.len] = FIELD("Physical Status", active1().fields["p_stat"], "p_stat")
					fields[++fields.len] = FIELD("Mental Status", active1().fields["m_stat"], "m_stat")
					var/list/photos = list()
					general["photos"] = photos
					photos[++photos.len] = active1().fields["photo-south"]
					photos[++photos.len] = active1().fields["photo-west"]
					general["has_photos"] = (active1().fields["photo-south"] || active1().fields["photo-west"] ? 1 : 0)
					general["empty"] = 0
				else
					general["empty"] = 1

				var/list/medical = list()
				data["medical"] = medical
				if(istype(active2(), /datum/data/record) && (active2() in GLOB.data_core.medical))
					var/list/fields = list()
					medical["fields"] = fields
					fields[++fields.len] = MED_FIELD("Gender identity", active2().fields["id_gender"], "id_gender", TRUE)
					fields[++fields.len] = MED_FIELD("Blood Type", active2().fields["b_type"], "blood_type", FALSE)
					fields[++fields.len] = MED_FIELD("Blood Basis", active2().fields["blood_reagent"], "blood_reagent", FALSE)
					fields[++fields.len] = MED_FIELD("DNA", active2().fields["b_dna"], "b_dna", TRUE)
					fields[++fields.len] = MED_FIELD("Brain Type", active2().fields["brain_type"], "brain_type", TRUE)
					fields[++fields.len] = MED_FIELD("Important Notes", active2().fields["notes"], "notes", TRUE)
					if(!active2().fields["comments"] || !islist(active2().fields["comments"]))
						active2().fields["comments"] = list()
					medical["comments"] = active2().fields["comments"]
					medical["empty"] = 0
				else
					medical["empty"] = 1
			if(MED_DATA_V_DATA)
				data["virus"] = list()
				for(var/datum/data/record/v in GLOB.virusDB)
					data["virus"] += list(list("name" = v.fields["name"], "D" = "\ref[v]"))
			if(MED_DATA_MEDBOT)
				data["medbots"] = list()
				for(var/mob/living/bot/medbot/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
					if(M.z != z)
						continue
					var/turf/T = get_turf(M)
					if(T)
						var/medbot = list()
						var/area/A = get_area(T)
						medbot["name"] = M.name
						medbot["area"] = A.name
						medbot["x"] = T.x
						medbot["y"] = T.y
						medbot["on"] = M.on
						if(!isnull(M.reagent_glass) && M.use_beaker)
							medbot["use_beaker"] = 1
							medbot["total_volume"] = M.reagent_glass.reagents.total_volume
							medbot["maximum_volume"] = M.reagent_glass.reagents.maximum_volume
						else
							medbot["use_beaker"] = 0
						data["medbots"] += list(medbot)

	data["modal"] = tgui_modal_data(src)
	return data

/obj/machinery/computer/med_data/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!(active1() in GLOB.data_core.general))
		rel_clear(src, nameof(active1))
	if(!(active2() in GLOB.data_core.medical))
		rel_clear(src, nameof(active2))
	return TRUE

UI_ACT(/obj/machinery/computer/med_data, "cleartemp", ui_act_cleartemp)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_cleartemp)
	. = TRUE
	temp = null

UI_ACT(/obj/machinery/computer/med_data, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_scan)
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(ui.user) && !ui.user.get_active_hand())
			ui.user.put_in_hands(scan)
		own_take(src, nameof(/obj/item/extrapolator::scan))
	else
		var/obj/item/I = ui.user.get_active_hand()
		if(istype(I, /obj/item/card/id))
			own_set(src, nameof(src.scan), I, user = ui.user)

UI_ACT(/obj/machinery/computer/med_data, "login", ui_act_login, UI_ARG_NUM("login_type"))
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_login)
	. = TRUE
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
	if(authenticated)
		rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
		rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))
		screen = MED_DATA_R_LIST

UI_ACT(/obj/machinery/computer/med_data, "logout", ui_act_logout)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_logout)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(ui.user) && !ui.user.get_active_hand())
			ui.user.put_in_hands(scan)
		own_take(src, nameof(/obj/item/extrapolator::scan))
	authenticated = null
	screen = null
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))

UI_ACT(/obj/machinery/computer/med_data, "screen", ui_act_screen, UI_ARG_NUM("screen"))
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_screen)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	screen = clamp(params["screen"] || 0, MED_DATA_R_LIST, MED_DATA_MEDBOT)
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))

UI_ACT(/obj/machinery/computer/med_data, "vir", ui_act_vir, UI_ARG_REF("vir", null, /datum/data/record))
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_vir)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/v = params["vir"]
	if(!istype(v))
		return FALSE
	tgui_modal_message(src, "virus", "", null, v.fields["tgui_description"])

UI_ACT(/obj/machinery/computer/med_data, "del_all", ui_act_del_all)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_del_all)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	for(var/datum/data/record/R in GLOB.data_core.medical)
		qdel(R)
	set_temp("All medical records deleted.")

UI_ACT(/obj/machinery/computer/med_data, "del_r", ui_act_del_r)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_del_r)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active2())
		set_temp("Medical record deleted.")
		qdel(active2())

UI_ACT(/obj/machinery/computer/med_data, "d_rec", ui_act_d_rec, UI_ARG_REF("d_rec", null, /datum/data/record))
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_d_rec)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/general_record = params["d_rec"]
	if(!(general_record in GLOB.data_core.general))
		set_temp("Record not found.", "danger")
		return

	var/datum/data/record/medical_record
	for(var/datum/data/record/M in GLOB.data_core.medical)
		if(M.fields["name"] == general_record.fields["name"] && M.fields["id"] == general_record.fields["id"])
			medical_record = M
			break

	rel_set(src, nameof(/obj/machinery/computer/med_data::active1), general_record)
	rel_set(src, nameof(/obj/machinery/computer/med_data::active2), medical_record)
	screen = MED_DATA_RECORD

UI_ACT(/obj/machinery/computer/med_data, "sync_r", ui_act_sync_r)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_sync_r)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active2())
		set_temp(client_update_record(src,ui.user))

UI_ACT(/obj/machinery/computer/med_data, "edit_notes", ui_act_edit_notes)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_edit_notes)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
		// The modal input in tgui is busted for this sadly...
	om_ask(ui.user, /datum/om/prompt/text/record_notes, PROC_REF(record_notes_entered), default = html_decode(active2().fields["notes"]), record = active2())

UI_ACT(/obj/machinery/computer/med_data, "new", ui_act_new)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_new)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(istype(active1(), /datum/data/record) && !istype(active2(), /datum/data/record))
		var/datum/data/record/R = new /datum/data/record()
		R.fields["name"] = active1().fields["name"]
		R.fields["id"] = active1().fields["id"]
		R.name = "Medical Record #[R.fields["id"]]"
		R.fields["b_type"] = "Unknown"
		R.fields["blood_reagent"] = "Unknown"
		R.fields["b_dna"] = "Unknown"
		R.fields["mi_dis"] = "None"
		R.fields["mi_dis_d"] = "No minor disabilities have been declared."
		R.fields["ma_dis"] = "None"
		R.fields["ma_dis_d"] = "No major disabilities have been diagnosed."
		R.fields["alg"] = "None"
		R.fields["alg_d"] = "No allergies have been detected in this patient."
		R.fields["cdi"] = "None"
		R.fields["cdi_d"] = "No diseases have been diagnosed at the moment."
		R.fields["notes"] = "No notes."
		own_add(GLOB.data_core, nameof(/datum/datacore::medical), R)
		rel_set(src, nameof(/obj/machinery/computer/med_data::active2), R)
		screen = MED_DATA_RECORD
		set_temp("Medical record created.", "success")

UI_ACT(/obj/machinery/computer/med_data, "del_c", ui_act_del_c, UI_ARG_NUM("del_c"))
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_del_c)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/index = params["del_c"]
	if(!index || !istype(active2(), /datum/data/record))
		return

	var/list/comments = active2().fields["comments"]
	index = clamp(index, 1, length(comments))
	if(comments[index])
		comments.Cut(index, index + 1)

UI_ACT(/obj/machinery/computer/med_data, "search", ui_act_search, UI_ARG_TEXT("t1"))
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_search)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))
	var/t1 = lowertext(params["t1"] || "")
	if(!length(t1))
		return

	for(var/datum/data/record/R in GLOB.data_core.medical)
		if(t1 == lowertext(R.fields["name"]) || t1 == lowertext(R.fields["id"]) || t1 == lowertext(R.fields["b_dna"]))
			rel_set(src, nameof(/obj/machinery/computer/med_data::active2), R)
			break
	if(!active2())
		set_temp("Medical record not found. You must enter the person's exact name, ID or DNA.", "danger")
		return
	for(var/datum/data/record/E in GLOB.data_core.general)
		if(E.fields["name"] == active2().fields["name"] && E.fields["id"] == active2().fields["id"])
			rel_set(src, nameof(/obj/machinery/computer/med_data::active1), E)
			break
	screen = MED_DATA_RECORD

UI_ACT(/obj/machinery/computer/med_data, "print_p", ui_act_print_p)
UI_ACT_PROC(/obj/machinery/computer/med_data, ui_act_print_p)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!printing)
		printing = TRUE
		SStgui.update_uis(src)
		om_after(src, 5 SECONDS, PROC_REF(print_finish))

/obj/machinery/computer/med_data/proc/record_notes_entered(datum/om/prompt/text/record_notes/ask)
	var/new_notes = strip_html_simple(ask.text, MAX_RECORD_LENGTH)
	if(new_notes != "")
		set_record_notes(ask.record, new_notes)
		return
	om_ask(ask.answerer, /datum/om/prompt/confirm/record_notes_delete, PROC_REF(record_notes_confirmed), record = ask.record)

/obj/machinery/computer/med_data/proc/record_notes_confirmed(datum/om/prompt/confirm/record_notes_delete/ask)
	set_record_notes(ask.record, "")

/obj/machinery/computer/med_data/proc/set_record_notes(datum/data/record/R, notes)
	if(R == active2())
		active2().fields["notes"] = notes
		SStgui.update_uis(src)

/// A records console's notes editor (medical, security and employment records).
/datum/om/prompt/text/record_notes
	title = "Character Preference"
	message = "Enter new information here."
	max_length = MAX_RECORD_LENGTH
	multiline = TRUE
	requires = PROMPT_ADJACENT
	var/datum/data/record/record

/// Empty notes: confirm clearing the record's notes.
/datum/om/prompt/confirm/record_notes_delete
	title = "Confirm Delete"
	message = "Are you sure you want to delete the current record's notes?"
	yes_text = "Delete"
	requires = PROMPT_ADJACENT
	var/datum/data/record/record


/obj/machinery/computer/med_data/ui_modal_opened(mob/user, id, list/arguments, datum/tgui/ui, datum/tgui_state/state)
	. = TRUE
	switch(id)
		if("edit")
			var/field = arguments["field"]
			if(!length(field) || !field_edit_questions[field])
				return
			var/question = field_edit_questions[field]
			var/choices = field_edit_choices[field]
			if(length(choices))
				tgui_modal_choice(src, id, question, arguments = arguments, value = arguments["value"], choices = choices)
			else
				tgui_modal_input(src, id, question, arguments = arguments, value = arguments["value"])
		if("add_c")
			tgui_modal_input(src, id, "Please enter your message:")
		else
			return FALSE

/obj/machinery/computer/med_data/ui_modal_answered(mob/user, id, answer, list/arguments, datum/tgui/ui, datum/tgui_state/state)
	. = TRUE
	switch(id)
		if("edit")
			var/field = arguments["field"]
			if(!length(field) || !field_edit_questions[field])
				return
			var/list/choices = field_edit_choices[field]
			if(length(choices) && !(answer in choices))
				return

			if(field == "age")
				answer = text2num(answer)

			if(istype(active2(), /datum/data/record) && (field in active2().fields))
				active2().fields[field] = answer
			else if(istype(active1(), /datum/data/record) && (field in active1().fields))
				active1().fields[field] = answer
		if("add_c")
			if(!length(answer) || !istype(active2(), /datum/data/record) || !length(authenticated))
				return
			active2().fields["comments"] += list(list(
				header = "Made by [authenticated] ([rank]) at [worldtime2stationtime(world.time)]",
				text = answer
			))
		else
			return FALSE
/**
 * Called when the print timer finishes
 */
/obj/machinery/computer/med_data/proc/print_finish()
	var/obj/item/paper/P = new(loc)
	P.info = "<center>" + span_bold("Medical Record") + "</center><br>"
	if(istype(active1(), /datum/data/record) && (active1() in GLOB.data_core.general))
		P.info += {"Name: [active1().fields["name"]] ID: [active1().fields["id"]]
		<br>\nSex: [active1().fields["sex"]]
		<br>\nSpecies: [active1().fields["species"]]
		<br>\nAge: [active1().fields["age"]]
		<br>\nFingerprint: [active1().fields["fingerprint"]]
		<br>\nPhysical Status: [active1().fields["p_stat"]]
		<br>\nMental Status: [active1().fields["m_stat"]]<br>"}
	else
		P.info += span_bold("General Record Lost!") + "<br>"
	if(istype(active2(), /datum/data/record) && (active2() in GLOB.data_core.medical))
		P.info += {"<br>\n<center><b>Medical Data</b></center>
		<br>\nGender Identity: [active2().fields["id_gender"]]
		<br>\nBlood Type: [active2().fields["b_type"]]
		<br>\nBlood Basis: [active2().fields["blood_reagent"]]
		<br>\nDNA: [active2().fields["b_dna"]]<br>\n
		<br>\nMinor Disabilities: [active2().fields["mi_dis"]]
		<br>\nDetails: [active2().fields["mi_dis_d"]]<br>\n
		<br>\nMajor Disabilities: [active2().fields["ma_dis"]]
		<br>\nDetails: [active2().fields["ma_dis_d"]]<br>\n
		<br>\nAllergies: [active2().fields["alg"]]
		<br>\nDetails: [active2().fields["alg_d"]]<br>\n
		<br>\nCurrent Diseases: [active2().fields["cdi"]] (per disease info placed in log/comment section)
		<br>\nDetails: [active2().fields["cdi_d"]]<br>\n
		<br>\nImportant Notes:
		<br>\n\t[active2().fields["notes"]]<br>\n
		<br>\n
		<center><b>Comments/Log</b></center><br>"}
		for(var/c in active2().fields["comments"])
			P.info += "[c["header"]]<br>[c["text"]]<br>"
	else
		P.info += span_bold("Medical Record Lost!") + "<br>"
	P.info += "</tt>"
	P.name = "paper - 'Medical Record: [active1().fields["name"]]'"
	printing = FALSE
	SStgui.update_uis(src)

/**
 * Sets a temporary message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * style - The style of the message: (color name), info, success, warning, danger, virus
 */
/obj/machinery/computer/med_data/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

DAMAGE_REACTION(/obj/machinery/computer/med_data, DAMAGE_EMP, PROC_REF(med_data_emp))
/// An EMP scrambles or wipes some of the records.
/obj/machinery/computer/med_data/proc/med_data_emp(datum/damage_packet/packet)
	if(!operable())
		return

	for(var/datum/data/record/R in GLOB.data_core.medical)
		if(prob(10/packet.severity))
			switch(rand(1,6))
				if(1)
					R.fields["name"] = "[pick(pick(GLOB.first_names_male), pick(GLOB.first_names_female))] [pick(GLOB.last_names)]"
				if(2)
					R.fields["sex"]	= pick("Male", "Female")
				if(3)
					R.fields["age"] = rand(5, 85)
				if(4)
					R.fields["b_type"] = pick("A-", "B-", "AB-", "O-", "A+", "B+", "AB+", "O+")
				if(5)
					R.fields["p_stat"] = pick("*SSD*", "Active", "Physically Unfit", "Disabled")
					if(GLOB.PDA_Manifest.len)
						GLOB.PDA_Manifest.Cut()
				if(6)
					R.fields["m_stat"] = pick("*Insane*", "*Unstable*", "*Watch*", "Stable")
			continue

		else if(prob(1))
			qdel(R)
			continue

/obj/machinery/computer/med_data/laptop //[TO DO] Change name to PCU and update mapdata to include replacement computers
	name = "\improper Medical Laptop"
	desc = "A personal computer unit. It seems to have only the medical records program installed."
	icon_screen = "pcu_generic"
	icon_state = "pcu_med"
	icon_keyboard = "pcu_key"
	light_color = "#5284e7"
	circuit = /obj/item/circuitboard/med_data/pcu
	density = FALSE

#undef MED_DATA_R_LIST
#undef MED_DATA_MAINT
#undef MED_DATA_RECORD
#undef MED_DATA_V_DATA
#undef MED_DATA_MEDBOT

#undef FIELD
#undef MED_FIELD

/obj/machinery/computer/med_data/declare_ownership(decl)
	..()
	own(decl, nameof(scan), policy = OWN_CONTAINED)

/// The selected record (a relation view).
/obj/machinery/computer/med_data/proc/active1() as /datum/data/record
	return active1

/// The selected record (a relation view).
/obj/machinery/computer/med_data/proc/active2() as /datum/data/record
	return active2
