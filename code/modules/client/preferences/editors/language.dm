// Language picker composite editor.
// Manages alternate_languages list (species-aware available pool), language_prefixes
// (the 3 radio prefix keys), and language_custom_keys (per-language radio keybind).
//
// Wire actions:
//   "add_language"    { language: "language_name" }
//   "remove_language" { language }
//   "set_prefix"      { index: 1..3, char: "x" }
//   "reset_prefixes"
//   "set_custom_key"  { language, key }
//   "clear_custom_key" { language }

/datum/preference_editor/language
	key = "language"
	category = "identity"
	group = "language"
	sort_order = 10
	display_name = "Languages"
	pref_keys = list("alternate_languages", "language_prefixes", "language_custom_keys", "extra_languages", "preferred_language", "runechat_color")

/datum/preference_editor/language/build_ui_data(datum/preferences/preferences)
	var/datum/species/S = GLOB.all_species[preferences.read_preference(/datum/preference/choiced/species)]
	var/list/alt_languages = preferences.read_preference(/datum/preference/alternate_languages) || list()
	var/extra = preferences.read_preference(/datum/preference/numeric/human/extra_languages) || 0

	return list(
		"alternate_languages" = alt_languages,
		"language_prefixes" = preferences.read_preference(/datum/preference/language_prefixes) || list(),
		"language_custom_keys" = preferences.read_preference(/datum/preference/language_custom_keys) || list(),
		"preferred_language" = preferences.read_preference(/datum/preference/text/human/preferred_language),
		"runechat_color" = preferences.read_preference(/datum/preference/color/human/runechat_color),
		"extra_languages" = extra,
		"max_alternate_languages" = S ? (S.num_alternate_languages + extra) : extra,
		"species_default_language" = S ? S.language : null,
	)

/datum/preference_editor/language/build_ui_static_data(datum/preferences/preferences)
	var/list/all_languages = list()
	for(var/key in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[key]
		all_languages[key] = list(
			"name" = L.name,
			"desc" = L.desc,
			"restricted" = (L.flags & RESTRICTED) ? TRUE : FALSE,
		)
	return list("all_languages" = all_languages)

/datum/preference_editor/language/proc/ui_act_add_language(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/lang = params["language"]
	var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
	if(lang in alt)
		return PREF_UPDATE_UNCHANGED
	alt += lang
	preferences.update_preference_by_type(/datum/preference/alternate_languages, alt)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_remove_language(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
	alt -= params["language"]
	preferences.update_preference_by_type(/datum/preference/alternate_languages, alt)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_set_prefix(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// prompt the user for the prefix character. The TGUI side only sends
	// the slot index; we ask for the character here so the user can actually type it.
	var/list/prefixes = preferences.read_preference(/datum/preference/language_prefixes) || list()
	var/idx = params["index"]
	if(idx < 1 || idx > 3)
		return PREF_UPDATE_REJECTED
	var/current = prefixes.len >= idx ? prefixes[idx] : ""
	// The answer re-runs this action.
	var/typed = rerun_ask(user, "prefix", PROC_REF(handle_action), args, /datum/om/prompt/text, message = "Prefix character for slot [idx] (single character)", title = "Language Prefix", default = current, max_length = 1)
	if(!typed)
		return PREF_UPDATE_UNCHANGED
	if(!user?.client?.prefs || user.client.prefs != preferences)
		return PREF_UPDATE_UNCHANGED
	if(length(typed) != 1)
		return PREF_UPDATE_REJECTED
	prefixes.len = max(prefixes.len, 3)
	prefixes[idx] = typed
	preferences.update_preference_by_type(/datum/preference/language_prefixes, prefixes)
	SStgui.update_uis(preferences)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_reset_prefixes(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/defaults = CONFIG_GET(str_list/language_prefixes)
	preferences.update_preference_by_type(/datum/preference/language_prefixes, defaults.Copy())
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_set_custom_key(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// prompt for the key. Replaces any prior binding for that key.
	var/list/keys = preferences.read_preference(/datum/preference/language_custom_keys) || list()
	var/lang = params["language"]
	var/typed = rerun_ask(user, "key", PROC_REF(handle_action), args, /datum/om/prompt/text, message = "Bind language '[lang]' to which single character?", title = "Language Key", max_length = 1)
	if(!typed)
		return PREF_UPDATE_UNCHANGED
	if(!user?.client?.prefs || user.client.prefs != preferences)
		return PREF_UPDATE_UNCHANGED
	if(length(typed) != 1)
		return PREF_UPDATE_REJECTED
	// Strip any previous binding for the same language (one key per language).
	for(var/k in keys.Copy()) // mutation during iteration → iterate copy
		if(keys[k] == lang)
			keys -= k
	keys[typed] = lang
	preferences.update_preference_by_type(/datum/preference/language_custom_keys, keys)
	SStgui.update_uis(preferences)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_clear_custom_key(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/keys = preferences.read_preference(/datum/preference/language_custom_keys) || list()
	for(var/k in keys)
		if(keys[k] == params["language"])
			keys -= k
	preferences.update_preference_by_type(/datum/preference/language_custom_keys, keys)
	return PREF_UPDATE_ACCEPTED

/// /datum/preference_editor/language's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/language/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("add_language")
			typed = payload_args(src, params, list("language" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_add_language(user, typed, preferences, null, action)
		if("remove_language")
			typed = payload_args(src, params, list("language" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_remove_language(user, typed, preferences, null, action)
		if("set_prefix")
			typed = payload_args(src, params, list("index" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_prefix(user, typed, preferences, null, action)
		if("reset_prefixes")
			typed = payload_args(src, params, list())
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_reset_prefixes(user, typed, preferences, null, action)
		if("set_custom_key")
			typed = payload_args(src, params, list("language" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_custom_key(user, typed, preferences, null, action)
		if("clear_custom_key")
			typed = payload_args(src, params, list("language" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_clear_custom_key(user, typed, preferences, null, action)
	return ..()
