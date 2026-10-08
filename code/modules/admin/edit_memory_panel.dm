// Edit Memory admin panel — fully structured TGUI.
//
// Replaces the legacy `/datum/mind/proc/edit_memory` HTML body that
// shipped through admin_log_show with byond:// href links. Each
// objective row, antag template row, and ambition/role/memory edit
// becomes a typed React component + a tgui_act handler that calls
// the mind's own procs directly.
//
// Per-antag-type structured data: see /datum/antagonist/proc/get_panel_data
// (code/modules/admin/antag_panel_data.dm).

/datum/edit_memory_panel
	var/datum/mind/target_mind
	var/tmp/mob/admin_user
	var/list/shown_antag_blocks

/datum/edit_memory_panel/New(datum/mind/target_mind, mob/admin_user)
	..()
	rel_set(src, nameof(target_mind), target_mind)
	rel_set(src, nameof(admin_user), admin_user)

// The mind owns this panel (tgui_edit_memory_panel); target_mind is a plain relation back.

CAPABILITIES(/datum/edit_memory_panel)
	interface("EditMemoryPanel", rights = R_ADMIN|R_FUN|R_EVENT)
	op("edit_role", ui_act("edit_role"), asks(/datum/prompt/choice, fields = list("question" = "Select new role", "title" = "Assigned role", "choices" = computed(PROC_REF(ui_act_edit_role_a1_choices)), "default" = computed(PROC_REF(ui_act_edit_role_a1_default)), "timeout" = 0), step = "a1"), then(PROC_REF(ui_act_edit_role)))
	op("edit_memory", ui_act("edit_memory"), asks(/datum/prompt/text, fields = list("question" = "Write new memory", "title" = "Memory", "default" = computed(PROC_REF(ui_act_edit_memory_a2_default)), "multiline" = TRUE, "timeout" = 0), step = "a2"), then(PROC_REF(ui_act_edit_memory)))
	op("edit_ambitions", ui_act("edit_ambitions"), asks(/datum/prompt/text, fields = list("question" = "Enter a new ambition", "title" = "Ambition", "default" = computed(PROC_REF(ui_act_edit_ambitions_a3_default)), "multiline" = TRUE, "timeout" = 0), step = "a3"), then(PROC_REF(ui_act_edit_ambitions)))
	op("obj_toggle_complete", ui_act("obj_toggle_complete", arg("ref", schema_ref(/datum/objective))), then(PROC_REF(ui_act_obj_toggle_complete)))
	op("obj_delete", ui_act("obj_delete", arg("ref", schema_ref(/datum/objective))), then(PROC_REF(ui_act_obj_delete)))
	op("obj_announce", ui_act("obj_announce"), then(PROC_REF(ui_act_obj_announce)))
	op("obj_add", ui_act("obj_add"), then(PROC_REF(ui_act_obj_add)))
	op("refresh_antags", ui_act("refresh_antags"), then(PROC_REF(ui_act_refresh_antags)))
	op("antag_add", ui_act("antag_add", arg("id", schema_text(4096))), then(PROC_REF(ui_act_antag_add)))
	op("antag_remove", ui_act("antag_remove", arg("id", schema_text(4096))), then(PROC_REF(ui_act_antag_remove)))
	op("antag_equip", ui_act("antag_equip", arg("id", schema_text(4096))), then(PROC_REF(ui_act_antag_equip)))
	op("antag_unequip", ui_act("antag_unequip", arg("id")), then(PROC_REF(ui_act_antag_unequip)))
	op("antag_move_to_spawn", ui_act("antag_move_to_spawn", arg("id", schema_text(4096))), then(PROC_REF(ui_act_antag_move_to_spawn)))

/datum/edit_memory_panel/ui_opening(mob/user, datum/tgui/ui)
	snapshot_antag_blocks()

/datum/edit_memory_panel/ui_title(mob/user)
	return "Edit Memory: [target_mind?.name]"

/datum/edit_memory_panel/proc/snapshot_antag_blocks()
	var/list/blocks = list()
	if(target_mind && SSantag.all_antag_types)
		for(var/antag_type in SSantag.all_antag_types)
			var/datum/antagonist/A = SSantag.all_antag_types[antag_type]
			var/list/entry = A?.get_panel_data(target_mind)
			if(entry)
				blocks += list(entry)
	shown_antag_blocks = blocks

/datum/edit_memory_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/// /datum/edit_memory_panel's window data.
/datum/edit_memory_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!target_mind)
		data["alive"] = FALSE
		return data
	data["alive"] = TRUE
	data["name"] = target_mind.name
	data["real_name"] = (target_mind.current && target_mind.current.real_name != target_mind.name) ? target_mind.current.real_name : null
	data["key"] = target_mind.key
	data["synced"] = !!target_mind.active
	data["assigned_role"] = target_mind.assigned_role
	data["ambitions"] = target_mind.ambitions || ""
	data["memory"] = target_mind.memory || ""

	// Objectives
	var/list/objectives = list()
	var/num = 1
	if(target_mind.objectives)
		for(var/datum/objective/O in target_mind.objectives)
			objectives += list(list(
				"ref" = "\ref[O]",
				"num" = num,
				"text" = O.explanation_text,
				"completed" = !!O.completed,
			))
			num++
	data["objectives"] = objectives

	data["antag_blocks"] = shown_antag_blocks || list()
	return data

/datum/edit_memory_panel/proc/ui_gate(datum/act/op/A)
	if(!target_mind)
		return FALSE
	if(!admin_can(A.actor?.client, R_ADMIN|R_FUN|R_EVENT))
		return FALSE
	return TRUE

/datum/edit_memory_panel/proc/ui_act_edit_role_a1_choices(datum/act/op/A)
	return SSjob.occupations_by_name

/datum/edit_memory_panel/proc/ui_act_edit_role_a1_default(datum/act/op/A)
	return target_mind.assigned_role

/datum/edit_memory_panel/proc/ui_act_edit_role(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/new_role = A.step_value("a1")
	if(new_role)
		target_mind.assigned_role = new_role
	return TRUE

/datum/edit_memory_panel/proc/ui_act_edit_memory_a2_default(datum/act/op/A)
	return target_mind.memory

/datum/edit_memory_panel/proc/ui_act_edit_memory(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/new_memo = A.step_value("a2")
	if(!isnull(new_memo))
		target_mind.memory = new_memo
	return TRUE

/datum/edit_memory_panel/proc/ui_act_edit_ambitions_a3_default(datum/act/op/A)
	return target_mind.ambitions

/datum/edit_memory_panel/proc/ui_act_edit_ambitions(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/new_amb = A.step_value("a3")
	if(isnull(new_amb))
		return TRUE
	target_mind.ambitions = new_amb
	if(target_mind.current)
		to_chat(target_mind.current, span_warning("Your ambitions have been changed by higher powers, they are now: [target_mind.ambitions]"))
	log_and_message_admins("made [key_name(target_mind.current)]'s ambitions be '[target_mind.ambitions]'.")
	return TRUE

/datum/edit_memory_panel/proc/ui_act_obj_toggle_complete(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in ui_source_target_mind_objectives()))
		return FALSE
	var/datum/objective/O = ref
	if(istype(O))
		O.completed = !O.completed
	return TRUE

/datum/edit_memory_panel/proc/ui_act_obj_delete(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in ui_source_target_mind_objectives()))
		return FALSE
	var/datum/objective/O = ref
	if(istype(O))
		rel_remove(target_mind, nameof(target_mind.objectives), O)
	return TRUE

/datum/edit_memory_panel/proc/ui_act_obj_announce(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(target_mind.current)
		to_chat(target_mind.current, span_blue("Your current objectives:"))
		var/obj_count = 1
		for(var/datum/objective/objective in target_mind.objectives)
			to_chat(target_mind.current, span_bold("Objective #[obj_count]") + ": [objective.explanation_text]")
			obj_count++
	return TRUE

/datum/edit_memory_panel/proc/ui_act_obj_add(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	target_mind.begin_objective_add(user)
	return TRUE

/datum/edit_memory_panel/proc/ui_act_refresh_antags(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	snapshot_antag_blocks()
	return TRUE

/datum/edit_memory_panel/proc/ui_act_antag_add(datum/act/op/A, id)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/antagonist/A2 = SSantag.all_antag_types[id]
	if(A2 && A2.add_antagonist(target_mind, 1, 1, 0, 1, 1))
		log_admin("[key_name_admin(user)] made [key_name(target_mind)] into a [A2.role_text].")
	snapshot_antag_blocks()
	return TRUE

/datum/edit_memory_panel/proc/ui_act_antag_remove(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/datum/antagonist/A2 = SSantag.all_antag_types[id]
	if(A2)
		A2.remove_antagonist(target_mind)
	snapshot_antag_blocks()
	return TRUE

/datum/edit_memory_panel/proc/ui_act_antag_equip(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/datum/antagonist/A2 = SSantag.all_antag_types[id]
	if(A2 && target_mind.current)
		A2.equip(target_mind.current)
	return TRUE

/datum/edit_memory_panel/proc/ui_act_antag_unequip(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/datum/antagonist/A2 = SSantag.all_antag_types[id]
	if(A2 && target_mind.current)
		A2.unequip(target_mind.current)
	return TRUE

/datum/edit_memory_panel/proc/ui_act_antag_move_to_spawn(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/datum/antagonist/A2 = SSantag.all_antag_types[id]
	if(A2 && target_mind.current)
		A2.place_mob(target_mind.current)
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/datum/edit_memory_panel/proc/ui_source_target_mind_objectives()
	return target_mind.objectives

/datum/mind
	var/datum/edit_memory_panel/tgui_edit_memory_panel

/// The admin_user this refers to (a relation view: null once that is deleted).
/datum/edit_memory_panel/proc/admin_user() as /mob
	return admin_user
