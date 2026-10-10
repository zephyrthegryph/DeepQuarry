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

CAPABILITIES(/datum/game_mode_panel)
	interface("GameModePanel", title = "Edit Game Mode", rights = R_ADMIN|R_EVENT)
	op("toggle", ui_act("toggle", arg("key", schema_text(4096))), then(PROC_REF(ui_act_toggle)))
	op("set", ui_act("set", arg("key", schema_text(4096))), then(PROC_REF(ui_act_set)))
	op("debug_antag", ui_act("debug_antag", arg("id", schema_text(4096))), then(PROC_REF(ui_act_debug_antag)))
	op("remove_antag_type", ui_act("remove_antag_type", arg("id", schema_text(4096))), then(PROC_REF(ui_act_remove_antag_type)))
	op("add_antag_type", ui_act("add_antag_type"), then(PROC_REF(ui_act_add_antag_type)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))

/datum/game_mode_panel/ui_opening(mob/user, datum/tgui/ui)
	recompute_antag_caps()

/datum/game_mode_panel/proc/recompute_antag_caps()
	if(!target_mode?.antag_templates)
		return
	for(var/datum/antagonist/antag in target_mode.antag_templates)
		antag.update_current_antag_max()

/datum/game_mode_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/// /datum/game_mode_panel's window data.
/datum/game_mode_panel/ui_data(datum/act/eval/A)
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

/datum/game_mode_panel/proc/ui_gate(datum/act/op/A)
	if(!target_mode || !admin_can(A.actor?.client, R_ADMIN|R_EVENT))
		return FALSE
	return TRUE

/datum/game_mode_panel/proc/ui_act_toggle(datum/act/op/A, key_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	// Forward to the existing /game_mode Topic handler.
	var/key = "[key_arg]"
	topic_dispatch(target_mode, user, list("toggle" = key))
	SStgui.update_uis(src)
	return TRUE

/datum/game_mode_panel/proc/ui_act_set(datum/act/op/A, key_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/key = "[key_arg]"
	topic_dispatch(target_mode, user, list("set" = key))
	SStgui.update_uis(src)
	return TRUE

/datum/game_mode_panel/proc/ui_act_debug_antag(datum/act/op/A, id_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/id = "[id_arg]"
	topic_dispatch(target_mode, user, list("debug_antag" = id))
	return TRUE

/datum/game_mode_panel/proc/ui_act_remove_antag_type(datum/act/op/A, id_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/id = "[id_arg]"
	topic_dispatch(target_mode, user, list("remove_antag_type" = id))
	SStgui.update_uis(src)
	return TRUE

/datum/game_mode_panel/proc/ui_act_add_antag_type(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	topic_dispatch(target_mode, user, list("add_antag_type" = "1"))
	recompute_antag_caps()
	SStgui.update_uis(src)
	return TRUE

/datum/game_mode_panel/proc/ui_act_refresh(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	recompute_antag_caps()
	SStgui.update_uis(src)
	return TRUE

/datum/game_mode
	var/datum/game_mode_panel/tgui_game_mode_panel

CAPABILITIES(/datum/game_mode)
	every(2 SECONDS, then(PROC_REF(mode_step)), when = nameof(mode_running))
	owns_one(nameof(tgui_game_mode_panel), /datum/game_mode_panel)
	op("toggle", topic("toggle", arg("toggle", schema_text(), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT)), then(PROC_REF(topic_toggle)))
	op("set", topic("set", arg("set", schema_text(), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT)), asks(/datum/prompt/number/game_mode_option, fields = list("question" = computed(PROC_REF(game_mode_option_question)), "window_max" = computed(PROC_REF(game_mode_option_max))), step = "value"), then(PROC_REF(topic_set)))
	op("debug_antag", topic("debug_antag", arg("debug_antag", schema_text(), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT)), then(PROC_REF(topic_debug_antag)))
	op("remove_antag_type", topic("remove_antag_type", arg("remove_antag_type", schema_text(), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT)), then(PROC_REF(topic_remove_antag_type)))
	op("add_antag_type", topic("add_antag_type"), needs(req_rights(R_ADMIN|R_EVENT)), asks(/datum/prompt/choice, fields = list("title" = "Select Antag Type", "question" = "Which type do you wish to add?", "choices" = computed(PROC_REF(antag_type_choices)), "rights" = R_ADMIN|R_SERVER, "timeout" = 0), step = "type"), then(PROC_REF(topic_add_antag_type)))

/proc/open_game_mode_panel(mob/user)
	if(!SSticker || !ticker_mode())
		tgui_alert_async(user, "Not before roundstart!", "Alert")
		return
	if(!ticker_mode().tgui_game_mode_panel)
		rel_set(ticker_mode(), nameof(/datum/game_mode::tgui_game_mode_panel), new /datum/game_mode_panel(ticker_mode()))
	ticker_mode().tgui_game_mode_panel.tgui_interact(user)
