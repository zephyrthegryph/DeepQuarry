// Map verify report — structured TGUI panel for admin map-load diagnostics.

CAPABILITIES(/datum/map_report)
	interface("MapReport", rights = R_ADMIN|R_DEBUG)
	ui_shape(original_path = any, crashed = bool(), loadable = bool(), bad_paths = list_of(), bad_keys = list_of())
	op("show", topic("show"), needs(req_rights(R_ADMIN)), then(PROC_REF(topic_show)))

/datum/map_report/ui_title(mob/user)
	return "Report for map file [original_path]"

/datum/map_report/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["original_path"] = original_path
	var/list/merged_1 = ui_data_datum_map_report(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/map_report's window data.
/datum/map_report/proc/ui_data_datum_map_report(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["crashed"] = !!crashed
	data["loadable"] = !!loadable
	var/list/path_rows = list()
	for(var/path in bad_paths)
		var/list/keys = LAZYACCESS(bad_paths, path)
		path_rows += list(list("path" = "[path]", "keys" = keys.Copy()))
	data["bad_paths"] = path_rows
	var/list/key_rows = list()
	for(var/key in bad_keys)
		var/list/messages = LAZYACCESS(bad_keys, key)
		key_rows += list(list("key" = "[key]", "messages" = messages.Copy()))
	data["bad_keys"] = key_rows
	return data

/datum/map_report/show_to(client/C)
	tgui_interact(C.mob)
