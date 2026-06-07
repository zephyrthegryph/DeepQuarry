// DQAdd — Language picker composite editor.
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

/datum/preference_editor/language/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("add_language")
			var/lang = params["language"]
			var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
			if(lang in alt)
				return PREF_UPDATE_UNCHANGED
			alt += lang
			preferences.update_preference_by_type(/datum/preference/alternate_languages, alt)
			return PREF_UPDATE_ACCEPTED
		if("remove_language")
			var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
			alt -= params["language"]
			preferences.update_preference_by_type(/datum/preference/alternate_languages, alt)
			return PREF_UPDATE_ACCEPTED
		if("set_prefix")
			// DQEdit — prompt the user for the prefix character. The TGUI side only sends
			// the slot index; we ask for the character here so the user can actually type it.
			var/list/prefixes = preferences.read_preference(/datum/preference/language_prefixes) || list()
			var/idx = text2num(params["index"])
			if(idx < 1 || idx > 3)
				return PREF_UPDATE_REJECTED
			var/current = prefixes.len >= idx ? prefixes[idx] : ""
			var/typed = tgui_input_text(user, "Prefix character for slot [idx] (single character)", "Language Prefix", current, 1)
			if(!typed)
				return PREF_UPDATE_UNCHANGED
			// tgui_input_text sleeps — re-verify prefs ownership.
			if(!user?.client?.prefs || user.client.prefs != preferences)
				return PREF_UPDATE_UNCHANGED
			if(length(typed) != 1)
				return PREF_UPDATE_REJECTED
			prefixes.len = max(prefixes.len, 3)
			prefixes[idx] = typed
			preferences.update_preference_by_type(/datum/preference/language_prefixes, prefixes)
			return PREF_UPDATE_ACCEPTED
		if("reset_prefixes")
			var/list/defaults = CONFIG_GET(str_list/language_prefixes)
			preferences.update_preference_by_type(/datum/preference/language_prefixes, defaults.Copy())
			return PREF_UPDATE_ACCEPTED
		if("set_custom_key")
			// DQEdit — prompt for the key. Replaces any prior binding for that key.
			var/list/keys = preferences.read_preference(/datum/preference/language_custom_keys) || list()
			var/lang = params["language"]
			var/typed = tgui_input_text(user, "Bind language '[lang]' to which single character?", "Language Key", null, 1)
			if(!typed)
				return PREF_UPDATE_UNCHANGED
			// tgui_input_text sleeps — re-verify prefs ownership.
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
			return PREF_UPDATE_ACCEPTED
		if("clear_custom_key")
			var/list/keys = preferences.read_preference(/datum/preference/language_custom_keys) || list()
			for(var/k in keys)
				if(keys[k] == params["language"])
					keys -= k
			preferences.update_preference_by_type(/datum/preference/language_custom_keys, keys)
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
