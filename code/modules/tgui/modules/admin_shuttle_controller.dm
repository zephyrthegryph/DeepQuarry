/* This is an admin tool to control all shuttles, including overmap & classic. */

/datum/tgui_module/admin_shuttle_controller
	name = "Admin Shuttle Controller"

/datum/tgui_module/admin_shuttle_controller/tgui_close(mob/user)
	. = ..()
	spent(src, user)

CAPABILITIES(/datum/tgui_module/admin_shuttle_controller)
	interface("AdminShuttleController", rights = R_ADMIN|R_EVENT|R_DEBUG)
	op("adminobserve", ui_act("adminobserve", arg("ref", schema_ref(/datum/shuttle))), then(PROC_REF(ui_act_adminobserve)))
	op("classicmove", ui_act("classicmove", arg("ref", schema_ref(/datum/shuttle))),
		needs(req_rights(R_ADMIN | R_EVENT | R_DEBUG)),
		asks(/datum/prompt/choice, fields = list("question" = "Choose shuttle destination", "title" = "Shuttle Destination", "choices" = computed(PROC_REF(multi_destination_choices)), "rights" = R_ADMIN | R_EVENT | R_DEBUG, "timeout" = 0), step = "multi_destination", when = PROC_REF(move_is_multi)),
		asks(/datum/prompt/choice, fields = list("question" = "Choose shuttle destination", "title" = "Shuttle Destination", "choices" = computed(PROC_REF(overmap_destination_choices)), "rights" = R_ADMIN | R_EVENT | R_DEBUG, "timeout" = 0), step = "overmap_destination", when = PROC_REF(move_is_overmap)),
		asks(/datum/prompt/yes_no, fields = list("question" = computed(PROC_REF(launch_question)), "title" = "Launching Shuttle", "rights" = R_ADMIN | R_EVENT | R_DEBUG, "timeout" = 0), step = "launch", when = PROC_REF(move_is_launch)),
		then(PROC_REF(ui_act_classicmove)))
	op("overmap_control", ui_act("overmap_control", arg("ref", schema_ref(/obj/effect/overmap/visitable/ship))), then(PROC_REF(ui_act_overmap_control)))

/datum/tgui_module/admin_shuttle_controller/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/list/shuttles = list()
	for(var/shuttle_name in shuttles_shuttles())
		var/datum/shuttle/S = shuttles_shuttles()[shuttle_name]
		shuttles.Add(list(list(
			"name" = shuttle_name,
			"ref" = ref_token(S),
			"current_location" = S.get_location_name(),
			"status" = S.moving_status,
		)))
	data["shuttles"] = shuttles

	var/list/overmap_ships = list()
	for(var/obj/effect/overmap/visitable/ship/S as anything in shuttles_ships())
		overmap_ships.Add(list(list(
			"name" = S.name,
			"ref" = ref_token(S),
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

/// How a classic move goes for the shuttle named: "multi" (a destination of its own list), "overmap" (a destination of the ones possible), "launch" (a confirmed launch) or null (not movable from here).
/datum/tgui_module/admin_shuttle_controller/proc/move_kind(datum/shuttle/S)
	if(QDELETED(S))
		return null
	if(istype(S, /datum/shuttle/autodock/multi))
		return "multi"
	if(istype(S, /datum/shuttle/autodock/overmap))
		return "overmap"
	if(istype(S, /datum/shuttle/autodock))
		return "launch"
	return null

/datum/tgui_module/admin_shuttle_controller/proc/move_is_multi(datum/act/op/A)
	return move_kind(A.args["ref"]) == "multi"

/// An overmap shuttle with no possible destination is not asked: the move says so and ends.
/datum/tgui_module/admin_shuttle_controller/proc/move_is_overmap(datum/act/op/A)
	if(move_kind(A.args["ref"]) != "overmap")
		return FALSE
	var/datum/shuttle/autodock/overmap/shuttle = A.args["ref"]
	return LAZYLEN(shuttle.get_possible_destinations()) > 0

/datum/tgui_module/admin_shuttle_controller/proc/move_is_launch(datum/act/op/A)
	return move_kind(A.args["ref"]) == "launch"

/datum/tgui_module/admin_shuttle_controller/proc/multi_destination_choices(datum/act/op/A)
	var/datum/shuttle/autodock/multi/shuttle = A.args["ref"]
	return shuttle.get_destinations()

/datum/tgui_module/admin_shuttle_controller/proc/overmap_destination_choices(datum/act/op/A)
	var/datum/shuttle/autodock/overmap/shuttle = A.args["ref"]
	return shuttle.get_possible_destinations()

/datum/tgui_module/admin_shuttle_controller/proc/launch_question(datum/act/op/A)
	return "Are you sure you want to launch [A.args["ref"]]?"

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_classicmove(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/datum/shuttle/S = ref
	switch(move_kind(S))
		if("multi")
			var/datum/shuttle/autodock/multi/shuttle = S
			var/dest_key = A.step_value("multi_destination")
			if(dest_key)
				shuttle.set_destination(dest_key, user)
				shuttle.launch(src, user)
			to_chat(user, span_notice("Launching shuttle [shuttle]."))
		if("overmap")
			var/datum/shuttle/autodock/overmap/shuttle = S
			var/list/possible_d = shuttle.get_possible_destinations()
			if(!A.step_answer("overmap_destination"))
				to_chat(user, span_warning("There are no possible destinations for [shuttle] ([shuttle.type])"))
				return FALSE
			var/D = A.step_value("overmap_destination")
			if(D)
				shuttle.set_destination(possible_d[D])
				shuttle.launch()
			to_chat(user, span_notice("Launching shuttle [shuttle]."))
		if("launch")
			var/datum/shuttle/autodock/shuttle = S
			if(A.step_value("launch"))
				shuttle.launch(src)
			to_chat(user, span_notice("Launching shuttle [shuttle]."))
		else
			to_chat(user, span_notice("The shuttle control panel isn't quite sure how to move [S] ([S?.type])."))
			return FALSE
	SStgui.update_uis(src)
	return TRUE

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_overmap_control(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/obj/effect/overmap/visitable/ship/V = ref
	if(istype(V))
		var/datum/flight_vessel/vessel = SSflight.vessel_for_ship(V) || SSflight.register_vessel(V)
		var/datum/flight_operations_ui/flight_ui = new(src, vessel)
		flight_ui.tgui_interact(user)

	return TRUE
