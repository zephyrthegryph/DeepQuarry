// Map verify report — structured TGUI panel for admin map-load diagnostics.

/datum/map_report/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_DEBUG)

/datum/map_report/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MapReport", "Report for map file [original_path]")
		ui.open()

/datum/map_report/tgui_data(mob/user)
	var/list/data = list()
	data["original_path"] = original_path
	data["crashed"] = !!crashed
	data["loadable"] = !!loadable
	var/list/path_rows = list()
	for(var/path in bad_paths)
		var/list/keys = bad_paths[path]
		path_rows += list(list("path" = "[path]", "keys" = keys.Copy()))
	data["bad_paths"] = path_rows
	var/list/key_rows = list()
	for(var/key in bad_keys)
		var/list/messages = bad_keys[key]
		key_rows += list(list("key" = "[key]", "messages" = messages.Copy()))
	data["bad_keys"] = key_rows
	return data

/datum/map_report/show_to(client/C)
	tgui_interact(C.mob)
