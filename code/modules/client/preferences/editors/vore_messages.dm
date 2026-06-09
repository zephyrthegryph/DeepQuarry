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

/datum/preference_editor/vore_messages/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/which = params["which"]
	if(which != "heat" && which != "cold")
		return PREF_UPDATE_REJECTED
	var/pref_type = which == "heat" ? /datum/preference/custom_heat : /datum/preference/custom_cold
	var/list/messages = preferences.read_preference(pref_type) || list()

	switch(action)
		if("add_message")
			var/text = strip_html_simple(trim(params["text"] || ""))
			if(!text || length(text) > 400)
				return PREF_UPDATE_REJECTED
			if(messages.len >= 10)
				return PREF_UPDATE_REJECTED
			messages += text
			preferences.update_preference_by_type(pref_type, messages)
			return PREF_UPDATE_ACCEPTED
		if("edit_message")
			var/index = text2num(params["index"])
			var/text = strip_html_simple(trim(params["text"] || ""))
			if(!index || index < 1 || index > messages.len)
				return PREF_UPDATE_REJECTED
			if(!text || length(text) > 400)
				return PREF_UPDATE_REJECTED
			messages[index] = text
			preferences.update_preference_by_type(pref_type, messages)
			return PREF_UPDATE_ACCEPTED
		if("remove_message")
			var/index = text2num(params["index"])
			if(!index || index < 1 || index > messages.len)
				return PREF_UPDATE_REJECTED
			messages.Cut(index, index + 1)
			preferences.update_preference_by_type(pref_type, messages)
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
