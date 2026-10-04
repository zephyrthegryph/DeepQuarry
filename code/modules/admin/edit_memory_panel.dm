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

DECLARE_UI_STATE(/datum/edit_memory_panel, ADMIN_STATE(R_ADMIN|R_FUN|R_EVENT))

DECLARE_UI(/datum/edit_memory_panel, "EditMemoryPanel")

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
	qdel(src)

UI_DATA_REPLACE(/datum/edit_memory_panel, "merge:ui_data_datum_edit_memory_panel{alive:bool,name:text,real_name:text,key:text,synced:bool,assigned_role:unknown,ambitions:bool,memory:bool,objectives:list,antag_blocks:bool}")

/// The computed part of /datum/edit_memory_panel's window data (declared on its UI_DATA row).
/datum/edit_memory_panel/proc/ui_data_datum_edit_memory_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/edit_memory_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!target_mind)
		return FALSE
	if(!check_rights(R_ADMIN|R_FUN|R_EVENT))
		return FALSE
	return TRUE

UI_ACT(/datum/edit_memory_panel, "edit_role", ui_act_edit_role)
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_edit_role)
	var/new_role = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/choice, message = "Select new role", title = "Assigned role", choices = SSjob.occupations_by_name, default = target_mind.assigned_role)
	if(isnull(new_role))
		return
	if(new_role)
		target_mind.assigned_role = new_role
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "edit_memory", ui_act_edit_memory)
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_edit_memory)
	var/new_memo = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/text, message = "Write new memory", title = "Memory", default = target_mind.memory, multiline = TRUE)
	if(isnull(new_memo))
		return
	if(!isnull(new_memo))
		target_mind.memory = new_memo
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "edit_ambitions", ui_act_edit_ambitions)
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_edit_ambitions)
	var/new_amb = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/text, message = "Enter a new ambition", title = "Ambition", default = target_mind.ambitions, multiline = TRUE)
	if(isnull(new_amb))
		return
	if(isnull(new_amb))
		return TRUE
	target_mind.ambitions = new_amb
	if(target_mind.current)
		to_chat(target_mind.current, span_warning("Your ambitions have been changed by higher powers, they are now: [target_mind.ambitions]"))
	log_and_message_admins("made [key_name(target_mind.current)]'s ambitions be '[target_mind.ambitions]'.")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "obj_toggle_complete", ui_act_obj_toggle_complete, UI_ARG_REF("ref", "proc:ui_source_target_mind_objectives", /datum/objective))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_obj_toggle_complete)
	var/datum/objective/O = params["ref"]
	if(istype(O))
		O.completed = !O.completed
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "obj_delete", ui_act_obj_delete, UI_ARG_REF("ref", "proc:ui_source_target_mind_objectives", /datum/objective))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_obj_delete)
	var/datum/objective/O = params["ref"]
	if(istype(O))
		own_remove(target_mind, nameof(target_mind.objectives), O)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "obj_announce", ui_act_obj_announce)
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_obj_announce)
	if(target_mind.current)
		to_chat(target_mind.current, span_blue("Your current objectives:"))
		var/obj_count = 1
		for(var/datum/objective/objective in target_mind.objectives)
			to_chat(target_mind.current, span_bold("Objective #[obj_count]") + ": [objective.explanation_text]")
			obj_count++
	return TRUE

UI_ACT(/datum/edit_memory_panel, "obj_add", ui_act_obj_add)
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_obj_add)
	target_mind.begin_objective_add(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "refresh_antags", ui_act_refresh_antags)
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_refresh_antags)
	snapshot_antag_blocks()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "antag_add", ui_act_antag_add, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_antag_add)
	var/datum/antagonist/A = SSantag.all_antag_types[params["id"]]
	if(A && A.add_antagonist(target_mind, 1, 1, 0, 1, 1))
		log_admin("[key_name_admin(ui.user)] made [key_name(target_mind)] into a [A.role_text].")
	snapshot_antag_blocks()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "antag_remove", ui_act_antag_remove, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_antag_remove)
	var/datum/antagonist/A = SSantag.all_antag_types[params["id"]]
	if(A)
		A.remove_antagonist(target_mind)
	snapshot_antag_blocks()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "antag_equip", ui_act_antag_equip, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_antag_equip)
	var/datum/antagonist/A = SSantag.all_antag_types[params["id"]]
	if(A && target_mind.current)
		A.equip(target_mind.current)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "antag_unequip", ui_act_antag_unequip, UI_ARG_VALUE("id"))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_antag_unequip)
	var/datum/antagonist/A = SSantag.all_antag_types[params["id"]]
	if(A && target_mind.current)
		A.unequip(target_mind.current)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/edit_memory_panel, "antag_move_to_spawn", ui_act_antag_move_to_spawn, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/edit_memory_panel, ui_act_antag_move_to_spawn)
	var/datum/antagonist/A = SSantag.all_antag_types[params["id"]]
	if(A && target_mind.current)
		A.place_mob(target_mind.current)
	SStgui.update_uis(src)
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/datum/edit_memory_panel/proc/ui_source_target_mind_objectives()
	return target_mind.objectives

/datum/mind
	var/datum/edit_memory_panel/tgui_edit_memory_panel

/// The admin_user this refers to (a relation view: null once that is deleted).
/datum/edit_memory_panel/proc/admin_user() as /mob
	return admin_user
