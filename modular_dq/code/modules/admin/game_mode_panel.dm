// Edit Game Mode admin panel — structured TGUI.
//
// Replaces the legacy "Show Game Mode" HTML body. The current /game_mode
// Topic handler stays unchanged; we just expose its state as typed
// tgui_data and dispatch the same toggles / set= actions via tgui_act.

/datum/game_mode_panel
	var/datum/game_mode/target_mode

/datum/game_mode_panel/New(datum/game_mode/target_mode)
	..()
	src.target_mode = target_mode

/datum/game_mode_panel/Destroy()
	if(target_mode?.tgui_game_mode_panel == src)
		target_mode.tgui_game_mode_panel = null
	target_mode = null
	return ..()

/datum/game_mode_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT)

/datum/game_mode_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		recompute_antag_caps()
		ui = new(user, src, "GameModePanel", "Edit Game Mode")
		ui.open()

/datum/game_mode_panel/proc/recompute_antag_caps()
	if(!target_mode?.antag_templates)
		return
	for(var/datum/antagonist/antag in target_mode.antag_templates)
		antag.update_current_antag_max()

/datum/game_mode_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/game_mode_panel/tgui_data(mob/user)
	if(!target_mode)
		return list("alive" = FALSE)
	var/list/data = list("alive" = TRUE)
	data["mode_name"] = target_mode.name
	data["config_tag"] = target_mode.config_tag
	data["ert_enabled"] = !target_mode.ert_disabled
	data["respawn_allowed"] = !target_mode.deny_respawn
	data["shuttle_delay"] = target_mode.shuttle_delay
	data["shuttle_auto_recall"] = !!target_mode.auto_recall_shuttle
	data["event_modifier_moderate"] = target_mode.event_delay_mod_moderate
	data["event_modifier_major"] = target_mode.event_delay_mod_major
	data["autotraitor"] = !!target_mode.round_autoantag
	data["antag_scaling_coeff"] = target_mode.antag_scaling_coeff

	var/list/core_tags = list()
	if(target_mode.antag_tags)
		for(var/tag in target_mode.antag_tags)
			core_tags += tag
	data["core_antag_tags"] = core_tags

	var/list/antag_templates = list()
	if(target_mode.antag_templates)
		for(var/datum/antagonist/antag in target_mode.antag_templates)
			antag_templates += list(list(
				"id" = antag.id,
				"count" = antag.get_antag_count(),
				"cur_max" = antag.cur_max,
			))
	data["antag_templates"] = antag_templates
	return data

/datum/game_mode_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!target_mode || !check_rights(R_ADMIN|R_EVENT))
		return

	switch(action)
		if("toggle")
			// Forward to the existing /game_mode Topic handler.
			var/key = "[params["key"]]"
			target_mode.Topic("toggle=[key]", list("toggle" = key))
			SStgui.update_uis(src)
			return TRUE
		if("set")
			var/key = "[params["key"]]"
			target_mode.Topic("set=[key]", list("set" = key))
			SStgui.update_uis(src)
			return TRUE
		if("debug_antag")
			var/id = "[params["id"]]"
			target_mode.Topic("debug_antag=[id]", list("debug_antag" = id))
			return TRUE
		if("remove_antag_type")
			var/id = "[params["id"]]"
			target_mode.Topic("remove_antag_type=[id]", list("remove_antag_type" = id))
			SStgui.update_uis(src)
			return TRUE
		if("add_antag_type")
			target_mode.Topic("add_antag_type=1", list("add_antag_type" = "1"))
			recompute_antag_caps()
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
			recompute_antag_caps()
			SStgui.update_uis(src)
			return TRUE


/datum/game_mode
	var/datum/game_mode_panel/tgui_game_mode_panel

/proc/open_game_mode_panel(mob/user)
	if(!SSticker || !SSticker.mode)
		tgui_alert_async(user, "Not before roundstart!", "Alert")
		return
	if(!SSticker.mode.tgui_game_mode_panel)
		SSticker.mode.tgui_game_mode_panel = new(SSticker.mode)
	SSticker.mode.tgui_game_mode_panel.tgui_interact(user)
