/* This is an admin tool to control all shuttles, including overmap & classic. */

/datum/tgui_module/admin_shuttle_controller
	name = "Admin Shuttle Controller"
	/// The shuttle a destination question was asked about (a view: the shuttles own themselves).
	var/tmp/datum/shuttle/moving

/datum/tgui_module/admin_shuttle_controller/tgui_close(mob/user)
	. = ..()
	spent(src, user)

CAPABILITIES(/datum/tgui_module/admin_shuttle_controller)
	ref_one(nameof(moving), /datum/shuttle)
	interface("AdminShuttleController", rights = R_ADMIN|R_EVENT|R_DEBUG)
	op("adminobserve", ui_act("adminobserve", arg("ref", schema_ref(/datum/shuttle))), then(PROC_REF(ui_act_adminobserve)))
	op("classicmove", ui_act("classicmove", arg("ref", schema_ref(/datum/shuttle))), then(PROC_REF(ui_act_classicmove)))
	op("overmap_control", ui_act("overmap_control", arg("ref", schema_ref(/obj/effect/overmap/visitable/ship))), then(PROC_REF(ui_act_overmap_control)))

/datum/tgui_module/admin_shuttle_controller/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/list/shuttles = list()
	for(var/shuttle_name in shuttles_shuttles())
		var/datum/shuttle/S = shuttles_shuttles()[shuttle_name]
		shuttles.Add(list(list(
			"name" = shuttle_name,
			"ref" = REF(S),
			"current_location" = S.get_location_name(),
			"status" = S.moving_status,
		)))
	data["shuttles"] = shuttles

	var/list/overmap_ships = list()
	for(var/obj/effect/overmap/visitable/ship/S as anything in shuttles_ships())
		overmap_ships.Add(list(list(
			"name" = S.name,
			"ref" = REF(S),
		)))
	data["overmap_ships"] = overmap_ships

	return data

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_adminobserve(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/datum/shuttle/S = ref
	if(istype(S))
		var/client/C = user.client
		if(!isobserver(user))
			SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
			SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/jumptoturf, get_turf(S.current_location()))
	else if(istype(S, /obj/effect/overmap/visitable))
		var/obj/effect/overmap/visitable/V = S
		var/client/C = user.client
		if(!isobserver(user))
			SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
			var/atom/target
			if(LAZYLEN(V.generic_waypoints))
				target =  LAZYACCESS(V.generic_waypoints, 1)
			else if(LAZYLEN(V.restricted_waypoints))
				target =  LAZYACCESS(V.restricted_waypoints, 1)
			else
				to_chat(C, span_warning("Unable to jump to [V]."))
				return
			var/turf/T = get_turf(target)
			if(!istype(T))
				to_chat(C, span_warning("Unable to jump to [V]."))
				return
			SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/jumptoturf, T)
	return TRUE

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_classicmove(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/datum/shuttle/S = ref
	if(istype(S, /datum/shuttle/autodock/multi))
		var/datum/shuttle/autodock/multi/shuttle = S
		rel_set(src, nameof(moving), shuttle)
		open_request(src, /datum/prompt/choice, PROC_REF(multi_destination_chosen), valid = PROC_REF(request_usable), rights = R_ADMIN | R_EVENT | R_DEBUG, answerer = user, question = "Choose shuttle destination", title = "Shuttle Destination", choices = shuttle.get_destinations(), timeout = 0)
	else if(istype(S, /datum/shuttle/autodock/overmap))
		var/datum/shuttle/autodock/overmap/shuttle = S
		var/list/possible_d = shuttle.get_possible_destinations()
		if(!LAZYLEN(possible_d))
			to_chat(user, span_warning("There are no possible destinations for [shuttle] ([shuttle.type])"))
			return FALSE
		rel_set(src, nameof(moving), shuttle)
		open_request(src, /datum/prompt/choice, PROC_REF(overmap_destination_chosen), valid = PROC_REF(request_usable), rights = R_ADMIN | R_EVENT | R_DEBUG, answerer = user, question = "Choose shuttle destination", title = "Shuttle Destination", choices = possible_d, timeout = 0)
	else if(istype(S, /datum/shuttle/autodock))
		rel_set(src, nameof(moving), S)
		open_request(src, /datum/prompt/yes_no, PROC_REF(launch_confirmed), valid = PROC_REF(request_usable), rights = R_ADMIN | R_EVENT | R_DEBUG, answerer = user, question = "Are you sure you want to launch [S]?", title = "Launching Shuttle", timeout = 0)
	else
		to_chat(user, span_notice("The shuttle control panel isn't quite sure how to move [S] ([S?.type])."))
		return FALSE
	return TRUE

/datum/tgui_module/admin_shuttle_controller/proc/multi_destination_chosen(datum/act/request/A)
	multi_destination_chosen_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/admin_shuttle_controller/proc/multi_destination_chosen_apply(datum/act/request/A)
	var/datum/shuttle/autodock/multi/shuttle = moving()
	if(!A.answer || !istype(shuttle))
		return
	var/mob/user = A.request.answerer
	var/dest_key = A.answer.value
	if(dest_key)
		shuttle.set_destination(dest_key, user)
		shuttle.launch(src, user)
	to_chat(user, span_notice("Launching shuttle [shuttle]."))

/datum/tgui_module/admin_shuttle_controller/proc/overmap_destination_chosen(datum/act/request/A)
	overmap_destination_chosen_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/admin_shuttle_controller/proc/overmap_destination_chosen_apply(datum/act/request/A)
	var/datum/shuttle/autodock/overmap/shuttle = moving()
	if(!A.answer || !istype(shuttle))
		return
	var/mob/user = A.request.answerer
	var/list/possible_d = shuttle.get_possible_destinations()
	var/D = A.answer.value
	if(D)
		shuttle.set_destination(possible_d[D])
		shuttle.launch()
	to_chat(user, span_notice("Launching shuttle [shuttle]."))

/datum/tgui_module/admin_shuttle_controller/proc/launch_confirmed(datum/act/request/A)
	launch_confirmed_apply(A)
	SStgui.update_uis(src)

/datum/tgui_module/admin_shuttle_controller/proc/launch_confirmed_apply(datum/act/request/A)
	var/datum/shuttle/autodock/shuttle = moving()
	if(!A.answer || !istype(shuttle))
		return
	var/mob/user = A.request.answerer
	if(A.answer.value)
		shuttle.launch(src)
	to_chat(user, span_notice("Launching shuttle [shuttle]."))

/// The shuttle the pending destination question is about.
/datum/tgui_module/admin_shuttle_controller/proc/moving() as /datum/shuttle
	return moving

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_overmap_control(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/obj/effect/overmap/visitable/ship/V = ref
	if(istype(V))
		var/datum/flight_vessel/vessel = SSflight.vessel_for_ship(V) || SSflight.register_vessel(V)
		var/datum/flight_operations_ui/flight_ui = new(src, vessel)
		flight_ui.tgui_interact(user)

	return TRUE
