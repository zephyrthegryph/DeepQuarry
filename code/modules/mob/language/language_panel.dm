// Known Languages — structured TGUI replacing the legacy admin_log_show panel.

/proc/dq_open_languages_panel(mob/source, mob/user)
	if(!istype(user))
		return
	var/key = ref_token(source)
	var/datum/languages_panel/panel = resolve_token(LAZYACCESS(GLOB.dq_languages_panels, key))
	if(!panel)
		panel = new(source)
		GLOB.dq_languages_panels[key] = ref_token(panel)
	panel.tgui_interact(user)

/// Open panels: host key -> the panel's ref_token (a deleted panel stops resolving).
GLOBAL_LIST_EMPTY(dq_languages_panels)

/datum/languages_panel
	var/mob/host

/datum/languages_panel/New(mob/host_mob)
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/languages_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_languages_panels -= ref_token(host)

CAPABILITIES(/datum/languages_panel)
	ref_one(nameof(host), /mob)
	interface("LanguagesPanel", title = "Known Languages", state = nameof(GLOB.tgui_always_state))
	op("set_default", ui_act("set_default", arg("language", schema_text(64))), needs(req(PROC_REF(req_own_languages)), req(PROC_REF(req_known_language))), then(PROC_REF(ui_act_set_default)))
	op("reset_default", ui_act("reset_default"), needs(req(PROC_REF(req_own_languages))), then(PROC_REF(ui_act_reset_default)))
	op("edit_key", ui_act("edit_key", arg("language", schema_text(64))), needs(req(PROC_REF(req_own_languages)), req(PROC_REF(req_known_language))), asks(/datum/prompt/text/language_key, fields = list("language" = computed(PROC_REF(arg_language))), step = "key"), then(PROC_REF(ui_act_edit_key)))

/// /datum/languages_panel's window data.
/datum/languages_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(!host)
		return data
	data["prefix"] = host.get_language_prefix()
	var/mob/living/L = host
	var/datum/language/default_lang = istype(L) ? L.default_language : null
	data["has_default"] = !!default_lang
	data["default_name"] = default_lang ? default_lang.name : null
	var/list/rows = list()
	for(var/datum/language/lang in host.languages)
		if(lang.flags & NONGLOBAL)
			continue
		var/lang_key = get_custom_prefix_by_lang(host, lang)
		var/can_speak_lang = TRUE
		if(istype(L))
			can_speak_lang = L.can_speak(lang)
		rows += list(list(
			"id" = lang.name,
			"name" = lang.name,
			"key" = lang.key,
			"custom_key" = lang_key,
			"description" = lang.desc,
			"can_speak" = !!can_speak_lang,
			"is_default" = (lang == default_lang),
		))
	data["languages"] = rows
	return data

/// Requirement: the languages are the viewer's own: a living mob's window, opened by the mob itself.
/datum/languages_panel/proc/req_own_languages(datum/act/op/A)
	return (istype(host, /mob/living) && A.actor == host) ? null : MSG(req_silent)

/// The language the button names, if the mob knows it (a name no known language bears is nothing).
/datum/languages_panel/proc/arg_language(datum/act/op/A)
	var/wanted = A.args ? A.args["language"] : null
	if(!istext(wanted) || !host)
		return null
	for(var/datum/language/L in host.languages)
		if(L.name == wanted)
			return L
	return null

/// Requirement: the button names a language the mob knows.
/datum/languages_panel/proc/req_known_language(datum/act/op/A)
	return read_once(arg_language(A)) ? null : MSG(req_silent)

/datum/languages_panel/proc/ui_act_set_default(datum/act/op/A, language)
	var/mob/living/L = host
	L.apply_default_language(arg_language(A))
	SStgui.update_uis(src)
	return OP_OK

/datum/languages_panel/proc/ui_act_reset_default(datum/act/op/A)
	var/mob/living/L = host
	if(L.species_language)
		L.apply_default_language(GLOB.all_languages[L.species_language])
	else
		L.apply_default_language(GLOB.all_languages[LANGUAGE_GIBBERISH])
	SStgui.update_uis(src)
	return OP_OK

/// The key a language is spoken with: asked when the button is pressed, set here (the answerer is still checked to know the language, by the prompt).
/datum/languages_panel/proc/ui_act_edit_key(datum/act/op/A, language)
	var/mob/living/M = host
	var/datum/language/L = arg_language(A)
	var/old_key = get_custom_prefix_by_lang(M, L)
	var/custom_key = A.step_value("key")
	if(custom_key && length(custom_key) == 1)
		if(contains_az09(custom_key))
			M.set_language_keys_at(custom_key, L)
			if(old_key && old_key != custom_key)
				M.remove_language_keys(old_key)
		else if(custom_key == " ")
			if(old_key && old_key != custom_key)
				M.remove_language_keys(old_key)
		else
			tgui_alert_async(M, "Improper language key. Rejected.", "Error")
	SStgui.update_uis(src)
	return OP_OK

// Known Languages verb now opens a structured TGUI panel.
/mob/verb/check_languages()
	set name = "Check Known Languages"
	set category = VERB_CAT_IC_GAME
	set src = usr
	dq_open_languages_panel(src, src)

