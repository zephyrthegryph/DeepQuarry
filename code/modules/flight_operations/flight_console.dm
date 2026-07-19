/datum/flight_operations_ui
	var/datum/host
	var/datum/flight_vessel/forced_vessel

/datum/flight_operations_ui/New(new_host, datum/flight_vessel/new_forced_vessel = null)
	..()
	host = new_host
	forced_vessel = new_forced_vessel

/datum/flight_operations_ui/Destroy()
	host = null
	forced_vessel = null
	return ..()

/datum/flight_operations_ui/tgui_host()
	return host

/datum/flight_operations_ui/tgui_state(mob/user)
	if(forced_vessel)
		return ADMIN_STATE(R_ADMIN | R_EVENT | R_DEBUG)
	return GLOB.tgui_default_state

/datum/flight_operations_ui/tgui_interact(mob/user, datum/tgui/ui)
	if(!resolve_vessel())
		to_chat(user, span_warning("Flight Operations cannot identify this console's vessel."))
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FlightOperations", "Flight Operations")
		ui.open()

/datum/flight_operations_ui/proc/resolve_ship()
	if(istype(host, /obj/machinery/computer/ship))
		var/obj/machinery/computer/ship/console = host
		if(!console.linked)
			console.sync_linked()
		return console.linked
	if(istype(host, /obj/machinery/computer/shuttle_control/explore))
		var/obj/machinery/computer/shuttle_control/explore/console = host
		var/datum/shuttle/autodock/overmap/shuttle = SSshuttles.shuttles[console.shuttle_tag]
		return shuttle?.myship
	return null

/datum/flight_operations_ui/proc/resolve_vessel()
	if(forced_vessel)
		return forced_vessel
	var/obj/effect/overmap/visitable/ship/ship = resolve_ship()
	return SSflight_operations?.vessel_for_ship(ship) || SSflight_operations?.register_vessel(ship)

/datum/flight_operations_ui/proc/serialize_destinations(datum/flight_vessel/viewing_vessel)
	var/list/destination_data = list()
	var/obj/effect/overmap/visitable/ship/viewing_ship = viewing_vessel?.ship
	for(var/id in SSflight_operations.destinations)
		var/datum/flight_destination/destination = SSflight_operations.destinations[id]
		if(!destination?.discovered || (destination.kind != FLIGHT_DEST_SYSTEM && !destination.is_available()))
			continue
		var/list/render_data = list(
			"id" = destination.id,
			"name" = destination.name,
			"description" = destination.description,
			"kind" = destination.kind,
			"scene_role" = "orbital",
			"orbit_parent_id" = destination.orbit_parent_id,
			"docked_port_id" = null,
			"docked_host_id" = null,
			"orbit_radius" = destination.orbit_radius,
			"orbit_period" = destination.orbit_period,
			"orbit_phase" = destination.orbit_phase,
			"orbit_inclination" = destination.orbit_inclination,
			"body_radius" = destination.body_radius,
			"body_color" = destination.body_color,
			"latitude" = destination.surface_latitude,
			"longitude" = destination.surface_longitude,
			"compatible" = viewing_vessel.has_capabilities(destination.required_capabilities),
			"materialized" = !destination.expedition || destination.expedition.z_level > 0,
			"is_current" = destination.target == viewing_ship,
		)
		if(destination.kind == FLIGHT_DEST_VESSEL)
			var/datum/flight_vessel/render_vessel = SSflight_operations.vessel_for_ship(destination.target)
			var/is_carrier = istype(render_vessel?.ship, /obj/effect/overmap/visitable/ship/exploration_carrier)
			var/datum/flight_port/render_port = is_carrier ? null : SSflight_operations.ports[render_vessel?.docked_port_id]
			render_data["scene_role"] = render_port ? "docked" : "orbital"
			render_data["docked_port_id"] = render_port?.id
			render_data["docked_host_id"] = render_port?.host_destination_id
		destination_data += list(render_data)
	return destination_data

/datum/flight_operations_ui/tgui_data(mob/user)
	var/datum/flight_vessel/vessel = resolve_vessel()
	var/obj/effect/overmap/visitable/ship/ship = vessel?.ship
	var/list/data = list(
		"vessel" = vessel?.name || "Unlinked vessel",
		"vessel_id" = vessel?.id,
		"vessel_destination_id" = SSflight_operations?.destination_for_target(ship)?.id,
		"orbit_parent_id" = vessel?.orbit_parent_id,
		"docked_port_id" = vessel?.docked_port_id,
		"capabilities" = vessel?.capabilities || 0,
		"engines_online" = ship?.engines_state || FALSE,
		"thrust_limit" = round((ship?.thrust_limit || 0) * 100),
		"total_thrust" = ship?.get_total_thrust() || 0,
		"can_burn" = !!ship?.can_burn(),
		"destinations" = list(),
		"contacts" = list(),
		"plan" = null,
		"expedition" = null,
		"server_time" = world.time,
	)
	if(!vessel)
		return data
	data["destinations"] = serialize_destinations(vessel)
	if(ship)
		var/list/contacts = list()
		for(var/contact_id in SSflight_operations.vessels)
			var/datum/flight_vessel/contact_vessel = SSflight_operations.vessels[contact_id]
			if(contact_vessel == vessel || contact_vessel.orbit_parent_id != vessel.orbit_parent_id)
				continue
			contacts += list(list("name" = contact_vessel.name, "ref" = contact_vessel.id))
		data["contacts"] = contacts
	var/datum/flight_plan/plan = vessel.active_plan
	if(plan)
		data["plan"] = list(
			"id" = plan.id,
			"destination_id" = plan.destination?.id,
			"origin_id" = plan.origin?.id || vessel.orbit_parent_id,
			"destination" = plan.destination?.name,
			"state" = plan.state,
			"state_name" = plan.state_name(),
			"failure" = plan.failure_reason,
			"eta" = max(0, plan.estimated_arrival_at - world.time),
			"departure_at" = plan.departure_at,
			"arrival_at" = plan.estimated_arrival_at,
			"generation_state" = plan.generation_state,
			"generation_progress" = plan.generation_progress,
			"generation_stage" = plan.generation_stage,
		)
	var/datum/expedition_site/active_expedition = vessel.active_expedition
	if(active_expedition && !QDELETED(active_expedition))
		data["expedition"] = list(
			"name" = active_expedition.name,
			"objective" = active_expedition.mission?.objective_text() || "Reach the surveyed site.",
			"progress" = active_expedition.mission?.progress_text() || "Awaiting departure",
			"infrastructure" = active_expedition.generated_station_status_text(),
			"status" = active_expedition.status,
			"materialized" = active_expedition.z_level > 0,
		)
	return data

/datum/flight_operations_ui/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel)
		return FALSE
	switch(action)
		if("jump")
			if(vessel.active_plan)
				if(vessel.active_plan.state != FLIGHT_PLAN_DRAFT)
					return FALSE
				SSflight_operations.plans -= vessel.active_plan.id
				qdel(vessel.active_plan)
			var/datum/flight_plan/jump_plan = SSflight_operations.create_plan(vessel, params["destination_id"])
			if(!jump_plan || !jump_plan.start())
				to_chat(ui.user, span_warning("The jump could not be initiated."))
				return TRUE
			to_chat(ui.user, span_notice("Jump sequence engaged for [jump_plan.destination.name]."))
			return TRUE
		if("select_destination")
			if(vessel.active_plan)
				if(vessel.active_plan.state != FLIGHT_PLAN_DRAFT)
					return FALSE
				SSflight_operations.plans -= vessel.active_plan.id
				qdel(vessel.active_plan)
			var/datum/flight_plan/plan = SSflight_operations.create_plan(vessel, params["destination_id"])
			if(!plan)
				to_chat(ui.user, span_warning("The selected destination cannot be added to this vessel's flight plan."))
			return TRUE
		if("engage")
			if(!vessel.active_plan?.start())
				to_chat(ui.user, span_warning("The flight plan could not be engaged."))
			return TRUE
		if("abort")
			vessel.active_plan?.request_abort()
			return TRUE
		if("abandon_expedition")
			SSexpedition.abandon_assignment(ui.user, vessel)
			return TRUE
		if("toggle_engines")
			if(!vessel.ship)
				return FALSE
			vessel.ship.engines_state = !vessel.ship.engines_state
			for(var/datum/ship_engine/engine in vessel.ship.engines)
				if(vessel.ship.engines_state == !engine.is_on())
					engine.toggle()
			return TRUE
		if("thrust_limit")
			if(!vessel.ship)
				return FALSE
			vessel.ship.thrust_limit = clamp(text2num(params["value"]) / 100, 0, 1)
			for(var/datum/ship_engine/engine in vessel.ship.engines)
				engine.set_thrust_limit(vessel.ship.thrust_limit)
			return TRUE
	return FALSE

/obj/machinery/computer/ship
	var/datum/flight_operations_ui/flight_operations_ui

/obj/machinery/computer/ship/proc/open_flight_operations(mob/user, datum/tgui/ui)
	if(!flight_operations_ui)
		flight_operations_ui = new(src)
	flight_operations_ui.tgui_interact(user, ui)

/obj/machinery/computer/ship/helm/tgui_interact(mob/user, datum/tgui/ui)
	open_flight_operations(user, ui)

/obj/machinery/computer/ship/navigation/tgui_interact(mob/user, datum/tgui/ui)
	open_flight_operations(user, ui)

/obj/machinery/computer/shuttle_control/explore
	var/datum/flight_operations_ui/flight_operations_ui

/obj/machinery/computer/shuttle_control/explore/tgui_interact(mob/user, datum/tgui/ui)
	if(!flight_operations_ui)
		flight_operations_ui = new(src)
	flight_operations_ui.tgui_interact(user, ui)
