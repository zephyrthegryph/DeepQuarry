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

MSG_DEF_SELF(records/id_required, "needs an identification card")
MSG_DEF_SELF(records/no_provider, "you have nothing to do that with")
MSG_DEF_SELF(records/unknown_field, "Unknown record field.")
MSG_DEF(records/inserted_id, "You insert %I%.", "")
MSG_DEF(records/ejected_id, "You remove %I% from %T%.", "")

CAPABILITIES(/obj/machinery/computer/med_data)
	ref_one(nameof(active2), /datum/data/record)
	owns_one(nameof(scan), /obj/item/card/id)
	interface("MedicalRecords", title = "Medical Records")
	// Keep the existing plain-click ranking: the computer's generic item op wins;
	// this named insertion is also offered by the context menu.
	op("insert_scan", inputs(item(/obj/item/card/id), menu()), authority(AUTH_PHYSICAL | AUTH_REMOTE_ACCESS | AUTH_AI), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Insert ID card"), when(cond_not(nameof(scan))), needs(req(/obj/item/card/id, because = MSG(records/id_required)), any_of(req(PROC_REF(records_slot_reachable)), all_of(req_actor_kind(/mob/living/silicon), req(PROC_REF(records_remote_slot_allowed)))), req_capable(), req_held_releasable()), then(PROC_REF(insert_scan)))
	op("eject_scan_menu", menu(), authority(AUTH_PHYSICAL | AUTH_REMOTE_ACCESS | AUTH_AI), ungated(), label("Eject ID Card"), when(nameof(scan)), needs(any_of(req(PROC_REF(records_slot_reachable)), all_of(req_actor_kind(/mob/living/silicon), req(PROC_REF(records_remote_slot_allowed)))), req_capable(), req(PROC_REF(scan_removable))), then(PROC_REF(eject_scan)))
	op("open_records", inputs(menu(), hand()), by(NONE), reach(REACH_ANY), authority(AUTH_PHYSICAL | AUTH_REMOTE_ACCESS | AUTH_AI), priority(OP_PRIORITY_DEFAULT - 1), label("Open records"), when(cond_any(req_on_origin(ORIGIN_MENU), req(PROC_REF(records_plain_hand)))), needs(req_actor_kind(/mob/living/silicon, not = TRUE, because = MSG(records/no_provider)), req(PROC_REF(records_open_admission))), then(PROC_REF(open_records)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("login", ui_act("login", arg("login_type", num())), then(PROC_REF(ui_act_login)))
	op("logout", ui_act("logout"), then(PROC_REF(ui_act_logout)))
	op("screen", ui_act("screen", arg("screen", num())), then(PROC_REF(ui_act_screen)))
	op("vir", ui_act("vir", arg("vir")), then(PROC_REF(ui_act_vir)))
	op("del_all", ui_act("del_all"), then(PROC_REF(ui_act_del_all)))
	op("del_r", ui_act("del_r"), then(PROC_REF(ui_act_del_r)))
	op("d_rec", ui_act("d_rec", arg("d_rec")), then(PROC_REF(ui_act_d_rec)))
	op("sync_r", ui_act("sync_r"), then(PROC_REF(ui_act_sync_r)))
	op("edit_notes", ui_act("edit_notes"), needs(req_adjacent(), req(PROC_REF(records_authenticated))), asks(/datum/prompt/text, fields = list("title" = "Character Preference", "question" = "Enter new information here.", "max_len" = MAX_RECORD_LENGTH, "multiline" = TRUE, "default" = computed(PROC_REF(notes_default))), step = "notes"), asks(/datum/prompt/yes_no/record_notes_delete, fields = list("record" = computed(PROC_REF(notes_record)), "timeout" = 0), step = "delete_notes", when = PROC_REF(notes_empty)), then(PROC_REF(ui_act_edit_notes)))
	op("new", ui_act("new"), then(PROC_REF(ui_act_new)))
	op("del_c", ui_act("del_c", arg("del_c", num())), then(PROC_REF(ui_act_del_c)))
	op("search", ui_act("search", arg("t1", schema_text(4096))), then(PROC_REF(ui_act_search)))
	op("print_p", ui_act("print_p"), then(PROC_REF(ui_act_print_p)))
	extend(TAG_UI, then(PROC_REF(ui_records_fresh), early = TRUE))
	// The record modals (the old ui_modal_opened()/ui_modal_answered()): a field is edited by a pick or by typing, as the field's kind says.
	op("edit", ui_act("modal:edit", arg("arguments")), needs(req(PROC_REF(edit_field_known), silent = TRUE)),
		asks(/datum/prompt/choice/medical_record_edit, fields = list("arguments" = arg_of("arguments"), "inline" = TRUE, "timeout" = 0), step = "edit_choice", when = PROC_REF(edit_by_choice)),
		asks(/datum/prompt/text/medical_record_edit, fields = list("arguments" = arg_of("arguments"), "inline" = TRUE, "timeout" = 0), step = "edit_text", when = PROC_REF(edit_by_text)),
		then(PROC_REF(modal_edit)))
	op("add_c", ui_act("modal:add_c", arg("arguments")), asks(/datum/prompt/text, fields = list("question" = "Please enter your message:", "inline" = TRUE, "timeout" = 0), step = "comment"), then(PROC_REF(modal_add_comment)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(med_data_emp)))

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

/// Physical slots retain the console's declared silicon reach, independently of window access.
/obj/machinery/computer/med_data/proc/records_slot_reachable(datum/act/op/A)
	var/mob/user = A.actor
	return user && read_once(user.Adjacent(src)) ? null : "you're too far away"

/// A silicon's interface reaches the physical ID slot: the console takes a silicon's Use as a hand's (every machine's silicon_hand() op),
/// so the slot is open to it; actor kinds are selected by requirements.
/obj/machinery/computer/med_data/proc/records_remote_slot_allowed(datum/act/op/A)
	return null

/// The named insertion uses the same checked transfer as the old ID-card slot.
/obj/machinery/computer/med_data/proc/insert_scan(datum/act/op/A)
	if(!move_into(src, nameof(scan), A.held, A.actor))
		return OP_DECLINE
	act_message_t(A.actor, src, MSG(records/inserted_id), A.held)
	tgui_interact(A.actor)
	return OP_OK

/// The slot's release policy is checked before an eject effect can run.
/obj/machinery/computer/med_data/proc/scan_removable(datum/act/op/A)
	var/obj/item/card/id/card = read_once(scan)
	return card ? read_once(release_refusal(card, A.actor)) : null

/// A card is physically removable even when the records window is unusable.
/obj/machinery/computer/med_data/proc/eject_scan(datum/act/op/A)
	var/obj/item/card/id/card = scan
	rel_take(src, nameof(scan))
	A.actor.put_in_hands(card)
	act_message_t(A.actor, src, MSG(records/ejected_id), card)
	return OP_OK

/// A physical click needs an empty, admitted hand; refused menu rows remain visible.
/obj/machinery/computer/med_data/proc/records_plain_hand(datum/act/op/A)
	if(A.held)
		return MSG(req_hand_full)
	return records_open_admission(A)

/// The old named hand operation's physical provider and machine checks are requirements,
/// so a menu can display the same refusal even when the actor has no qualifying hand.
/obj/machinery/computer/med_data/proc/records_open_admission(datum/act/op/A)
	if(A.authority & AUTH_ADMIN)
		return null
	var/mob/user = A.actor
	if(!user || isobserver(user))
		return "too far away"
	if(!read_once(user.Adjacent(src)))
		return "too far away"
	if(!read_once(user.can_provide_hands(A)))
		return MSG(records/no_provider)
	if(!read_once(user.operation_actor_capable()))
		return MSG(req_not_capable)
	return op_hand_refusal(A)

/// The explicit records menu entry preserves its fingerprint and window effect.
/obj/machinery/computer/med_data/proc/open_records(datum/act/op/A)
	add_fingerprint(A.actor)
	tgui_interact(A.actor)
	return OP_OK

/obj/machinery/computer/med_data/ui_data(datum/act/eval/A)
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
						var/area/bot_area = get_area(T)
						medbot["name"] = M.name
						medbot["area"] = bot_area.name
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

/// Every button first drops a record the data core no longer holds (the old window guard's side effects).
/obj/machinery/computer/med_data/proc/ui_records_fresh(datum/act/op/A)
	if(!(active1() in GLOB.data_core.general))
		rel_clear(src, nameof(active1))
	if(!(active2() in GLOB.data_core.medical))
		rel_clear(src, nameof(active2))
	return OP_OK

/obj/machinery/computer/med_data/proc/ui_act_cleartemp(datum/act/op/A)
	. = TRUE
	temp = null

/obj/machinery/computer/med_data/proc/ui_act_scan(datum/act/op/A)
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

/obj/machinery/computer/med_data/proc/ui_act_login(datum/act/op/A, login_type_arg)
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
		rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
		rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))
		screen = MED_DATA_R_LIST

/obj/machinery/computer/med_data/proc/ui_act_logout(datum/act/op/A)
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
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))

/obj/machinery/computer/med_data/proc/ui_act_screen(datum/act/op/A, screen_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	screen = clamp(screen_arg || 0, MED_DATA_R_LIST, MED_DATA_MEDBOT)
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))

/obj/machinery/computer/med_data/proc/ui_act_vir(datum/act/op/A, vir)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/v = ui_ref(vir, null, /datum/data/record)
	if(!istype(v))
		return FALSE
	tgui_modal_message(src, "virus", "", null, v.fields["tgui_description"])

/obj/machinery/computer/med_data/proc/ui_act_del_all(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	for(var/datum/data/record/R in GLOB.data_core.medical)
		spent(R)
	set_temp("All medical records deleted.")

/obj/machinery/computer/med_data/proc/ui_act_del_r(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active2())
		set_temp("Medical record deleted.")
		spent(active2())

/obj/machinery/computer/med_data/proc/ui_act_d_rec(datum/act/op/A, d_rec)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/general_record = ui_ref(d_rec, null, /datum/data/record)
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

/obj/machinery/computer/med_data/proc/ui_act_sync_r(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active2())
		set_temp(client_update_record(src,A.actor))

/obj/machinery/computer/med_data/proc/ui_act_edit_notes(datum/act/op/A)
	if(!active2())
		return OP_OK
	var/new_notes = strip_html_simple(A.step_value("notes"), MAX_RECORD_LENGTH)
	if(new_notes != "")
		set_record_notes(active2(), new_notes)
	else if(A.step_value("delete_notes"))
		var/datum/prompt/yes_no/record_notes_delete/R = A.answer
		set_record_notes(R.record, "")
	return OP_OK

/obj/machinery/computer/med_data/proc/notes_empty(datum/act/op/A)
	return !!active2() && strip_html_simple(A.step_value("notes"), MAX_RECORD_LENGTH) == ""

/obj/machinery/computer/med_data/proc/notes_record(datum/act/op/A)
	return active2()

/obj/machinery/computer/med_data/proc/notes_default(datum/act/A)
	return html_decode(active2()?.fields["notes"])

/// The operator is logged in (the old handlers each refused without it).
/obj/machinery/computer/med_data/proc/records_authenticated(datum/act/op/A)
	return read_once(authenticated) ? null : MSG(records/not_authenticated)

/obj/machinery/computer/med_data/proc/ui_act_new(datum/act/op/A)
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
		rel_add(GLOB.data_core, nameof(/datum/datacore::medical), R)
		rel_set(src, nameof(/obj/machinery/computer/med_data::active2), R)
		screen = MED_DATA_RECORD
		set_temp("Medical record created.", "success")

/obj/machinery/computer/med_data/proc/ui_act_del_c(datum/act/op/A, del_c)
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

/obj/machinery/computer/med_data/proc/ui_act_search(datum/act/op/A, t1_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active2))
	var/t1 = lowertext(t1_arg || "")
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

/obj/machinery/computer/med_data/proc/ui_act_print_p(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!printing)
		printing = TRUE
		SStgui.update_uis(src)
		after(src, 5 SECONDS, PROC_REF(print_finish))

/obj/machinery/computer/med_data/proc/set_record_notes(datum/data/record/R, notes)
	if(R == active2())
		active2().fields["notes"] = notes
		SStgui.update_uis(src)

/// Empty notes: confirm clearing the record's notes (medical, security and employment records).
/datum/prompt/yes_no/record_notes_delete
	title = "Confirm Delete"
	question = "Are you sure you want to delete the current record's notes?"
	yes_text = "Delete"
	var/datum/data/record/record

CAPABILITIES(/datum/prompt/yes_no/record_notes_delete)
	ref_one(nameof(record), /datum/data/record)

MSG_DEF_SELF(records/not_authenticated, "You must log in first.")

/// The record field the edit modal names (`arguments["field"]`), when this console can edit it.
/obj/machinery/computer/med_data/proc/edit_field(list/arguments)
	var/field = islist(arguments) ? arguments["field"] : null
	return (length(field) && field_edit_questions[field]) ? field : null

/// Requirement: the edit modal names a field this console edits (silently refused otherwise, as the old modal never opened).
/obj/machinery/computer/med_data/proc/edit_field_known(datum/act/op/A)
	return isnull(edit_field(A.args["arguments"])) ? MSG(records/unknown_field) : null

/// The field is edited by picking from its choices.
/obj/machinery/computer/med_data/proc/edit_by_choice(datum/act/op/A)
	return length(field_edit_choices[edit_field(A.args["arguments"])]) > 0

/// The field is edited by typing.
/obj/machinery/computer/med_data/proc/edit_by_text(datum/act/op/A)
	return !edit_by_choice(A)

/// Argument-derived fields are prepared on the typed request, after arg_of() supplies the checked modal arguments.
/datum/prompt/choice/medical_record_edit
	var/list/arguments

/datum/prompt/choice/medical_record_edit/prepare(datum/act/op/A)
	..()
	var/obj/machinery/computer/med_data/console = A.holder
	var/field = console.edit_field(arguments)
	question = console.field_edit_questions[field]
	choices = console.field_edit_choices[field]
	default = islist(arguments) ? arguments["value"] : null

/datum/prompt/text/medical_record_edit
	var/list/arguments

/datum/prompt/text/medical_record_edit/prepare(datum/act/op/A)
	..()
	var/obj/machinery/computer/med_data/console = A.holder
	question = console.field_edit_questions[console.edit_field(arguments)]
	default = islist(arguments) ? arguments["value"] : null

/// The edit modal's answer goes into the record field.
/obj/machinery/computer/med_data/proc/modal_edit(datum/act/op/A, list/arguments)
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

	if(istype(active2(), /datum/data/record) && (field in active2().fields))
		active2().fields[field] = answer
	else if(istype(active1(), /datum/data/record) && (field in active1().fields))
		active1().fields[field] = answer

/// The comment modal's answer is added to the record's log.
/obj/machinery/computer/med_data/proc/modal_add_comment(datum/act/op/A, list/arguments)
	var/answer = A.step_value("comment")
	. = TRUE
	if(!length(answer) || !istype(active2(), /datum/data/record) || !length(authenticated))
		return
	active2().fields["comments"] += list(list(
		header = "Made by [authenticated] ([rank]) at [worldtime2stationtime(world.time)]",
		text = answer
	))
/**
 * Called when the print timer finishes
 */
/obj/machinery/computer/med_data/proc/print_finish()
	var/obj/item/paper/P = new(loc)
	P.set_info("<center>" + span_bold("Medical Record") + "</center><br>")
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
	if(istype(active2(), /datum/data/record) && (active2() in GLOB.data_core.medical))
		P.set_info(P.info + ({"<br>\n<center><b>Medical Data</b></center>
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
		<center><b>Comments/Log</b></center><br>"}))
		for(var/c in active2().fields["comments"])
			P.set_info(P.info + ("[c["header"]]<br>[c["text"]]<br>"))
	else
		P.set_info(P.info + (span_bold("Medical Record Lost!") + "<br>"))
	P.set_info(P.info + ("</tt>"))
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

/// An EMP scrambles or wipes some of the records.
/obj/machinery/computer/med_data/proc/med_data_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
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
			destroyed(R, null, "emp")
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

/// The selected record (a relation view).
/obj/machinery/computer/med_data/proc/active1() as /datum/data/record
	return active1

/// The selected record (a relation view).
/obj/machinery/computer/med_data/proc/active2() as /datum/data/record
	return active2
