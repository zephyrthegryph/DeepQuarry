/* This is an admin tool to control all shuttles, including overmap & classic. */

/datum/tgui_module/admin_shuttle_controller
	name = "Admin Shuttle Controller"

/datum/tgui_module/admin_shuttle_controller/tgui_close(mob/user)
	. = ..()
	spent(src, user)

CAPABILITIES(/datum/tgui_module/admin_shuttle_controller)
	interface("AdminShuttleController", rights = R_ADMIN|R_EVENT|R_DEBUG)
	op("adminobserve", ui_act("adminobserve", arg("ref", schema_ref(/datum/shuttle))), then(PROC_REF(ui_act_adminobserve)))
	op("classicmove", ui_act("classicmove", arg("ref", schema_ref(/datum/shuttle))), needs(req_rights(R_ADMIN|R_EVENT|R_DEBUG)),
		asks(/datum/prompt/choice, fields = list("title" = "Shuttle Destination", "question" = "Choose shuttle destination", "choices" = computed(PROC_REF(multi_destinations)), "timeout" = 0, "rights" = R_ADMIN|R_EVENT|R_DEBUG), step = "multi", when = PROC_REF(asks_multi)),
		asks(/datum/prompt/choice, fields = list("title" = "Shuttle Destination", "question" = "Choose shuttle destination", "choices" = computed(PROC_REF(overmap_destinations)), "timeout" = 0, "rights" = R_ADMIN|R_EVENT|R_DEBUG), step = "overmap", when = PROC_REF(asks_overmap)),
		asks(/datum/prompt/yes_no, fields = list("title" = "Launching Shuttle", "question" = computed(PROC_REF(launch_question)), "timeout" = 0, "rights" = R_ADMIN|R_EVENT|R_DEBUG), step = "launch", when = PROC_REF(asks_launch)),
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

/// The shuttle a classic-move button names.
/datum/tgui_module/admin_shuttle_controller/proc/classic_shuttle(datum/act/op/A)
	return A.args["ref"]

/datum/tgui_module/admin_shuttle_controller/proc/asks_multi(datum/act/op/A)
	return istype(classic_shuttle(A), /datum/shuttle/autodock/multi)

/// A multi-destination shuttle has no overmap step; an overmap shuttle with nowhere to go is refused in the effect.
/datum/tgui_module/admin_shuttle_controller/proc/asks_overmap(datum/act/op/A)
	var/datum/shuttle/S = classic_shuttle(A)
	if(!istype(S, /datum/shuttle/autodock/overmap) || istype(S, /datum/shuttle/autodock/multi))
		return FALSE
	var/datum/shuttle/autodock/overmap/shuttle = S
	return LAZYLEN(shuttle.get_possible_destinations()) > 0

/datum/tgui_module/admin_shuttle_controller/proc/asks_launch(datum/act/op/A)
	var/datum/shuttle/S = classic_shuttle(A)
	return istype(S, /datum/shuttle/autodock) && !istype(S, /datum/shuttle/autodock/multi) && !istype(S, /datum/shuttle/autodock/overmap)

/datum/tgui_module/admin_shuttle_controller/proc/multi_destinations(datum/act/op/A)
	var/datum/shuttle/autodock/multi/shuttle = classic_shuttle(A)
	return shuttle.get_destinations()

/datum/tgui_module/admin_shuttle_controller/proc/overmap_destinations(datum/act/op/A)
	var/datum/shuttle/autodock/overmap/shuttle = classic_shuttle(A)
	return shuttle.get_possible_destinations()

/datum/tgui_module/admin_shuttle_controller/proc/launch_question(datum/act/op/A)
	return "Are you sure you want to launch [classic_shuttle(A)]?"

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_classicmove(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/datum/shuttle/S = ref
	if(istype(S, /datum/shuttle/autodock/multi))
		var/datum/shuttle/autodock/multi/shuttle = S
		if(!A.answer)
			return OP_OK
		var/dest_key = A.step_value("multi")
		if(dest_key)
			shuttle.set_destination(dest_key, user)
			shuttle.launch(src, user)
		to_chat(user, span_notice("Launching shuttle [shuttle]."))
	else if(istype(S, /datum/shuttle/autodock/overmap))
		var/datum/shuttle/autodock/overmap/shuttle = S
		var/list/possible_d = shuttle.get_possible_destinations()
		if(!LAZYLEN(possible_d))
			to_chat(user, span_warning("There are no possible destinations for [shuttle] ([shuttle.type])"))
			return OP_OK
		if(!A.answer)
			return OP_OK
		var/D = A.step_value("overmap")
		if(D)
			shuttle.set_destination(possible_d[D])
			shuttle.launch()
		to_chat(user, span_notice("Launching shuttle [shuttle]."))
	else if(istype(S, /datum/shuttle/autodock))
		var/datum/shuttle/autodock/shuttle = S
		if(!A.answer)
			return OP_OK
		if(A.step_value("launch"))
			shuttle.launch(src)
		to_chat(user, span_notice("Launching shuttle [shuttle]."))
	else
		to_chat(user, span_notice("The shuttle control panel isn't quite sure how to move [S] ([S?.type])."))
		return OP_OK
	SStgui.update_uis(src)
	return OP_OK

/datum/tgui_module/admin_shuttle_controller/proc/ui_act_overmap_control(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/obj/effect/overmap/visitable/ship/V = ref
	if(istype(V))
		var/datum/flight_vessel/vessel = SSflight.vessel_for_ship(V) || SSflight.register_vessel(V)
		var/datum/flight_operations_ui/flight_ui = new(src, vessel)
		flight_ui.tgui_interact(user)

	return TRUE
