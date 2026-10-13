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

CAPABILITIES(/datum/spawn_menu)
	interface("SpawnSearch", rights = R_SPAWN)
	op("setRegexSearch", ui_act("setRegexSearch", arg("regexSearch", bool())), then(PROC_REF(ui_act_setregexsearch)))
	op("setNameSearch", ui_act("setNameSearch", arg("searchNames", bool())), then(PROC_REF(ui_act_setnamesearch)))
	op("setFancyTypes", ui_act("setFancyTypes", arg("fancyTypes", bool())), then(PROC_REF(ui_act_setfancytypes)))
	op("setIncludeAbstracts", ui_act("setIncludeAbstracts", arg("includeAbstracts", bool())), then(PROC_REF(ui_act_setincludeabstracts)))
	op("spawn", ui_act("spawn", arg("amount", num()), arg("type", schema_path(/datum))), then(PROC_REF(ui_act_spawn)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))

/datum/spawn_menu/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_SPAWN))
		return FALSE
	return TRUE

/datum/spawn_menu/proc/ui_act_setregexsearch(datum/act/op/A, regexSearch)
	if(!ui_gate(A))
		return FALSE
	regex_search = regexSearch
	return TRUE

/datum/spawn_menu/proc/ui_act_setnamesearch(datum/act/op/A, searchNames)
	if(!ui_gate(A))
		return FALSE
	name_search = searchNames
	return TRUE

/datum/spawn_menu/proc/ui_act_setfancytypes(datum/act/op/A, fancyTypes)
	if(!ui_gate(A))
		return FALSE
	fancy_types = fancyTypes
	return TRUE

/datum/spawn_menu/proc/ui_act_setincludeabstracts(datum/act/op/A, includeAbstracts)
	if(!ui_gate(A))
		return FALSE
	include_abstracts = includeAbstracts
	return TRUE

/datum/spawn_menu/proc/ui_act_spawn(datum/act/op/A, amount_arg, type)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/path = type
	if (!path)
		return TRUE
	var/amount = clamp(amount_arg || 1, 1, ADMIN_SPAWN_CAP)
	var/turf/target_turf = get_turf(user)
	if(ispath(path, /turf))
		target_turf.ChangeTurf(path)
	else
		for(var/i in 1 to amount)
			var/atom/spawned = new path(target_turf)
			spawned.flags |= ADMIN_SPAWNED

	log_admin("[key_name(user)] spawned [amount] x [path] at [AREACOORD(user)]")
	SStgui.close_uis(src)
	return TRUE

/datum/spawn_menu/proc/ui_act_cancel(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	SStgui.close_uis(src)
	return TRUE

/datum/spawn_menu/ui_data(datum/act/eval/A)
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
