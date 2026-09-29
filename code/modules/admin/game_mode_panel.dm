// Edit Game Mode admin panel — structured TGUI.
//
// Replaces the legacy "Show Game Mode" HTML body. The current /game_mode
// Topic handler stays unchanged; we just expose its state as typed
// tgui_data and dispatch the same toggles / set= actions via tgui_act.

/datum/game_mode_panel
	var/datum/game_mode/target_mode

/datum/game_mode_panel/New(datum/game_mode/target_mode)
	..()
	rel_set(src, nameof(target_mode), target_mode)

// The game mode owns this panel (tgui_game_mode_panel); target_mode is a plain relation back.

DECLARE_UI_STATE(/datum/game_mode_panel, ADMIN_STATE(R_ADMIN|R_EVENT))

DECLARE_UI(/datum/game_mode_panel, "GameModePanel", UI_TITLE("Edit Game Mode"))

/datum/game_mode_panel/ui_opening(mob/user, datum/tgui/ui)
	recompute_antag_caps()

/datum/game_mode_panel/proc/recompute_antag_caps()
	if(!target_mode?.antag_templates)
		return
	for(var/datum/antagonist/antag in target_mode.antag_templates)
		antag.update_current_antag_max()

/datum/game_mode_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

UI_DATA_REPLACE(/datum/game_mode_panel, "merge:ui_data_datum_game_mode_panel{alive:bool,mode_name:text,config_tag:unknown,ert_enabled:bool,respawn_allowed:bool,shuttle_delay:num,shuttle_auto_recall:bool,event_modifier_moderate:unknown,event_modifier_major:unknown,autotraitor:bool,antag_scaling_coeff:num,core_antag_tags:list,antag_templates:list}")

/// The computed part of /datum/game_mode_panel's window data (declared on its UI_DATA row).
/datum/game_mode_panel/proc/ui_data_datum_game_mode_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/game_mode_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!target_mode || !check_rights(R_ADMIN|R_EVENT))
		return FALSE
	return TRUE

UI_ACT(/datum/game_mode_panel, "toggle", ui_act_toggle, UI_ARG_TEXT("key"))
UI_ACT_PROC(/datum/game_mode_panel, ui_act_toggle)
	// Forward to the existing /game_mode Topic handler.
	var/key = "[params["key"]]"
	topic_dispatch(target_mode, ui.user, list("toggle" = key))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/game_mode_panel, "set", ui_act_set, UI_ARG_TEXT("key"))
UI_ACT_PROC(/datum/game_mode_panel, ui_act_set)
	var/key = "[params["key"]]"
	topic_dispatch(target_mode, ui.user, list("set" = key))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/game_mode_panel, "debug_antag", ui_act_debug_antag, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/game_mode_panel, ui_act_debug_antag)
	var/id = "[params["id"]]"
	topic_dispatch(target_mode, ui.user, list("debug_antag" = id))
	return TRUE

UI_ACT(/datum/game_mode_panel, "remove_antag_type", ui_act_remove_antag_type, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/game_mode_panel, ui_act_remove_antag_type)
	var/id = "[params["id"]]"
	topic_dispatch(target_mode, ui.user, list("remove_antag_type" = id))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/game_mode_panel, "add_antag_type", ui_act_add_antag_type)
UI_ACT_PROC(/datum/game_mode_panel, ui_act_add_antag_type)
	topic_dispatch(target_mode, ui.user, list("add_antag_type" = "1"))
	recompute_antag_caps()
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/game_mode_panel, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/game_mode_panel, ui_act_refresh)
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
		own_set(SSticker.mode, nameof(/datum/game_mode::tgui_game_mode_panel), new /datum/game_mode_panel(SSticker.mode))
	SSticker.mode.tgui_game_mode_panel.tgui_interact(user)
