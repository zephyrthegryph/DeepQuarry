
/*
	Tgui panel for admins editing the access list of various machines.
*/
/datum/access_viewer
	/// The object being edited (a relation view)
	var/obj/machinery/focused_obj

CAPABILITIES(/datum/access_viewer)
	interface("AccessViewer", title = "Access Viewer", rights = R_DEBUG)
	op("req_all", ui_act("req_all", arg("set_id", num())), then(PROC_REF(ui_act_req_all)))
	op("req_one", ui_act("req_one", arg("set_id", num())), then(PROC_REF(ui_act_req_one)))

/datum/access_viewer/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/machinery/req_thing = focused_obj
	if(!check_rights_for(user.client, R_DEBUG))
		return FALSE
	if(!req_thing)
		return FALSE
	return TRUE

/datum/access_viewer/proc/ui_act_req_all(datum/act/op/A, set_id_arg)
	if(!ui_gate(A))
		return FALSE
	var/obj/machinery/req_thing = focused_obj
	var/set_id = set_id_arg
	if(!set_id)
		return FALSE
	// Copy first: access lists are shared between objects (intern_access_lists()).
	req_thing.req_access = req_thing.req_access ? req_thing.req_access.Copy() : list()
	if(set_id in req_thing.req_access)
		req_thing.req_access -= set_id
	else
		req_thing.req_access += set_id
	return TRUE

/datum/access_viewer/proc/ui_act_req_one(datum/act/op/A, set_id_arg)
	if(!ui_gate(A))
		return FALSE
	var/obj/machinery/req_thing = focused_obj
	var/set_id = set_id_arg
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

/// /datum/access_viewer's window data.
/datum/access_viewer/ui_data(datum/act/eval/A)
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
