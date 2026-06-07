// Edit Memory admin panel — fully structured TGUI.
//
// Replaces the legacy `/datum/mind/proc/edit_memory` HTML body that
// shipped through admin_log_show with byond:// href links. Each
// objective row, antag template row, and ambition/role/memory edit
// becomes a typed React component + a tgui_act handler that calls
// the same /datum/mind/Topic logic the legacy panel did.
//
// Per-antag-type structured data: see /datum/antagonist/proc/get_panel_data
// (modular_dq/code/modules/admin/antag_panel_data.dm).

/datum/edit_memory_panel
	var/datum/mind/target_mind
	var/mob/admin_user
	var/list/cached_antag_blocks

/datum/edit_memory_panel/New(datum/mind/target_mind, mob/admin_user)
	..()
	src.target_mind = target_mind
	src.admin_user = admin_user

/datum/edit_memory_panel/Destroy()
	if(target_mind?.tgui_edit_memory_panel == src)
		target_mind.tgui_edit_memory_panel = null
	target_mind = null
	admin_user = null
	cached_antag_blocks = null
	return ..()

/datum/edit_memory_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_FUN|R_EVENT)

/datum/edit_memory_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		snapshot_antag_blocks()
		ui = new(user, src, "EditMemoryPanel", "Edit Memory: [target_mind?.name]")
		ui.open()

/datum/edit_memory_panel/proc/snapshot_antag_blocks()
	var/list/blocks = list()
	if(target_mind && SSantag_job?.all_antag_types)
		for(var/antag_type in SSantag_job.all_antag_types)
			var/datum/antagonist/A = SSantag_job.all_antag_types[antag_type]
			var/list/entry = A?.get_panel_data(target_mind)
			if(entry)
				blocks += list(entry)
	cached_antag_blocks = blocks

/datum/edit_memory_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/edit_memory_panel/tgui_data(mob/user)
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

	data["antag_blocks"] = cached_antag_blocks || list()
	return data

/datum/edit_memory_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!target_mind)
		return
	if(!check_rights(R_ADMIN|R_FUN|R_EVENT))
		return

	switch(action)
		if("edit_role")
			var/new_role = tgui_input_list(ui.user, "Select new role", "Assigned role", SSjob.occupations_by_name, target_mind.assigned_role)
			if(new_role)
				target_mind.assigned_role = new_role
			SStgui.update_uis(src)
			return TRUE
		if("edit_memory")
			var/new_memo = tgui_input_text(ui.user, "Write new memory", "Memory", target_mind.memory, MAX_MESSAGE_LEN, TRUE, prevent_enter = TRUE)
			if(!isnull(new_memo))
				target_mind.memory = new_memo
			SStgui.update_uis(src)
			return TRUE
		if("edit_ambitions")
			var/new_amb = tgui_input_text(ui.user, "Enter a new ambition", "Ambition", target_mind.ambitions, MAX_MESSAGE_LEN, TRUE, prevent_enter = TRUE)
			if(isnull(new_amb))
				return TRUE
			target_mind.ambitions = new_amb
			if(target_mind.current)
				to_chat(target_mind.current, span_warning("Your ambitions have been changed by higher powers, they are now: [target_mind.ambitions]"))
			log_and_message_admins("made [key_name(target_mind.current)]'s ambitions be '[target_mind.ambitions]'.")
			SStgui.update_uis(src)
			return TRUE
		if("obj_toggle_complete")
			var/datum/objective/O = locate(params["ref"])
			if(istype(O))
				O.completed = !O.completed
			SStgui.update_uis(src)
			return TRUE
		if("obj_delete")
			var/datum/objective/O = locate(params["ref"])
			if(istype(O))
				target_mind.objectives -= O
				qdel(O)
			SStgui.update_uis(src)
			return TRUE
		if("obj_announce")
			if(target_mind.current)
				to_chat(target_mind.current, span_blue("Your current objectives:"))
				var/obj_count = 1
				for(var/datum/objective/objective in target_mind.objectives)
					to_chat(target_mind.current, span_bold("Objective #[obj_count]") + ": [objective.explanation_text]")
					obj_count++
			return TRUE
		if("obj_add")
			// Delegate to the legacy Topic handler since the add-objective
			// flow is many sub-prompts (target picker, text picker, etc.)
			// and re-implementing it here would duplicate ~150 lines. The
			// existing flow uses tgui_input_* prompts already.
			target_mind.Topic("obj_add=1", list("obj_add" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("refresh_antags")
			snapshot_antag_blocks()
			SStgui.update_uis(src)
			return TRUE
		if("antag_add")
			var/datum/antagonist/A = SSantag_job.all_antag_types[params["id"]]
			if(A && A.add_antagonist(target_mind, 1, 1, 0, 1, 1))
				log_admin("[key_name_admin(ui.user)] made [key_name(target_mind)] into a [A.role_text].")
			snapshot_antag_blocks()
			SStgui.update_uis(src)
			return TRUE
		if("antag_remove")
			var/datum/antagonist/A = SSantag_job.all_antag_types[params["id"]]
			if(A)
				A.remove_antagonist(target_mind)
			snapshot_antag_blocks()
			SStgui.update_uis(src)
			return TRUE
		if("antag_equip")
			var/datum/antagonist/A = SSantag_job.all_antag_types[params["id"]]
			if(A && target_mind.current)
				A.equip(target_mind.current)
			SStgui.update_uis(src)
			return TRUE
		if("antag_unequip")
			var/datum/antagonist/A = SSantag_job.all_antag_types[params["id"]]
			if(A && target_mind.current)
				A.unequip(target_mind.current)
			SStgui.update_uis(src)
			return TRUE
		if("antag_move_to_spawn")
			var/datum/antagonist/A = SSantag_job.all_antag_types[params["id"]]
			if(A && target_mind.current)
				A.place_mob(target_mind.current)
			SStgui.update_uis(src)
			return TRUE


/datum/mind
	var/datum/edit_memory_panel/tgui_edit_memory_panel
