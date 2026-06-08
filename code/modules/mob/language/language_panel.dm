// Known Languages — structured TGUI replacing the legacy admin_log_show panel.

/mob/proc/dq_open_languages_panel(mob/user)
	if(!istype(user))
		return
	var/key = "[REF(src)]"
	var/datum/languages_panel/panel = LAZYACCESS(GLOB.dq_languages_panels, key)
	if(!panel)
		panel = new(src)
		GLOB.dq_languages_panels[key] = panel
	panel.tgui_interact(user)

GLOBAL_LIST_EMPTY(dq_languages_panels)

/datum/languages_panel
	var/mob/host

/datum/languages_panel/New(mob/host_mob)
	host = host_mob

/datum/languages_panel/Destroy(force, ...)
	if(host)
		GLOB.dq_languages_panels -= "[REF(host)]"
	host = null
	return ..()

/datum/languages_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/languages_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LanguagesPanel", "Known Languages")
		ui.open()

/datum/languages_panel/tgui_data(mob/user)
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

/datum/languages_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(. || !host)
		return
	switch(action)
		if("set_default")
			var/ref = "[params["ref"]]"
			host.Topic("default_lang=[ref]", list("default_lang" = ref))
			SStgui.update_uis(src)
			return TRUE
		if("reset_default")
			host.Topic("default_lang=reset", list("default_lang" = "reset"))
			SStgui.update_uis(src)
			return TRUE
		if("edit_key")
			var/ref = "[params["ref"]]"
			host.Topic("set_lang_key=[ref]", list("set_lang_key" = ref))
			SStgui.update_uis(src)
			return TRUE

// Known Languages verb now opens a structured TGUI panel.
/mob/verb/check_languages()
	set name = "Check Known Languages"
	set category = "IC.Game"
	set src = usr
	dq_open_languages_panel(src)
