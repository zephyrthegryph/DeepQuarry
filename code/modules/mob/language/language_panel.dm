// Known Languages — structured TGUI replacing the legacy admin_log_show panel.

/proc/dq_open_languages_panel(mob/source, mob/user)
	if(!istype(user))
		return
	var/key = "[REF(source)]"
	var/datum/languages_panel/panel = LAZYACCESS(GLOB.dq_languages_panels, key)
	if(!panel)
		panel = new(source)
		GLOB.dq_languages_panels[key] = panel
	panel.tgui_interact(user)

GLOBAL_LIST_EMPTY(dq_languages_panels)

/datum/languages_panel
	var/mob/host

/datum/languages_panel/New(mob/host_mob)
	rel_set(src, nameof(host), host_mob)

/// Phase 2: leaves the per-host panel index.
/datum/languages_panel/lifecycle_dematerialize()
	. = ..()
	if(host)
		GLOB.dq_languages_panels -= "[REF(host)]"

CAPABILITIES(/datum/languages_panel)
	interface("LanguagesPanel", title = "Known Languages", state = nameof(GLOB.tgui_always_state))
	op("set_default", ui_act("set_default", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_set_default)))
	op("reset_default", ui_act("reset_default"), then(PROC_REF(ui_act_reset_default)))
	op("edit_key", ui_act("edit_key", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_edit_key)))

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
			"ref" = "\ref[lang]",
			"name" = lang.name,
			"key" = lang.key,
			"custom_key" = lang_key,
			"description" = lang.desc,
			"can_speak" = !!can_speak_lang,
			"is_default" = (lang == default_lang),
		))
	data["languages"] = rows
	return data

/datum/languages_panel/proc/ui_gate(datum/act/op/A)
	if(!host)
		return FALSE
	return TRUE

/datum/languages_panel/proc/ui_act_set_default(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/ref = "[ref_arg]"
	topic_dispatch(host, user, list("default_lang" = ref))
	SStgui.update_uis(src)
	return TRUE

/datum/languages_panel/proc/ui_act_reset_default(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	topic_dispatch(host, user, list("default_lang" = "reset"))
	SStgui.update_uis(src)
	return TRUE

/datum/languages_panel/proc/ui_act_edit_key(datum/act/op/A, ref_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/ref = "[ref_arg]"
	topic_dispatch(host, user, list("set_lang_key" = ref))
	SStgui.update_uis(src)
	return TRUE

// Known Languages verb now opens a structured TGUI panel.
/mob/verb/check_languages()
	set name = "Check Known Languages"
	set category = VERB_CAT_IC_GAME
	set src = usr
	dq_open_languages_panel(src, src)

