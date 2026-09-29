/datum/spawn_menu
	/// Does the menu default to a regex prefix?
	var/regex_search = FALSE
	/// Does the search include atom names?
	var/name_search = TRUE
	/// Should we display full typepaths or the condensed versions?
	var/fancy_types = TRUE
	/// Should abstract types be included in the search?
	var/include_abstracts = FALSE
	/// Initial search value from the latest command
	var/init_value = null

DECLARE_UI(/datum/spawn_menu, "SpawnSearch")

/datum/spawn_menu/tgui_state(mob/user)
	return ADMIN_STATE(R_SPAWN)

/datum/spawn_menu/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!check_rights_for(ui.user.client, R_SPAWN))
		return FALSE
	return TRUE

UI_ACT(/datum/spawn_menu, "setRegexSearch", ui_act_setregexsearch, UI_ARG_VALUE("regexSearch"))
UI_ACT_PROC(/datum/spawn_menu, ui_act_setregexsearch)
	regex_search = params["regexSearch"]
	return TRUE

UI_ACT(/datum/spawn_menu, "setNameSearch", ui_act_setnamesearch, UI_ARG_VALUE("searchNames"))
UI_ACT_PROC(/datum/spawn_menu, ui_act_setnamesearch)
	name_search = params["searchNames"]
	return TRUE

UI_ACT(/datum/spawn_menu, "setFancyTypes", ui_act_setfancytypes, UI_ARG_VALUE("fancyTypes"))
UI_ACT_PROC(/datum/spawn_menu, ui_act_setfancytypes)
	fancy_types = params["fancyTypes"]
	return TRUE

UI_ACT(/datum/spawn_menu, "setIncludeAbstracts", ui_act_setincludeabstracts, UI_ARG_VALUE("includeAbstracts"))
UI_ACT_PROC(/datum/spawn_menu, ui_act_setincludeabstracts)
	include_abstracts = params["includeAbstracts"]
	return TRUE

UI_ACT(/datum/spawn_menu, "spawn", ui_act_spawn, UI_ARG_NUM("amount"), UI_ARG_PATH("type", /datum))
UI_ACT_PROC(/datum/spawn_menu, ui_act_spawn)
	var/path = params["type"]
	if (!path)
		return TRUE
	var/amount = clamp(params["amount"] || 1, 1, ADMIN_SPAWN_CAP)
	var/turf/target_turf = get_turf(ui.user)
	if(ispath(path, /turf))
		target_turf.ChangeTurf(path)
	else
		for(var/i in 1 to amount)
			var/atom/spawned = new path(target_turf)
			spawned.flags |= ADMIN_SPAWNED

	log_admin("[key_name(ui.user)] spawned [amount] x [path] at [AREACOORD(ui.user)]")
	SStgui.close_uis(src)
	return TRUE

UI_ACT(/datum/spawn_menu, "cancel", ui_act_cancel)
UI_ACT_PROC(/datum/spawn_menu, ui_act_cancel)
	SStgui.close_uis(src)
	return TRUE

/datum/spawn_menu/tgui_data(mob/user)
	var/list/data = list()
	data["initValue"] = init_value
	data["searchNames"] = name_search
	data["regexSearch"] = regex_search
	data["fancyTypes"] = fancy_types
	data["includeAbstracts"] = include_abstracts
	return data

/datum/spawn_menu/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/json/spawn_menu),
	)

/datum/asset/json/spawn_menu
	name = "spawn_menu_atom_data"

/datum/asset/json/spawn_menu/generate()
	var/list/data = list()
	var/static/list/types_list
	if (isnull(types_list))
		var/list/local_types = list()
		for (var/atom/atom_type as anything in subtypesof(/atom))
			local_types[atom_type] = atom_type::name || ""
		types_list = local_types
	data["types"] = types_list
	data["abstractTypes"] = GLOBAL_TABLE_GET(get_abstract_types)
	data["fancyTypes"] = GLOB.fancy_type_replacements
	return data
