// Language picker composite editor: which alternates the character knows, which one they speak by default, and each one's key.
//
// Wire actions:
//   "add_language"    { language }
//   "remove_language" { language }
//   "set_preferred"   { language }
//   "set_key"         { language, key }   the whole prefix; refused when invalid or another known language holds it
//   "reset_key"       { language }        back to the language's own prefix

/datum/preference_editor/language
	key = "language"
	category = "identity"
	group = "language"
	sort_order = 10
	display_name = "Languages"
	pref_keys = list("alternate_languages", "language_custom_keys", "extra_languages", "preferred_language")

/// The languages this character may actually pick as alternates: the same rule the alternate_languages sanitizer applies
/// (not restricted, and either one of the species' secondary languages or open to this player), so the picker never offers
/// a language that is dropped the moment it is chosen. Keys of GLOB.all_languages.
/datum/preference_editor/language/proc/pickable_languages(datum/preferences/preferences)
	var/datum/species/S = GLOB.all_species[preferences.read_preference(/datum/preference/choiced/species)]
	var/client/C = preferences.client()
	. = list()
	for(var/key in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[key]
		if(!istype(L) || (L.flags & RESTRICTED))
			continue
		if(S && L.name == S.language)
			continue // already known: the species default
		if(S && !(key in S.secondary_langs) && C && !is_lang_whitelisted(C, L))
			continue
		. += key

/datum/preference_editor/language/build_ui_data(datum/preferences/preferences)
	var/datum/species/S = GLOB.all_species[preferences.read_preference(/datum/preference/choiced/species)]
	var/list/alt_languages = preferences.read_preference(/datum/preference/alternate_languages) || list()
	var/extra = preferences.read_preference(/datum/preference/numeric/human/extra_languages) || 0

	return list(
		"alternate_languages" = alt_languages,
		"language_keys" = preferences.language_key_map(),
		"known_languages" = preferences.known_language_names(),
		"preferred_language" = preferences.read_preference(/datum/preference/text/human/preferred_language),
		"extra_languages" = extra,
		"max_alternate_languages" = S ? (S.num_alternate_languages + extra) : extra,
		"pickable_languages" = pickable_languages(preferences),
	)

/datum/preference_editor/language/build_ui_static_data(datum/preferences/preferences)
	var/list/all_languages = list()
	for(var/key in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[key]
		all_languages[key] = list(
			"name" = L.name,
			"desc" = L.desc,
			"restricted" = (L.flags & RESTRICTED) ? TRUE : FALSE,
			"default_key" = (L.flags & NONGLOBAL) ? "" : language_default_prefix(L),
		)
	return list("all_languages" = all_languages)

/datum/preference_editor/language/proc/ui_act_add_language(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/lang = params["language"]
	var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
	if(lang in alt)
		return PREF_UPDATE_UNCHANGED
	if(!(lang in pickable_languages(preferences)))
		return PREF_UPDATE_REJECTED
	alt += lang
	preferences.update_preference_by_type(/datum/preference/alternate_languages, alt)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_remove_language(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
	alt -= params["language"]
	preferences.update_preference_by_type(/datum/preference/alternate_languages, alt)
	if(preferences.read_preference(/datum/preference/text/human/preferred_language) == params["language"])
		preferences.update_preference_by_type(/datum/preference/text/human/preferred_language, preferences.species_language_name())
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_set_preferred(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	if(!(params["language"] in preferences.known_language_names()))
		return PREF_UPDATE_REJECTED
	preferences.update_preference_by_type(/datum/preference/text/human/preferred_language, params["language"])
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/language/proc/ui_act_set_key(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/problem = preferences.set_language_key(params["language"], params["key"])
	if(problem)
		if(user)
			to_chat(user, span_warning("Language prefix refused: [problem]."))
		return PREF_UPDATE_REJECTED
	return PREF_UPDATE_ACCEPTED

/// Drops the saved key; the language's own applies again (language_key_map skips it while another language holds it).
/datum/preference_editor/language/proc/ui_act_reset_key(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/keys = preferences.read_preference(/datum/preference/language_custom_keys) || list()
	for(var/k in keys.Copy())
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
		if("set_preferred")
			typed = payload_args(src, params, list("language" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_preferred(user, typed, preferences, null, action)
		if("set_key")
			typed = payload_args(src, params, list("language" = null, "key" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_key(user, typed, preferences, null, action)
		if("reset_key")
			typed = payload_args(src, params, list("language" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_reset_key(user, typed, preferences, null, action)
	return ..()
