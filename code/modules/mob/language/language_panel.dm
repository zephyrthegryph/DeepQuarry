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

DECLARE_UI_STATE(/datum/languages_panel, GLOB.tgui_always_state)

DECLARE_UI(/datum/languages_panel, "LanguagesPanel", UI_TITLE("Known Languages"))

UI_DATA_REPLACE(/datum/languages_panel, "merge:ui_data_datum_languages_panel{prefix:unknown,has_default:bool,default_name:text,languages:list}")

/// The computed part of /datum/languages_panel's window data (declared on its UI_DATA row).
/datum/languages_panel/proc/ui_data_datum_languages_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/datum/languages_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!host)
		return FALSE
	return TRUE

UI_ACT(/datum/languages_panel, "set_default", ui_act_set_default, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/languages_panel, ui_act_set_default)
	var/ref = "[params["ref"]]"
	topic_dispatch(host, ui.user, list("default_lang" = ref))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/languages_panel, "reset_default", ui_act_reset_default)
UI_ACT_PROC(/datum/languages_panel, ui_act_reset_default)
	topic_dispatch(host, ui.user, list("default_lang" = "reset"))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/languages_panel, "edit_key", ui_act_edit_key, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/languages_panel, ui_act_edit_key)
	var/ref = "[params["ref"]]"
	topic_dispatch(host, ui.user, list("set_lang_key" = ref))
	SStgui.update_uis(src)
	return TRUE

// Known Languages verb now opens a structured TGUI panel.
/mob/verb/check_languages()
	set name = "Check Known Languages"
	set category = "IC.Game"
	set src = usr
	dq_open_languages_panel(src, src)

