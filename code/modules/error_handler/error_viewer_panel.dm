// Error viewer — structured TGUI replacement for the legacy browse_to HTML chain.

/datum/error_viewer
	/// "organized" | "linear" — only meaningful when viewing the error_cache.
	var/dq_linear = FALSE
	/// Backwards-navigation target for the panel.
	var/datum/error_viewer/dq_back_to = null

/datum/error_viewer/browse_to(client/user, html)
	// body is now a TGUI panel; the legacy html arg is ignored.
	if(!user)
		return
	tgui_interact(user.mob)

/datum/error_viewer/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_DEBUG)

/datum/error_viewer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ensure_back_pointer()
		ui = new(user, src, "ErrorViewer", "Error Viewer")
		ui.open()

/datum/error_viewer/proc/ensure_back_pointer()
	return

/datum/error_viewer/error_source/ensure_back_pointer()
	if(!dq_back_to)
		dq_back_to = GLOB.error_cache

/datum/error_viewer/error_entry/ensure_back_pointer()
	if(!dq_back_to)
		dq_back_to = error_source

/datum/error_viewer/proc/dq_pack_link_ref(datum/error_viewer/EV)
	if(!EV)
		return null
	return "[REF(EV)]"

/datum/error_viewer/tgui_data(mob/user)
	var/list/data = list()
	data["view_kind"] = "unknown"
	data["title"] = name
	data["back_ref"] = dq_pack_link_ref(dq_back_to)
	data["linear"] = !!dq_linear
	data["total_runtimes"] = GLOB.total_runtimes
	data["total_skipped"] = GLOB.total_runtimes_skipped
	return data

/datum/error_viewer/error_cache/tgui_data(mob/user)
	var/list/data = ..()
	data["view_kind"] = "cache"
	var/list/items = list()
	if(!dq_linear)
		var/datum/error_viewer/error_source/error_source
		for(var/erroruid in error_sources)
			error_source = error_sources[erroruid]
			items += list(list(
				"ref" = "[REF(error_source)]",
				"name" = error_source.name,
				"is_skip_count" = FALSE,
			))
	else
		for(var/datum/error_viewer/error_entry/error_entry in errors)
			items += list(list(
				"ref" = "[REF(error_entry)]",
				"name" = error_entry.name,
				"is_skip_count" = !!error_entry.is_skip_count,
			))
	data["items"] = items
	return data

/datum/error_viewer/error_source/tgui_data(mob/user)
	var/list/data = ..()
	data["view_kind"] = "source"
	var/list/items = list()
	for(var/datum/error_viewer/error_entry/error_entry in errors)
		items += list(list(
			"ref" = "[REF(error_entry)]",
			"name" = error_entry.name,
			"is_skip_count" = !!error_entry.is_skip_count,
		))
	data["items"] = items
	return data

/datum/error_viewer/error_entry/tgui_data(mob/user)
	var/list/data = ..()
	data["view_kind"] = "entry"
	data["desc"] = desc
	data["usr_ref"] = usr_ref || null
	data["usr_loc_ref"] = usr_loc ? "[REF(usr_loc)]" : null
	if(usr_loc)
		data["usr_loc_x"] = usr_loc.x
		data["usr_loc_y"] = usr_loc.y
		data["usr_loc_z"] = usr_loc.z
	return data

/datum/error_viewer/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("refresh")
			SStgui.update_uis(src)
			return TRUE
		if("set_mode")
			dq_linear = "[params["mode"]]" == "linear"
			SStgui.update_uis(src)
			return TRUE
		if("navigate")
			var/ref = "[params["ref"]]"
			var/datum/error_viewer/EV = locate(ref)
			if(istype(EV))
				EV.dq_back_to = src
				EV.dq_linear = dq_linear
				EV.tgui_interact(ui.user)
			return TRUE
		if("back")
			if(dq_back_to)
				dq_back_to.tgui_interact(ui.user)
			return TRUE
		if("vv_usr")
			if(istype(src, /datum/error_viewer/error_entry))
				var/datum/error_viewer/error_entry/E = src
				if(E.usr_ref)
					ui.user.client?.view_var_Topic("Vars=[E.usr_ref]", list("_src_" = "vars", "Vars" = E.usr_ref))
			return TRUE
		if("pp_usr")
			if(istype(src, /datum/error_viewer/error_entry))
				var/datum/error_viewer/error_entry/E = src
				if(E.usr_ref)
					ui.user.client?.holder?.Topic("adminplayeropts=[E.usr_ref]", list("_src_" = "holder", "adminplayeropts" = E.usr_ref))
			return TRUE
		if("follow_usr")
			if(istype(src, /datum/error_viewer/error_entry))
				var/datum/error_viewer/error_entry/E = src
				if(E.usr_ref)
					ui.user.client?.holder?.Topic("adminplayerobservefollow=[E.usr_ref]", list("_src_" = "holder", "adminplayerobservefollow" = E.usr_ref))
			return TRUE
		if("vv_usr_loc")
			if(istype(src, /datum/error_viewer/error_entry))
				var/datum/error_viewer/error_entry/E = src
				if(E.usr_loc)
					var/ref = "[REF(E.usr_loc)]"
					ui.user.client?.view_var_Topic("Vars=[ref]", list("_src_" = "vars", "Vars" = ref))
			return TRUE
		if("jmp_usr_loc")
			if(istype(src, /datum/error_viewer/error_entry))
				var/datum/error_viewer/error_entry/E = src
				if(E.usr_loc)
					ui.user.client?.holder?.Topic("adminplayerobservecoodjump=1", list("_src_" = "holder", "adminplayerobservecoodjump" = "1", "X" = "[E.usr_loc.x]", "Y" = "[E.usr_loc.y]", "Z" = "[E.usr_loc.z]"))
			return TRUE
