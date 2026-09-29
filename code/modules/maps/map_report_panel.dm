// Map verify report — structured TGUI panel for admin map-load diagnostics.

DECLARE_UI_STATE(/datum/map_report, ADMIN_STATE(R_ADMIN|R_DEBUG))

DECLARE_UI(/datum/map_report, "MapReport")

/datum/map_report/ui_title(mob/user)
	return "Report for map file [original_path]"

UI_DATA_REPLACE(/datum/map_report, "original_path", "merge:ui_data_datum_map_report{crashed:bool,loadable:bool,bad_paths:list,bad_keys:list}")

/// The computed part of /datum/map_report's window data (declared on its UI_DATA row).
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
