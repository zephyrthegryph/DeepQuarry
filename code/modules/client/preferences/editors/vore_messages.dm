// Vore thermal messages editor. custom_heat / custom_cold each hold a list of
// strings displayed when the character is exposed to that temperature extreme. The user
// can add, edit, and remove individual messages.

/datum/preference_editor/vore_messages
	key = "vore_messages"
	category = "game"
	group = "roleplay"
	sort_order = 50
	display_name = "Hot & Cold Messages"
	pref_keys = list("custom_heat", "custom_cold")

/datum/preference_editor/vore_messages/build_ui_data(datum/preferences/preferences)
	return list(
		"heat" = preferences.read_preference(/datum/preference/custom_heat) || list(),
		"cold" = preferences.read_preference(/datum/preference/custom_cold) || list(),
	)

UI_ACT(/datum/preference_editor/vore_messages, "add_message", ui_act_add_message, UI_ARG_TEXT("text"), UI_ARG_TEXT("which"))
UI_ACT_PREF_PROC(/datum/preference_editor/vore_messages, ui_act_add_message)
	var/which = params["which"]
	var/pref_type = which == "heat" ? /datum/preference/custom_heat : /datum/preference/custom_cold
	var/list/messages = preferences.read_preference(pref_type) || list()
	if(which != "heat" && which != "cold")
		return FALSE
	var/text = strip_html_simple(trim(params["text"] || ""))
	if(!text || length(text) > 400)
		return PREF_UPDATE_REJECTED
	if(messages.len >= 10)
		return PREF_UPDATE_REJECTED
	messages += text
	preferences.update_preference_by_type(pref_type, messages)
	return PREF_UPDATE_ACCEPTED

UI_ACT(/datum/preference_editor/vore_messages, "edit_message", ui_act_edit_message, UI_ARG_NUM("index"), UI_ARG_TEXT("text"), UI_ARG_TEXT("which"))
UI_ACT_PREF_PROC(/datum/preference_editor/vore_messages, ui_act_edit_message)
	var/which = params["which"]
	var/pref_type = which == "heat" ? /datum/preference/custom_heat : /datum/preference/custom_cold
	var/list/messages = preferences.read_preference(pref_type) || list()
	if(which != "heat" && which != "cold")
		return FALSE
	var/index = params["index"]
	var/text = strip_html_simple(trim(params["text"] || ""))
	if(!index || index < 1 || index > messages.len)
		return PREF_UPDATE_REJECTED
	if(!text || length(text) > 400)
		return PREF_UPDATE_REJECTED
	messages[index] = text
	preferences.update_preference_by_type(pref_type, messages)
	return PREF_UPDATE_ACCEPTED

UI_ACT(/datum/preference_editor/vore_messages, "remove_message", ui_act_remove_message, UI_ARG_NUM("index"), UI_ARG_TEXT("which"))
UI_ACT_PREF_PROC(/datum/preference_editor/vore_messages, ui_act_remove_message)
	var/which = params["which"]
	var/pref_type = which == "heat" ? /datum/preference/custom_heat : /datum/preference/custom_cold
	var/list/messages = preferences.read_preference(pref_type) || list()
	if(which != "heat" && which != "cold")
		return FALSE
	var/index = params["index"]
	if(!index || index < 1 || index > messages.len)
		return PREF_UPDATE_REJECTED
	messages.Cut(index, index + 1)
	preferences.update_preference_by_type(pref_type, messages)
	return PREF_UPDATE_ACCEPTED
