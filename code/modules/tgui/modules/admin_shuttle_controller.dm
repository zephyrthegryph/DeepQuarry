/* This is an admin tool to control all shuttles, including overmap & classic. */

/datum/tgui_module/admin_shuttle_controller
	name = "Admin Shuttle Controller"
	tgui_id = "AdminShuttleController"

/datum/tgui_module/admin_shuttle_controller/tgui_close(mob/user)
	. = ..()
	qdel(src)

/datum/tgui_module/admin_shuttle_controller/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/list/shuttles = list()
	for(var/shuttle_name in SSshuttles.shuttles)
		var/datum/shuttle/S = SSshuttles.shuttles[shuttle_name]
		shuttles.Add(list(list(
			"name" = shuttle_name,
			"ref" = REF(S),
			"current_location" = S.get_location_name(),
			"status" = S.moving_status,
		)))
	data["shuttles"] = shuttles

	var/list/overmap_ships = list()
	for(var/obj/effect/overmap/visitable/ship/S as anything in SSshuttles.ships)
		overmap_ships.Add(list(list(
			"name" = S.name,
			"ref" = REF(S),
		)))
	data["overmap_ships"] = overmap_ships

	return data

/datum/tgui_module/admin_shuttle_controller/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT|R_DEBUG)

/datum/tgui_module/admin_shuttle_controller/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return

	switch(action)
		if("adminobserve")
			var/datum/shuttle/S = locate(params["ref"])
			if(istype(S))
				var/client/C = ui.user.client
				if(!isobserver(ui.user))
					SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/admin_ghost)
					SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/jumptoturf, get_turf(S.current_location()))
			else if(istype(S, /obj/effect/overmap/visitable))
				var/obj/effect/overmap/visitable/V = S
				var/client/C = ui.user.client
				if(!isobserver(ui.user))
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
		if("classicmove")
			var/datum/shuttle/S = locate(params["ref"])
			if(istype(S, /datum/shuttle/autodock/multi))
				var/datum/shuttle/autodock/multi/shuttle = S
				var/dest_key = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/choice, message = "Choose shuttle destination", title = "Shuttle Destination", choices = shuttle.get_destinations())
				if(isnull(dest_key))
					return
				if(dest_key)
					shuttle.set_destination(dest_key, ui.user)
					shuttle.launch(src)
			else if(istype(S, /datum/shuttle/autodock/overmap))
				var/datum/shuttle/autodock/overmap/shuttle = S
				var/list/possible_d = shuttle.get_possible_destinations()
				var/D
				if(!LAZYLEN(possible_d))
					to_chat(ui.user, span_warning("There are no possible destinations for [shuttle] ([shuttle.type])"))
					return FALSE
				var/_answer_a2 = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/choice, message = "Choose shuttle destination", title = "Shuttle Destination", choices = possible_d)
				if(isnull(_answer_a2))
					return
				D = _answer_a2
				if(D)
					shuttle.set_destination(possible_d[D])
					shuttle.launch()
			else if(istype(S, /datum/shuttle/autodock))
				var/datum/shuttle/autodock/shuttle = S
				var/_answer_a3 = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/choice/alert, message = "Are you sure you want to launch [shuttle]?", title = "Launching Shuttle", choices = list("Yes", "No"))
				if(isnull(_answer_a3))
					return
				if(_answer_a3 == "Yes")
					shuttle.launch(src)
			else
				to_chat(ui.user, span_notice("The shuttle control panel isn't quite sure how to move [S] ([S?.type])."))
				return FALSE
			to_chat(ui.user, span_notice("Launching shuttle [S]."))
			return TRUE
		if("overmap_control")
			var/obj/effect/overmap/visitable/ship/V = locate(params["ref"])
			if(istype(V))
				var/datum/flight_vessel/vessel = GLOB.flight_service.vessel_for_ship(V) || GLOB.flight_service.register_vessel(V)
				var/datum/flight_operations_ui/flight_ui = new(src, vessel)
				flight_ui.tgui_interact(ui.user)

			return TRUE
