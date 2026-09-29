
/*
	Tgui panel for admins editing the access list of various machines.
*/
/datum/access_viewer
	/// The object being edited (a relation view)
	var/obj/machinery/focused_obj

DECLARE_UI(/datum/access_viewer, "AccessViewer", UI_TITLE("Access Viewer"))

DECLARE_UI_STATE(/datum/access_viewer, ADMIN_STATE(R_DEBUG))

/datum/access_viewer/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/obj/machinery/req_thing = focused_obj
	if(!check_rights_for(ui.user.client, R_DEBUG))
		return FALSE
	if(!req_thing)
		return FALSE
	return TRUE

UI_ACT(/datum/access_viewer, "req_all", ui_act_req_all, UI_ARG_NUM("set_id"))
UI_ACT_PROC(/datum/access_viewer, ui_act_req_all)
	var/obj/machinery/req_thing = focused_obj
	var/set_id = params["set_id"]
	if(!set_id)
		return FALSE
	// Copy first: access lists are shared between objects (intern_access_lists()).
	req_thing.req_access = req_thing.req_access ? req_thing.req_access.Copy() : list()
	if(set_id in req_thing.req_access)
		req_thing.req_access -= set_id
	else
		req_thing.req_access += set_id
	return TRUE

UI_ACT(/datum/access_viewer, "req_one", ui_act_req_one, UI_ARG_NUM("set_id"))
UI_ACT_PROC(/datum/access_viewer, ui_act_req_one)
	var/obj/machinery/req_thing = focused_obj
	var/set_id = params["set_id"]
	if(!set_id)
		return FALSE
	req_thing.req_one_access = req_thing.req_one_access ? req_thing.req_one_access.Copy() : list()
	if(set_id in req_thing.req_one_access)
		req_thing.req_one_access -= set_id
	else
		req_thing.req_one_access += set_id
	return TRUE

/datum/access_viewer/tgui_static_data(mob/user)
	var/list/data = list()
	var/list/access_list = list()
	for(var/datum/access/dat as anything in subtypesof(/datum/access))
		access_list += list(
			list(
				"id" = dat.id,
				"name" = dat.desc,
				"region" = dat.region,
				"access_type" = dat.access_type,
			)
		)
	data["access_list"] = access_list
	return data

UI_DATA_REPLACE(/datum/access_viewer, "merge:ui_data_datum_access_viewer{name:text,coords:text,req_access:unknown,req_one_access:list}")

/// The computed part of /datum/access_viewer's window data (declared on its UI_DATA row).
/datum/access_viewer/proc/ui_data_datum_access_viewer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	// Check if the object still exists
	var/obj/machinery/req_thing = focused_obj
	if(req_thing)
		data["name"] = req_thing.name
		data["coords"] = "[req_thing.x].[req_thing.y].[req_thing.z]"
		data["req_access"] = req_thing.req_access ? req_thing.req_access : list()
		data["req_one_access"] = req_thing.req_one_access ? req_thing.req_one_access : list()
	return data

/datum/access_viewer/proc/set_access_focus(obj/machinery/req_thing)
	rel_set(src, nameof(focused_obj), req_thing)
