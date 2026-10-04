CAPABILITIES(/datum/error_viewer)
	op("refresh", ui_act(), then(PROC_REF(ui_act_refresh)))
	op("back", ui_act(), then(PROC_REF(ui_act_back)))

// Error viewer — structured TGUI replacement for the legacy browse_to HTML chain.

/datum/error_viewer
	/// "organized" | "linear" — only meaningful when viewing the error_cache.
	var/dq_linear = FALSE
	/// Backwards-navigation target for the panel.
	var/tmp/datum/error_viewer/dq_back_to

/datum/error_viewer/browse_to(client/user, html)
	// body is now a TGUI panel; the legacy html arg is ignored.
	if(!user)
		return
	tgui_interact(user.mob)

DECLARE_UI_STATE(/datum/error_viewer, ADMIN_STATE(R_ADMIN|R_DEBUG))

DECLARE_UI(/datum/error_viewer, "ErrorViewer", UI_TITLE("Error Viewer"))

/datum/error_viewer/ui_opening(mob/user, datum/tgui/ui)
	ensure_back_pointer()

/datum/error_viewer/proc/ensure_back_pointer()
	return

/datum/error_viewer/error_source/ensure_back_pointer()
	if(!dq_back_to())
		rel_set(src, nameof(dq_back_to), GLOB.error_cache)

/datum/error_viewer/error_entry/ensure_back_pointer()
	if(!dq_back_to())
		rel_set(src, nameof(dq_back_to), error_source())

/datum/error_viewer/proc/dq_pack_link_ref(datum/error_viewer/EV)
	if(!EV)
		return null
	return "[REF(EV)]"

UI_DATA_REPLACE(/datum/error_viewer, "title=name:text", "merge:ui_data_datum_error_viewer{view_kind:text,back_ref:unknown,linear:bool,total_runtimes:unknown,total_skipped:unknown}")

/// The computed part of /datum/error_viewer's window data (declared on its UI_DATA row).
/datum/error_viewer/proc/ui_data_datum_error_viewer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["view_kind"] = "unknown"
	data["back_ref"] = dq_pack_link_ref(dq_back_to())
	data["linear"] = !!dq_linear
	data["total_runtimes"] = GLOB.total_runtimes
	data["total_skipped"] = GLOB.total_runtimes_skipped
	return data

UI_DATA(/datum/error_viewer/error_cache, "merge:ui_data_datum_error_viewer_error_cache{view_kind:text,items:list}")

/// The computed part of /datum/error_viewer/error_cache's window data (declared on its UI_DATA row).
/datum/error_viewer/error_cache/proc/ui_data_datum_error_viewer_error_cache(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["view_kind"] = "cache"
	var/list/items = list()
	if(!dq_linear)
		var/datum/error_viewer/error_source/error_source
		for(var/erroruid in error_sources)
			error_source = LAZYACCESS(error_sources, erroruid)
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

UI_DATA(/datum/error_viewer/error_source, "merge:ui_data_datum_error_viewer_error_source{view_kind:text,items:list}")

/// The computed part of /datum/error_viewer/error_source's window data (declared on its UI_DATA row).
/datum/error_viewer/error_source/proc/ui_data_datum_error_viewer_error_source(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
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

UI_DATA(/datum/error_viewer/error_entry, "desc:text", "merge:ui_data_datum_error_viewer_error_entry{view_kind:text,usr_ref:bool,usr_loc_ref:text,usr_loc_x:num,usr_loc_y:num,usr_loc_z:num}")

/// The computed part of /datum/error_viewer/error_entry's window data (declared on its UI_DATA row).
/datum/error_viewer/error_entry/proc/ui_data_datum_error_viewer_error_entry(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["view_kind"] = "entry"
	data["usr_ref"] = usr_ref || null
	data["usr_loc_ref"] = usr_loc() ? "[REF(usr_loc())]" : null
	if(usr_loc())
		data["usr_loc_x"] = usr_loc().x
		data["usr_loc_y"] = usr_loc().y
		data["usr_loc_z"] = usr_loc().z
	return data

/datum/error_viewer/proc/ui_act_refresh(datum/act/op/A)
	SStgui.update_uis(src)
	return OP_OK

UI_ACT(/datum/error_viewer, "set_mode", ui_act_set_mode, UI_ARG_TEXT("mode"))
UI_ACT_PROC(/datum/error_viewer, ui_act_set_mode)
	dq_linear = "[params["mode"]]" == "linear"
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/error_viewer, "navigate", ui_act_navigate, UI_ARG_TEXT("ref"))
UI_ACT_PROC(/datum/error_viewer, ui_act_navigate)
	var/ref = "[params["ref"]]"
	var/datum/error_viewer/EV = locate(ref)
	if(istype(EV))
		rel_set(EV, nameof(/datum/error_viewer::dq_back_to), src)
		EV.dq_linear = dq_linear
		EV.tgui_interact(ui.user)
	return TRUE

/datum/error_viewer/proc/ui_act_back(datum/act/op/A)
	if(dq_back_to())
		dq_back_to().tgui_interact(A.actor)
	return OP_OK

UI_ACT(/datum/error_viewer, "vv_usr", ui_act_vv_usr)
UI_ACT_PROC(/datum/error_viewer, ui_act_vv_usr)
	if(istype(src, /datum/error_viewer/error_entry))
		var/datum/error_viewer/error_entry/E = src
		if(E.usr_ref)
			ui.user.client?.vv_topic(list("Vars" = E.usr_ref), TRUE)
	return TRUE

UI_ACT(/datum/error_viewer, "pp_usr", ui_act_pp_usr)
UI_ACT_PROC(/datum/error_viewer, ui_act_pp_usr)
	if(istype(src, /datum/error_viewer/error_entry))
		var/datum/error_viewer/error_entry/E = src
		if(E.usr_ref)
			ui.user.client?.admin_datum()?.topic_internal(ui.user, list("_src_" = "holder", "adminplayeropts" = E.usr_ref))
	return TRUE

UI_ACT(/datum/error_viewer, "follow_usr", ui_act_follow_usr)
UI_ACT_PROC(/datum/error_viewer, ui_act_follow_usr)
	if(istype(src, /datum/error_viewer/error_entry))
		var/datum/error_viewer/error_entry/E = src
		if(E.usr_ref)
			ui.user.client?.admin_datum()?.topic_internal(ui.user, list("_src_" = "holder", "adminplayerobservefollow" = E.usr_ref))
	return TRUE

UI_ACT(/datum/error_viewer, "vv_usr_loc", ui_act_vv_usr_loc)
UI_ACT_PROC(/datum/error_viewer, ui_act_vv_usr_loc)
	if(istype(src, /datum/error_viewer/error_entry))
		var/datum/error_viewer/error_entry/E = src
		if(E.usr_loc())
			var/ref = "[REF(E.usr_loc())]"
			ui.user.client?.vv_topic(list("Vars" = ref), TRUE)
	return TRUE

UI_ACT(/datum/error_viewer, "jmp_usr_loc", ui_act_jmp_usr_loc)
UI_ACT_PROC(/datum/error_viewer, ui_act_jmp_usr_loc)
	if(istype(src, /datum/error_viewer/error_entry))
		var/datum/error_viewer/error_entry/E = src
		if(E.usr_loc())
			ui.user.client?.admin_datum()?.topic_internal(ui.user, list("_src_" = "holder", "adminplayerobservecoodjump" = "1", "X" = "[E.usr_loc().x]", "Y" = "[E.usr_loc().y]", "Z" = "[E.usr_loc().z]"))
	return TRUE

/// The dq_back_to this refers to (a relation view: null once that is deleted).
/datum/error_viewer/proc/dq_back_to() as /datum/error_viewer
	return dq_back_to
