#define SEC_DATA_R_LIST	2	// Record list
#define SEC_DATA_MAINT	3	// Records maintenance
#define SEC_DATA_RECORD	4	// Record

#define FIELD(N, V, E) list(field = N, value = V, edit = E)

/obj/machinery/computer/secure_data//TODO:SANITY
	name = "security records console"
	desc = "Used to view, edit and maintain security records"
	icon_keyboard = "security_key"
	icon_screen = "security"
	light_color = "#a91515"
	req_one_access = list(ACCESS_SECURITY, ACCESS_FORENSICS_LOCKERS, ACCESS_LAWYER)
	circuit = /obj/item/circuitboard/secure_data
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

/obj/machinery/computer/secure_data/Initialize(mapload)
	. = ..()
	field_edit_questions = list(
		// General
		"name" = "Please enter new name:",
		"id" = "Please enter new id:",
		"sex" = "Please select new sex:",
		"species" = "Please input new species:",
		"age" = "Please input new age:",
		"rank" = "Please enter new rank:",
		"fingerprint" = "Please input new fingerprint hash:",
		// Security
		"brain_type" = "Please select new brain type:",
		"criminal" = "Please select new criminal status:",
		"mi_crim" = "Please input new minor crime:",
		"mi_crim_d" = "Please input minor crime summary.",
		"ma_crim" = "Please input new major crime:",
		"ma_crim_d" = "Please input new major crime summary.",
		"notes" = "Please input new important notes:",
	)
	field_edit_choices = list(
		// General
		"sex" = all_genders_text_list,
		// Security
		"criminal" = list("*Arrest*", "Incarcerated", "Parolled", "Released", "None"),
	)

/obj/machinery/computer/secure_data/proc/interaction_secure_data_eject_id(datum/act/op/A)
	var/mob/user = A.actor
	if(scan)
		to_chat(user, "You remove \the [scan] from \the [src].")
		scan.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(scan)
		rel_take(src, nameof(scan))
	else
		to_chat(user, "There is nothing to remove from the console.")
	return TRUE

/obj/machinery/computer/secure_data/proc/interaction_secure_data_insert_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(!move_into(src, nameof(src.scan), held, user))
		return OP_DECLINE
	to_chat(user, "You insert \the [held].")
	tgui_interact(user)
	return OP_OK

//Someone needs to break down the dat += into chunks instead of long ass lines.
CAPABILITIES(/obj/machinery/computer/secure_data)
	ref_one(nameof(active2), /datum/data/record)
	interface("SecurityRecords", title = "Security Records")
	extend("ui_open", priority(OP_PRIORITY_DEFAULT - 2), then(PROC_REF(record_open_touch)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("login", ui_act("login", arg("login_type", num())), then(PROC_REF(ui_act_login)))
	op("logout", ui_act("logout"), then(PROC_REF(ui_act_logout)))
	op("screen", ui_act("screen", arg("screen", num())), then(PROC_REF(ui_act_screen)))
	op("del_all", ui_act("del_all"), then(PROC_REF(ui_act_del_all)))
	op("del_r", ui_act("del_r"), then(PROC_REF(ui_act_del_r)))
	op("del_r_2", ui_act("del_r_2"), then(PROC_REF(ui_act_del_r_2)))
	op("sync_r", ui_act("sync_r"), then(PROC_REF(ui_act_sync_r)))
	op("edit_notes", ui_act("edit_notes"), needs(req_adjacent(), req(PROC_REF(records_authenticated), because = MSG(records/not_authenticated))), asks(/datum/prompt/text, fields = list("title" = "Character Preference", "question" = "Enter new information here.", "max_len" = MAX_RECORD_LENGTH, "multiline" = TRUE, "default" = computed(PROC_REF(notes_default))), step = "notes"), asks(/datum/prompt/yes_no/record_notes_delete, fields = list("record" = computed(PROC_REF(notes_record)), "timeout" = 0), step = "delete_notes", when = PROC_REF(notes_empty)), then(PROC_REF(ui_act_edit_notes)))
	op("d_rec", ui_act("d_rec", arg("d_rec")), then(PROC_REF(ui_act_d_rec)))
	op("new", ui_act("new"), then(PROC_REF(ui_act_new)))
	op("del_c", ui_act("del_c", arg("del_c", num())), then(PROC_REF(ui_act_del_c)))
	op("search", ui_act("search", arg("t1", schema_text(4096))), then(PROC_REF(ui_act_search)))
	op("print_p", ui_act("print_p"), then(PROC_REF(ui_act_print_p)))
	op("photo_front", ui_act("photo_front"), then(PROC_REF(ui_act_photo_front)))
	op("photo_side", ui_act("photo_side"), then(PROC_REF(ui_act_photo_side)))
	extend(TAG_UI, then(PROC_REF(ui_records_fresh), early = TRUE))
	// The record modals (the old ui_modal_opened()/ui_modal_answered()): a field is edited by a pick or by typing, as the field's kind says.
	op("edit", ui_act("modal:edit", arg("arguments")), needs(req(PROC_REF(edit_field_known), silent = TRUE)),
		asks(/datum/prompt/choice/security_record_edit, fields = list("arguments" = arg_of("arguments"), "inline" = TRUE, "timeout" = 0), step = "edit_choice", when = PROC_REF(edit_by_choice)),
		asks(/datum/prompt/text/security_record_edit, fields = list("arguments" = arg_of("arguments"), "inline" = TRUE, "timeout" = 0), step = "edit_text", when = PROC_REF(edit_by_text)),
		then(PROC_REF(modal_edit)))
	op("add_c", ui_act("modal:add_c", arg("arguments")), asks(/datum/prompt/text, fields = list("question" = "Please enter your message:", "inline" = TRUE, "timeout" = 0), step = "comment"), then(PROC_REF(modal_add_comment)))
	op("secure_data_eject_id", menu(), label("Eject ID Card"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_secure_data_eject_id)))
	op("secure_data_insert_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT), label("Insert ID"), when(req_empty(nameof(scan))), then(PROC_REF(interaction_secure_data_insert_id)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(secure_data_emp)))

/obj/machinery/computer/secure_data/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["temp"] = temp
	data["authenticated"] = authenticated
	data["rank"] = rank
	data["screen"] = screen
	data["printing"] = printing
	data["scan"] = scan ? scan.name : null
	data["isAI"] = user?.records_login_kind() == LOGIN_TYPE_AI
	data["isRobot"] = user?.records_login_kind() == LOGIN_TYPE_ROBOT
	if(authenticated)
		switch(screen)
			if(SEC_DATA_R_LIST)
				if(!isnull(GLOB.data_core.general))
					var/list/records = list()
					data["records"] = records
					for(var/datum/data/record/R in sortRecord(GLOB.data_core.general))
						var/color = null
						var/criminal = "None"
						for(var/datum/data/record/M in GLOB.data_core.security)
							if(M.fields["name"] == R.fields["name"] && M.fields["id"] == R.fields["id"])
								switch(M.fields["criminal"])
									if("*Arrest*")
										color = "bad"
									if("Incarcerated")
										color = "brown"
									if("Parolled", "Released")
										color = "average"
									if("None")
										color = "good"
								criminal = M.fields["criminal"]
								break
						records[++records.len] = list(
							"ref" = "\ref[R]",
							"id" = R.fields["id"],
							"name" = R.fields["name"],
							"color" = color,
							"criminal" = criminal
						)
			if(SEC_DATA_RECORD)
				var/list/general = list()
				data["general"] = general
				if(istype(active1(), /datum/data/record) && (active1() in GLOB.data_core.general))
					var/list/fields = list()
					general["fields"] = fields
					fields[++fields.len] = FIELD("Name", active1().fields["name"], "name")
					fields[++fields.len] = FIELD("ID", active1().fields["id"], "id")
					fields[++fields.len] = FIELD("Entity Classification", active1().fields["brain_type"], "brain_type")
					fields[++fields.len] = FIELD("Sex", active1().fields["sex"], "sex")
					fields[++fields.len] = FIELD("Species", active1().fields["species"], "species")
					fields[++fields.len] = FIELD("Age", "[active1().fields["age"]]", "age")
					fields[++fields.len] = FIELD("Rank", active1().fields["rank"], "rank")
					fields[++fields.len] = FIELD("Fingerprint", active1().fields["fingerprint"], "fingerprint")
					fields[++fields.len] = FIELD("Physical Status", active1().fields["p_stat"], null)
					fields[++fields.len] = FIELD("Mental Status", active1().fields["m_stat"], null)
					var/list/photos = list()
					general["photos"] = photos
					photos[++photos.len] = active1().fields["photo-south"]
					photos[++photos.len] = active1().fields["photo-west"]
					general["has_photos"] = (active1().fields["photo-south"] || active1().fields["photo-west"] ? 1 : 0)
					general["empty"] = 0
				else
					general["empty"] = 1

				var/list/security = list()
				data["security"] = security
				if(istype(active2(), /datum/data/record) && (active2() in GLOB.data_core.security))
					var/list/fields = list()
					security["fields"] = fields
					fields[++fields.len] = FIELD("Criminal Status", active2().fields["criminal"], "criminal")
					fields[++fields.len] = FIELD("Minor Crimes", active2().fields["mi_crim"], "mi_crim")
					fields[++fields.len] = FIELD("Details", active2().fields["mi_crim_d"], "mi_crim_d")
					fields[++fields.len] = FIELD("Major Crimes", active2().fields["ma_crim"], "ma_crim")
					fields[++fields.len] = FIELD("Details", active2().fields["ma_crim_d"], "ma_crim_d")
					fields[++fields.len] = FIELD("Important Notes", active2().fields["notes"], "notes")
					if(!active2().fields["comments"] || !islist(active2().fields["comments"]))
						active2().fields["comments"] = list()
					security["comments"] = active2().fields["comments"]
					security["empty"] = 0
				else
					security["empty"] = 1

	data["modal"] = tgui_modal_data(src)
	return data

/// Every button first drops a record the data core no longer holds (the old window guard's side effects).
/obj/machinery/computer/secure_data/proc/ui_records_fresh(datum/act/op/A)
	if(!(active1() in GLOB.data_core.general))
		rel_clear(src, nameof(active1))
	if(!(active2() in GLOB.data_core.security))
		rel_clear(src, nameof(active2))
	return OP_OK

/obj/machinery/computer/secure_data/proc/ui_act_cleartemp(datum/act/op/A)
	. = TRUE
	temp = null

/obj/machinery/computer/secure_data/proc/ui_act_scan(datum/act/op/A)
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(A.actor) && !A.actor.get_active_hand())
			A.actor.put_in_hands(scan)
		rel_take(src, nameof(src.scan))
	else
		var/obj/item/I = A.actor.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.scan), I, A.actor)

/obj/machinery/computer/secure_data/proc/ui_act_login(datum/act/op/A, login_type_arg)
	. = TRUE
	var/login_type = login_type_arg
	if(login_type == LOGIN_TYPE_NORMAL && istype(scan))
		if(check_access(scan))
			authenticated = scan.registered_name
			rank = scan.assignment
	else if(login_type != LOGIN_TYPE_NORMAL && login_type == A.actor.records_login_kind())
		authenticated = A.actor.name
		rank = A.actor.records_login_rank()
	if(authenticated)
		rel_clear(src, nameof(src.active1))
		rel_clear(src, nameof(src.active2))
		screen = SEC_DATA_R_LIST

/obj/machinery/computer/secure_data/proc/ui_act_logout(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(A.actor) && !A.actor.get_active_hand())
			A.actor.put_in_hands(scan)
		rel_take(src, nameof(src.scan))
	authenticated = null
	screen = null
	rel_clear(src, nameof(src.active1))
	rel_clear(src, nameof(src.active2))

/obj/machinery/computer/secure_data/proc/ui_act_screen(datum/act/op/A, screen_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	screen = clamp(screen_arg || 0, SEC_DATA_R_LIST, SEC_DATA_RECORD)
	rel_clear(src, nameof(src.active1))
	rel_clear(src, nameof(src.active2))

/obj/machinery/computer/secure_data/proc/ui_act_del_all(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	for(var/datum/data/record/R in GLOB.data_core.security)
		spent(R)
	set_temp("All security records deleted.")

/obj/machinery/computer/secure_data/proc/ui_act_del_r(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active2())
		set_temp("Security record deleted.")
		spent(active2())

/obj/machinery/computer/secure_data/proc/ui_act_del_r_2(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active1())
		set_temp("All records for [active1().fields["name"]] deleted.")
		for(var/datum/data/record/R in GLOB.data_core.medical)
			if((R.fields["name"] == active1().fields["name"] || R.fields["id"] == active1().fields["id"]))
				spent(R)
		spent(active1())
	if(active2())
		spent(active2())

/obj/machinery/computer/secure_data/proc/ui_act_sync_r(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active2())
		set_temp(client_update_record(src,A.actor))

/obj/machinery/computer/secure_data/proc/ui_act_edit_notes(datum/act/op/A)
	if(!active2())
		return OP_OK
	var/new_notes = strip_html_simple(A.step_value("notes"), MAX_RECORD_LENGTH)
	if(new_notes != "")
		set_record_notes(active2(), new_notes)
	else if(A.step_value("delete_notes"))
		var/datum/prompt/yes_no/record_notes_delete/R = A.answer
		set_record_notes(R.record, "")
	return OP_OK

/obj/machinery/computer/secure_data/proc/notes_empty(datum/act/op/A)
	return !!active2() && strip_html_simple(A.step_value("notes"), MAX_RECORD_LENGTH) == ""

/obj/machinery/computer/secure_data/proc/notes_record(datum/act/op/A)
	return active2()

/obj/machinery/computer/secure_data/proc/notes_default(datum/act/A)
	return html_decode(active2()?.fields["notes"])

/// The operator is logged in (the old handlers each refused without it).
/obj/machinery/computer/secure_data/proc/records_authenticated(datum/act/op/A)
	return (!!authenticated) ? null : MSG(records/not_authenticated) // ALLOW(reads): who is logged in is asked when the button is pressed and again when the answer arrives, never cached

/obj/machinery/computer/secure_data/proc/ui_act_d_rec(datum/act/op/A, d_rec)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/general_record = ui_ref(d_rec, null, /datum/data/record)
	if(!(general_record in GLOB.data_core.general))
		set_temp("Record not found.", "danger")
		return

	var/datum/data/record/security_record
	for(var/datum/data/record/M in GLOB.data_core.security)
		if(M.fields["name"] == general_record.fields["name"] && M.fields["id"] == general_record.fields["id"])
			security_record = M
			break

	rel_set(src, nameof(src.active1), general_record)
	rel_set(src, nameof(src.active2), security_record)
	screen = SEC_DATA_RECORD

/obj/machinery/computer/secure_data/proc/ui_act_new(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(istype(active1(), /datum/data/record) && !istype(active2(), /datum/data/record))
		var/datum/data/record/R = new /datum/data/record()
		R.fields["name"] = active1().fields["name"]
		R.fields["id"] = active1().fields["id"]
		R.name = "Security Record #[R.fields["id"]]"
		R.fields["brain_type"]	= "Unknown"
		R.fields["criminal"]	= "None"
		R.fields["mi_crim"]		= "None"
		R.fields["mi_crim_d"]	= "No minor crime convictions."
		R.fields["ma_crim"]		= "None"
		R.fields["ma_crim_d"]	= "No major crime convictions."
		R.fields["notes"]		= "No notes."
		R.fields["notes"]		= "No notes."
		rel_add(GLOB.data_core, nameof(/datum/datacore::security), R)
		rel_set(src, nameof(src.active2), R)
		screen = SEC_DATA_RECORD
		set_temp("Security record created.", "success")

/obj/machinery/computer/secure_data/proc/ui_act_del_c(datum/act/op/A, del_c)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/index = del_c
	if(!index || !istype(active2(), /datum/data/record))
		return

	var/list/comments = active2().fields["comments"]
	index = clamp(index, 1, length(comments))
	if(comments[index])
		comments.Cut(index, index + 1)

/obj/machinery/computer/secure_data/proc/ui_act_search(datum/act/op/A, t1_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	rel_clear(src, nameof(src.active1))
	rel_clear(src, nameof(src.active2))
	var/t1 = lowertext(t1_arg || "")
	if(!length(t1))
		return

	for(var/datum/data/record/R in GLOB.data_core.general)
		if(t1 == lowertext(R.fields["name"]) || t1 == lowertext(R.fields["id"]) || t1 == lowertext(R.fields["fingerprint"]))
			rel_set(src, nameof(src.active1), R)
			break
	if(!active1())
		set_temp("Security record not found. You must enter the person's exact name, ID, or fingerprint.", "danger")
		return
	for(var/datum/data/record/E in GLOB.data_core.security)
		if(E.fields["name"] == active1().fields["name"] && E.fields["id"] == active1().fields["id"])
			rel_set(src, nameof(src.active2), E)
			break
	screen = SEC_DATA_RECORD

/obj/machinery/computer/secure_data/proc/ui_act_print_p(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!printing)
		printing = TRUE
		SStgui.update_uis(src)
		after(src, 5 SECONDS, PROC_REF(print_finish))

/obj/machinery/computer/secure_data/proc/ui_act_photo_front(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/icon/photo = get_photo(A.actor)
	if(photo && active1())
		active1().fields["photo_front"] = photo
		active1().fields["photo-south"] = "'data:image/png;base64,[icon2base64(photo)]'"

/obj/machinery/computer/secure_data/proc/ui_act_photo_side(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/icon/photo = get_photo(A.actor)
	if(photo && active1())
		active1().fields["photo_side"] = photo
		active1().fields["photo-west"] = "'data:image/png;base64,[icon2base64(photo)]'"

/obj/machinery/computer/secure_data/proc/set_record_notes(datum/data/record/R, notes)
	if(R == active2())
		active2().fields["notes"] = notes
		SStgui.update_uis(src)

/// The record field the edit modal names (`arguments["field"]`), when this console can edit it.
/obj/machinery/computer/secure_data/proc/edit_field(list/arguments)
	var/field = islist(arguments) ? arguments["field"] : null
	return (length(field) && field_edit_questions[field]) ? field : null

/// Requirement: the edit modal names a field this console edits (silently refused otherwise, as the old modal never opened).
/obj/machinery/computer/secure_data/proc/edit_field_known(datum/act/op/A)
	return (!isnull(edit_field(A.args["arguments"]))) ? null : MSG(req_failed)

/// The field is edited by picking from its choices.
/obj/machinery/computer/secure_data/proc/edit_by_choice(datum/act/op/A)
	return length(field_edit_choices[edit_field(A.args["arguments"])]) > 0

/// The field is edited by typing.
/obj/machinery/computer/secure_data/proc/edit_by_text(datum/act/op/A)
	return !edit_by_choice(A)

/// Argument-derived fields are prepared on the typed request, after arg_of() supplies the checked modal arguments.
/datum/prompt/choice/security_record_edit
	var/list/arguments

/datum/prompt/choice/security_record_edit/prepare(datum/act/op/A)
	..()
	var/obj/machinery/computer/secure_data/console = A.holder
	var/field = console.edit_field(arguments)
	question = console.field_edit_questions[field]
	choices = console.field_edit_choices[field]
	default = islist(arguments) ? arguments["value"] : null

/datum/prompt/text/security_record_edit
	var/list/arguments

/datum/prompt/text/security_record_edit/prepare(datum/act/op/A)
	..()
	var/obj/machinery/computer/secure_data/console = A.holder
	question = console.field_edit_questions[console.edit_field(arguments)]
	default = islist(arguments) ? arguments["value"] : null

/// The edit modal's answer goes into the record field.
/obj/machinery/computer/secure_data/proc/modal_edit(datum/act/op/A, list/arguments)
	var/mob/user = A.actor
	var/answer = A.step_value("edit_choice")
	if(isnull(answer))
		answer = A.step_value("edit_text")
	. = TRUE
	var/field = arguments["field"]
	if(!length(field) || !field_edit_questions[field])
		return
	var/list/choices = field_edit_choices[field]
	if(length(choices) && !(answer in choices))
		return

	if(field == "age")
		answer = text2num(answer)

	if(field == "rank")
		if(answer in SSjob.occupations_by_name)
			active1().fields["real_rank"] = answer

	var/old_criminal_status
	if(field == "criminal")
		old_criminal_status = active2()?.fields?["criminal"]
		for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			H.flag_hud_update(WANTED_HUD)

	if(istype(active2(), /datum/data/record) && (field in active2().fields))
		active2().fields[field] = answer
	if(istype(active1(), /datum/data/record) && (field in active1().fields))
		active1().fields[field] = answer
	if(field == "criminal" && old_criminal_status != answer)
		record_security_disposition(old_criminal_status, answer, user)

/// The comment modal's answer is added to the record's log.
/obj/machinery/computer/secure_data/proc/modal_add_comment(datum/act/op/A, list/arguments)
	var/answer = A.step_value("comment")
	. = TRUE
	if(!length(answer) || !istype(active2(), /datum/data/record) || !length(authenticated))
		return
	active2().fields["comments"] += list(list(
		header = "Made by [authenticated] ([rank]) at [worldtime2stationtime(world.time)]",
		text = answer
	))
/obj/machinery/computer/secure_data/proc/record_security_disposition(old_status, new_status, mob/living/user)
	if(!istype(active2(), /datum/data/record) || !istext(new_status))
		return FALSE
	var/record_id = active1()?.fields?["id"] || active2().fields["id"] || REF(active2())
	var/subject_name = active1()?.fields?["name"] || active2().fields["name"]
	var/list/custody = SScontracts.physical_custody_snapshot(record_id, subject_name)
	var/custody_duration = custody["duration"] || 0
	var/list/event_tags = list()
	if(old_status == "Incarcerated" && (new_status in list("Released", "Parolled")) && custody["verified"])
		event_tags += "custody_resolution"
	else if(new_status == "None" && old_status == "Incarcerated" && custody["verified"])
		event_tags += "record_cleared"
	var/datum/data/record/disposition_record = active2()
	LAZYINITLIST(disposition_record.disposition_history)
	disposition_record.disposition_history.Add(list(list(
		"occurred_at" = EXPIRY_AT(src, CLOCK_WORLD, 0),
		"actor_account" = contract_account_for_mob(user)?.account_number,
		"actor_name" = user?.real_name,
		"previous_status" = old_status,
		"disposition" = new_status,
		"physical_subject_id" = custody["subject_id"],
		"physical_custody_verified" = custody["verified"],
		"custody_duration" = custody_duration,
	)))
	emit_contract_event(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, list(
		"department" = DEPARTMENT_SECURITY,
		// Subject identity is physical and round-stable. The independently
		// editable record remains the fact identity below, so duplicate records
		// for one prisoner cannot masquerade as distinct custodial cases.
		"subject_id" = custody["subject_id"],
		"subject_name" = subject_name,
		"physical_subject_id" = custody["subject_id"],
		"physical_custody_verified" = custody["verified"],
		"physical_custody_active" = custody["active"],
		"record_id" = record_id,
		"previous_status" = old_status,
		"disposition" = new_status,
		"tags" = event_tags,
		"fact_id" = "security-record:[record_id]",
		"fact_revision" = length(active2().disposition_history),
		"fact_active" = new_status != "None",
		"metrics" = list("custody_duration" = custody_duration),
		"detail" = "Recorded [new_status] disposition with [DisplayTimeText(custody_duration)] of physically verified custody",
	), "security-disposition:[REF(active2())]:[length(active2().disposition_history)]", src, user)
	return TRUE

/**
 * Called when the print timer finishes
 */
/obj/machinery/computer/secure_data/proc/print_finish()
	var/obj/item/paper/P = new(loc)
	P.set_info("<center>" + span_bold("Security Record") + "</center><br>")
	if(istype(active1(), /datum/data/record) && (active1() in GLOB.data_core.general))
		P.set_info(P.info + ({"Name: [active1().fields["name"]] ID: [active1().fields["id"]]
		<br>\nSex: [active1().fields["sex"]]
		<br>\nSpecies: [active1().fields["species"]]
		<br>\nAge: [active1().fields["age"]]
		<br>\nFingerprint: [active1().fields["fingerprint"]]
		<br>\nPhysical Status: [active1().fields["p_stat"]]
		<br>\nMental Status: [active1().fields["m_stat"]]<br>"}))
	else
		P.set_info(P.info + (span_bold("General Record Lost!") + "<br>"))
	if(istype(active2(), /datum/data/record) && (active2() in GLOB.data_core.security))
		P.set_info(P.info + ({"<br>\n<center><b>Security Data</b></center>
		<br>\nCriminal Status: [active2().fields["criminal"]]<br>\n
		<br>\nMinor Crimes: [active2().fields["mi_crim"]]
		<br>\nDetails: [active2().fields["mi_crim_d"]]<br>\n
		<br>\nMajor Crimes: [active2().fields["ma_crim"]]
		<br>\nDetails: [active2().fields["ma_crim_d"]]<br>\n
		<br>\nImportant Notes:
		<br>\n\t[active2().fields["notes"]]<br>\n
		<br>\n
		<center><b>Comments/Log</b></center><br>"}))
		for(var/c in active2().fields["comments"])
			P.set_info(P.info + ("[c["header"]]<br>[c["text"]]<br>"))
	else
		P.set_info(P.info + (span_bold("Security Record Lost!") + "<br>"))
	P.set_info(P.info + ("</tt>"))
	P.name = "paper - 'Security Record: [active1().fields["name"]]'"
	printing = FALSE
	SStgui.update_uis(src)

/**
 * Sets a temporary message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * style - The style of the message: (color name), info, success, warning, danger, virus
 */
/obj/machinery/computer/secure_data/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

/obj/machinery/computer/secure_data/proc/is_not_allowed(mob/user)
	return !src.authenticated || user.stat || user.restrained() || (!in_range(src, user) && (!istype(user, /mob/living/silicon)))

/obj/machinery/computer/secure_data/proc/get_photo(mob/user)
	if(istype(user.get_active_hand(), /obj/item/photo))
		var/obj/item/photo/photo = user.get_active_hand()
		return photo.img
	if(istype(user, /mob/living/silicon))
		var/mob/living/silicon/tempAI = user
		var/obj/item/photo/selection = tempAI.GetPicture()
		if (selection)
			return selection.img

/// An EMP scrambles or wipes some of the records.
/obj/machinery/computer/secure_data/proc/secure_data_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
	if(!operable())
		return

	for(var/datum/data/record/R in GLOB.data_core.security)
		if(prob(10/packet.severity))
			switch(rand(1,6))
				if(1)
					R.fields["name"] = "[pick(pick(GLOB.first_names_male), pick(GLOB.first_names_female))] [pick(GLOB.last_names)]"
				if(2)
					R.fields["sex"]	= pick("Male", "Female")
				if(3)
					R.fields["age"] = rand(5, 85)
				if(4)
					R.fields["criminal"] = pick("None", "*Arrest*", "Incarcerated", "Parolled", "Released")
				if(5)
					R.fields["p_stat"] = pick("*Unconcious*", "Active", "Physically Unfit")
					if(GLOB.PDA_Manifest.len)
						GLOB.PDA_Manifest.Cut()
				if(6)
					R.fields["m_stat"] = pick("*Insane*", "*Unstable*", "*Watch*", "Stable")
			continue

		else if(prob(1))
			destroyed(R, null, "emp")
			continue

/obj/machinery/computer/secure_data/detective_computer
	icon_state = "forensic"

#undef SEC_DATA_R_LIST
#undef SEC_DATA_MAINT
#undef SEC_DATA_RECORD

#undef FIELD

/obj/machinery/computer/secure_data/ownership()
	. = ..()
	. += owns(nameof(scan), policy = OWN_CONTAINED)

/// The selected record (a relation view).
/obj/machinery/computer/secure_data/proc/active1() as /datum/data/record
	return active1

/// The selected record (a relation view).
/obj/machinery/computer/secure_data/proc/active2() as /datum/data/record
	return active2

/obj/machinery/computer/secure_data/proc/record_open_touch(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK
