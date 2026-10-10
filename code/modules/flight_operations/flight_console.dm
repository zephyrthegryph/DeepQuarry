/datum/flight_operations_ui
	var/tmp/datum/host
	var/tmp/datum/flight_vessel/forced_vessel

/datum/flight_operations_ui/New(new_host, datum/flight_vessel/new_forced_vessel = null)
	..()
	rel_set(src, nameof(host), new_host)
	rel_set(src, nameof(forced_vessel), new_forced_vessel)

/datum/flight_operations_ui/tgui_host()
	return host()

/datum/flight_operations_ui/tgui_state(mob/user)
	if(forced_vessel())
		return ADMIN_STATE(R_ADMIN | R_EVENT | R_DEBUG)
	return GLOB.tgui_default_state

CAPABILITIES(/datum/flight_operations_ui)
	interface("FlightOperations", title = "Flight Operations")
	op("jump", ui_act("jump", arg("destination_id", schema_text(4096))), then(PROC_REF(ui_act_jump)))
	op("select_destination", ui_act("select_destination", arg("destination_id")), then(PROC_REF(ui_act_select_destination)))
	op("engage", ui_act("engage"), then(PROC_REF(ui_act_engage)))
	op("abort", ui_act("abort"), then(PROC_REF(ui_act_abort)))
	op("abandon_expedition", ui_act("abandon_expedition"), then(PROC_REF(ui_act_abandon_expedition)))
	op("toggle_engines", ui_act("toggle_engines"), then(PROC_REF(ui_act_toggle_engines)))
	op("thrust_limit", ui_act("thrust_limit", arg("value", num())), then(PROC_REF(ui_act_thrust_limit)))

/datum/flight_operations_ui/ui_prepare(mob/user, datum/tgui/ui)
	if(!resolve_vessel())
		to_chat(user, span_warning("Flight Operations cannot identify this console's vessel."))
		return FALSE
	return TRUE

/datum/flight_operations_ui/proc/resolve_ship()
	if(istype(host(), /obj/machinery/computer/ship))
		var/obj/machinery/computer/ship/console = host()
		if(!console.linked())
			console.sync_linked()
		return console.linked()
	if(istype(host(), /obj/machinery/computer/shuttle_control/explore))
		var/obj/machinery/computer/shuttle_control/explore/console = host()
		var/datum/shuttle/autodock/overmap/shuttle = shuttles_shuttles()[console.shuttle_tag]
		return shuttle?.myship()
	return null

/datum/flight_operations_ui/proc/resolve_vessel()
	if(forced_vessel())
		return forced_vessel()
	var/obj/effect/overmap/visitable/ship/ship = resolve_ship()
	return SSflight?.vessel_for_ship(ship) || SSflight?.register_vessel(ship)

/datum/flight_operations_ui/proc/serialize_destinations(datum/flight_vessel/viewing_vessel)
	var/list/destination_data = list()
	var/obj/effect/overmap/visitable/ship/viewing_ship = viewing_vessel?.ship()
	for(var/id in SSflight.destinations)
		var/datum/flight_destination/destination = SSflight.destinations[id]
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
			"materialized" = !destination.expedition() || destination.expedition().z_level > 0,
			"is_current" = destination.target() == viewing_ship,
		)
		if(destination.kind == FLIGHT_DEST_VESSEL)
			var/datum/flight_vessel/render_vessel = SSflight.vessel_for_ship(destination.target())
			var/is_carrier = istype(render_vessel?.ship(), /obj/effect/overmap/visitable/ship/exploration_carrier)
			var/datum/flight_port/render_port = is_carrier ? null : SSflight.ports[render_vessel?.docked_port_id]
			render_data["scene_role"] = render_port ? "docked" : "orbital"
			render_data["docked_port_id"] = render_port?.id
			render_data["docked_host_id"] = render_port?.host_destination_id
		destination_data += list(render_data)
	return destination_data

/// /datum/flight_operations_ui's window data.
/datum/flight_operations_ui/ui_data(datum/act/eval/A)
	var/datum/flight_vessel/vessel = resolve_vessel()
	var/obj/effect/overmap/visitable/ship/ship = vessel?.ship()
	var/list/data = list(
		"vessel" = vessel?.name || "Unlinked vessel",
		"vessel_id" = vessel?.id,
		"vessel_destination_id" = SSflight?.destination_for_target(ship)?.id,
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
		"server_time" = EXPIRY_AT(null, CLOCK_WORLD, 0),
	)
	if(!vessel)
		return data
	data["destinations"] = serialize_destinations(vessel)
	if(ship)
		var/list/contacts = list()
		for(var/contact_id in SSflight.vessels)
			var/datum/flight_vessel/contact_vessel = SSflight.vessels[contact_id]
			if(contact_vessel == vessel || contact_vessel.orbit_parent_id != vessel.orbit_parent_id)
				continue
			contacts += list(list("name" = contact_vessel.name, "ref" = contact_vessel.id))
		data["contacts"] = contacts
	var/datum/flight_plan/plan = vessel.active_plan
	if(plan)
		data["plan"] = list(
			"id" = plan.id,
			"destination_id" = plan.destination()?.id,
			"origin_id" = plan.origin()?.id || vessel.orbit_parent_id,
			"destination" = plan.destination()?.name,
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
	var/datum/expedition_site/active_expedition = vessel.active_expedition()
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

/datum/flight_operations_ui/proc/ui_gate(datum/act/op/A)
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel)
		return FALSE
	return TRUE

/datum/flight_operations_ui/proc/ui_act_jump(datum/act/op/A, destination_id)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(vessel.active_plan)
		if(vessel.active_plan.state != FLIGHT_PLAN_DRAFT)
			return FALSE
		SSflight.plans -= vessel.active_plan.id
		own_clear(vessel, nameof(/datum/flight_vessel::active_plan), OWN_DELETE)
	var/datum/flight_plan/jump_plan = SSflight.create_plan(vessel, destination_id)
	if(!jump_plan || !jump_plan.start())
		to_chat(user, span_warning("The jump could not be initiated."))
		return TRUE
	to_chat(user, span_notice("Jump sequence engaged for [jump_plan.destination().name]."))
	return TRUE

/datum/flight_operations_ui/proc/ui_act_select_destination(datum/act/op/A, destination_id)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(vessel.active_plan)
		if(vessel.active_plan.state != FLIGHT_PLAN_DRAFT)
			return FALSE
		SSflight.plans -= vessel.active_plan.id
		own_clear(vessel, nameof(/datum/flight_vessel::active_plan), OWN_DELETE)
	var/datum/flight_plan/plan = SSflight.create_plan(vessel, destination_id)
	if(!plan)
		to_chat(user, span_warning("The selected destination cannot be added to this vessel's flight plan."))
	return TRUE

/datum/flight_operations_ui/proc/ui_act_engage(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel.active_plan?.start())
		to_chat(user, span_warning("The flight plan could not be engaged."))
	return TRUE

/datum/flight_operations_ui/proc/ui_act_abort(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	vessel.active_plan?.request_abort()
	return TRUE

/datum/flight_operations_ui/proc/ui_act_abandon_expedition(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	SSexpedition.abandon_assignment(user, vessel)
	return TRUE

/datum/flight_operations_ui/proc/ui_act_toggle_engines(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel.ship())
		return FALSE
	vessel.ship().engines_state = !vessel.ship().engines_state
	for(var/datum/ship_engine/engine in vessel.ship().engines)
		if(vessel.ship().engines_state == !engine.is_on())
			engine.toggle()
	return TRUE

/datum/flight_operations_ui/proc/ui_act_thrust_limit(datum/act/op/A, value)
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel.ship())
		return FALSE
	vessel.ship().thrust_limit = clamp(value / 100, 0, 1)
	for(var/datum/ship_engine/engine in vessel.ship().engines)
		engine.set_thrust_limit(vessel.ship().thrust_limit)
	return TRUE

/obj/machinery/computer/ship
	var/datum/flight_operations_ui/flight_operations_ui

CAPABILITIES(/obj/machinery/computer/ship)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	owns_one(nameof(flight_operations_ui), /datum/flight_operations_ui)
	// The buttons every ship console's window has (code/modules/overmap/ships/computers/ship.dm).
	op("sync", ui_act("sync"), then(PROC_REF(ui_act_sync)))
	op("close", ui_act("close"), then(PROC_REF(ui_act_close)))
	op("topic_sync", topic("sync"), then(PROC_REF(topic_sync)))
	op("ship_silicon_use", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req_is(nameof(ai_control), TRUE, because = MSG(ship/ai_denied))), then(PROC_REF(ship_silicon_use)))
	op("ship_ghost_view", observer(), priority(OP_PRIORITY_DEFAULT - 1), label("View"), then(PROC_REF(ship_ghost_view)))
	op("ship_console_use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req_bool(PROC_REF(ship_access_holds), because = MSG(ship/access_denied)), any_of(req_actor_kind(/mob/living/silicon, not = TRUE, because = MSG(ship/access_denied)), req_is(nameof(ai_control), TRUE, because = MSG(ship/access_denied)))), then(PROC_REF(interaction_use)))

/// Helm and navigation consoles show the Flight Operations UI.
/obj/machinery/computer/ship/proc/flight_operations()
	if(!flight_operations_ui)
		rel_set(src, nameof(flight_operations_ui), new /datum/flight_operations_ui(src))
	return flight_operations_ui

/obj/machinery/computer/ship/helm/ui_redirect(mob/user)
	return flight_operations()

/obj/machinery/computer/ship/navigation/ui_redirect(mob/user)
	return flight_operations()

/obj/machinery/computer/shuttle_control/explore
	var/datum/flight_operations_ui/flight_operations_ui

CAPABILITIES(/obj/machinery/computer/shuttle_control/explore)
	owns_one(nameof(flight_operations_ui), /datum/flight_operations_ui)
	op("plot_expedition", ui_act("plot_expedition"), then(PROC_REF(ui_act_plot_expedition)))
	op("pick", ui_act("pick"), then(PROC_REF(ui_act_pick)))

/obj/machinery/computer/shuttle_control/explore/ui_redirect(mob/user)
	if(!flight_operations_ui)
		rel_set(src, nameof(flight_operations_ui), new /datum/flight_operations_ui(src))
	return flight_operations_ui



/// Accessor for the host var.
/datum/flight_operations_ui/proc/host() as /datum
	return host

/// Accessor for the forced_vessel var.
/datum/flight_operations_ui/proc/forced_vessel() as /datum/flight_vessel
	return forced_vessel
