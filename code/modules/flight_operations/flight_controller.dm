// The flight operations system (was SSflight_operations): vessels, destinations, ports and
// flight plans, with plan processing run by plan_step (1 s). Not on demand:
// every step also re-syncs vessel destinations, which the consoles read even with no plan in flight.
SYSTEM_DEF(flight)
	name = "Flight Operations"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	// The old subsystem depended on SSshuttles (it registers SSshuttles.ships); boot right after it.
	needs = list(/datum/system/shuttles, /datum/system/expedition)
	// rebuild_registry() registers any live expedition sites.
	var/list/destinations = list()
	var/list/destination_by_target = list()
	var/list/vessels = list()
	var/list/vessel_by_ship = list()
	var/list/ports = list()
	var/list/port_by_landmark = list()
	var/list/plans = list()
	var/tmp/list/current_run
	/// TRUE while a plan pass that ran out of budget waits to resume.
	VAR_PRIVATE/plans_resuming = FALSE

CAPABILITIES(/datum/system/flight)
	owns_many(nameof(destinations))
	owns_many(nameof(plans))
	owns_many(nameof(ports))
	owns_many(nameof(vessels))

/datum/system/flight/initialize()
	initialized = TRUE
	rebuild_registry()
	log_world("World service [name] initialized: [length(vessels)] vessels, [length(destinations)] destinations, [length(ports)] ports.")

/datum/system/flight/proc/rebuild_registry()
	var/has_sif = FALSE
	for(var/obj/effect/overmap/visitable/planet/planet as anything in REGISTRY_MEMBERS(REGISTRY_OVERMAP_VISITABLES))
		if(lowertext(planet.name) == "sif")
			has_sif = TRUE
	if(!has_sif)
		new /obj/effect/overmap/visitable/planet/sif/navigation(null)
	var/datum/flight_destination/system = new
	system.id = "system-vir"
	system.name = "Vir"
	system.description = "The Vir system primary."
	system.kind = FLIGHT_DEST_SYSTEM
	system.body_radius = 5
	system.body_color = "#ffd36a"
	rel_add(src, nameof(destinations), system, system.id)
	for(var/obj/effect/overmap/visitable/target as anything in REGISTRY_MEMBERS(REGISTRY_OVERMAP_VISITABLES))
		register_destination(target)
	normalize_celestial_hierarchy()
	for(var/obj/effect/overmap/visitable/ship/ship as anything in SSshuttles.ships)
		register_vessel(ship)
	// Ports reference destination IDs, including destinations created while
	// registering vessels. Resolve physical occupancy only after both registries exist.
	register_mapped_ports()
	sync_vessel_ports()
	sync_vessel_destinations()
	// Vessel registration can create destinations which were not present during the
	// initial overmap scan. Normalize after that final source of registry entries.
	normalize_celestial_hierarchy()
	for(var/key in SSexpedition?.sites)
		var/datum/expedition_site/site = SSexpedition.sites[key]
		if(istype(site))
			register_expedition(site)
	seed_expedition_catalog()

/datum/system/flight/proc/make_id(prefix, value)
	var/safe = lowertext(replacetext("[value]", " ", "-"))
	safe = replacetext(safe, "—", "-")
	var/base = "[prefix]-[safe]"
	var/candidate = base
	var/suffix = 2
	while(destinations?[candidate] || vessels?[candidate])
		candidate = "[base]-[suffix++]"
	return candidate

/datum/system/flight/proc/register_destination(obj/effect/overmap/visitable/target)
	if(!target || QDELETED(target))
		return null
	var/existing_id = destination_by_target[REF(target)]
	if(existing_id)
		return destinations?[existing_id]
	var/datum/flight_destination/destination = new
	destination.id = make_id("destination", target.name)
	destination.name = target.name
	destination.description = target.desc
	rel_set(destination, nameof(destination.target), target)
	if(istype(target, /obj/effect/overmap/visitable/planet))
		destination.kind = FLIGHT_DEST_SURFACE
		destination.orbit_parent_id = "system-vir"
		destination.required_capabilities = FLIGHT_CAP_STRATEGIC
		destination.body_radius = 3.4
		destination.body_color = "#5f9f8b"
		destination.orbit_radius = 64
		destination.orbit_period = 12 HOURS
		destination.orbit_inclination = 4
	else
		destination.kind = istype(target, /obj/effect/overmap/visitable/ship) ? FLIGHT_DEST_VESSEL : (target.base ? FLIGHT_DEST_STATION : FLIGHT_DEST_ORBIT)
		destination.orbit_parent_id = first_planet_id()
		destination.body_radius = destination.kind == FLIGHT_DEST_STATION ? 1.8 : 1.15
		destination.body_color = destination.kind == FLIGHT_DEST_STATION ? "#bda5ff" : "#62d5ff"
		destination.orbit_radius = destination.kind == FLIGHT_DEST_STATION ? 14 : 19
		destination.orbit_period = destination.kind == FLIGHT_DEST_STATION ? 45 MINUTES : 60 MINUTES
		destination.orbit_inclination = destination.kind == FLIGHT_DEST_STATION ? -7 : 9
	destination.orbit_phase = 35
	if(lowertext(destination.name) == "southern cross")
		destination.orbit_radius = 13
		destination.orbit_phase = 210
	if(istype(target, /obj/effect/overmap/visitable/ship/exploration_carrier))
		destination.orbit_radius = 19
		destination.orbit_phase = 42
	rel_add(src, nameof(destinations), destination, destination.id)
	var/target_ref = REF(target) // lookup keyed by ref string: plain data
	destination_by_target[target_ref] = destination.id
	return destination

/datum/system/flight/proc/first_planet_id()
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations?[id]
		if(destination.kind == FLIGHT_DEST_SURFACE)
			return destination.id
	return "system-vir"

/datum/system/flight/proc/planet_id_named(planet_name)
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations?[id]
		if(destination.kind == FLIGHT_DEST_SURFACE && lowertext(destination.name) == lowertext(planet_name))
			return destination.id
	return null

/datum/system/flight/proc/destination_id_named(destination_name)
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations?[id]
		if(lowertext(destination.name) == lowertext(destination_name))
			return destination.id
	return null

/datum/system/flight/proc/normalize_celestial_hierarchy()
	var/sif_id = planet_id_named("Sif") || first_planet_id()
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations?[id]
		if(destination.kind == FLIGHT_DEST_STATION)
			destination.orbit_parent_id = sif_id
		else if(destination.kind == FLIGHT_DEST_VESSEL || destination.kind == FLIGHT_DEST_ORBIT)
			if(!destination.orbit_parent_id || destination.orbit_parent_id == "system-vir")
				destination.orbit_parent_id = sif_id

/datum/system/flight/proc/seed_expedition_catalog()
	for(var/id in destinations.Copy())
		var/datum/flight_destination/planet = destinations?[id]
		if(planet.kind != FLIGHT_DEST_SURFACE)
			continue
		var/site_count = 0
		for(var/site_id in destinations)
			var/datum/flight_destination/site_destination = destinations?[site_id]
			if(site_destination.kind == FLIGHT_DEST_EXPEDITION && site_destination.orbit_parent_id == planet.id)
				site_count++
		while(site_count < 4)
			var/list/mission_types = GLOB.expedition_mission_types
			var/mission_type = pick(mission_types)
			var/difficulty = pick(EXP_DIFF_LOW, EXP_DIFF_LOW, EXP_DIFF_MED, EXP_DIFF_HIGH)
			var/datum/expedition_mission/mission = new mission_type(difficulty)
			mission.faction_type = expedition_pick_faction(difficulty)
			var/datum/expedition_site/site = SSexpedition.create_site_descriptor(mission, difficulty, null, null, planet.id)
			if(!site)
				spent(mission)
				break
			site_count++

/datum/system/flight/proc/sync_vessel_destinations()
	var/sif_id = planet_id_named("Sif") || first_planet_id()
	for(var/id in vessels)
		var/datum/flight_vessel/vessel = vessels?[id]
		var/datum/flight_destination/destination = destination_for_target(vessel.ship())
		if(!destination)
			continue
		if(istype(vessel.ship(), /obj/effect/overmap/visitable/ship/exploration_carrier))
			vessel.orbit_parent_id = sif_id
			vessel.docked_port_id = null
			destination.orbit_parent_id = sif_id
			destination.orbit_radius = 19
			destination.orbit_period = 60 MINUTES
			destination.orbit_phase = 42
		else
			destination.orbit_parent_id = vessel.orbit_parent_id || sif_id
			destination.orbit_radius = vessel.docked_port_id ? 0 : 11
		destination.orbit_inclination = 0
		if(!istype(vessel.ship(), /obj/effect/overmap/visitable/ship/exploration_carrier))
			destination.orbit_period = 600

/datum/system/flight/proc/register_mapped_ports()
	rel_clear(src, nameof(ports))
	port_by_landmark.Cut()
	if(length(using_map.station_levels))
		var/station_z = using_map.station_levels[1]
		if(!SSshuttles.registered_shuttle_landmarks["hangar_3_expedition"])
			var/turf/general_berth = locate(161, 140, station_z)
			if(istype(get_area(general_berth), /area/hangar/three))
				new /obj/effect/shuttle_landmark/southern_cross/expedition_station/general(general_berth)
		if(!SSshuttles.registered_shuttle_landmarks["hangar_3_echidna"])
			var/turf/echidna_berth = locate(155, 141, station_z)
			if(istype(get_area(echidna_berth), /area/hangar/three))
				new /obj/effect/shuttle_landmark/southern_cross/expedition_station/echidna(echidna_berth)
	var/carrier_id = destination_id_named("Exploration Carrier")
	var/station_id = destination_id_named("Southern Cross")
	var/static/list/carrier_port_tags = list(
		"exphangar_1",
		"baby_mammoth_dock",
		"ursula_dock",
		"stargazer_dock",
		"needle_dock",
		"echidna_dock",
	)
	for(var/landmark_tag in SSshuttles.registered_shuttle_landmarks)
		var/obj/effect/shuttle_landmark/landmark = SSshuttles.registered_shuttle_landmarks[landmark_tag]
		var/host_id
		if(landmark.landmark_tag in carrier_port_tags)
			host_id = carrier_id
		else if(landmark.landmark_tag in list("hangar_3_expedition", "hangar_3_echidna"))
			host_id = station_id
		if(!host_id)
			continue
		var/datum/flight_port/port = new
		port.id = "port-[landmark.landmark_tag]"
		port.name = landmark.name
		port.host_destination_id = host_id
		port.serves_destination_ids = list(host_id)
		rel_set(port, nameof(port.landmark), landmark)
		if(host_id == station_id)
			port.berth_group = "southern-cross-hangar-three"
		rel_add(src, nameof(ports), port, port.id)
		var/landmark_ref = REF(landmark) // lookup keyed by ref string: plain data
		port_by_landmark[landmark_ref] = port.id

/datum/system/flight/proc/sync_vessel_ports()
	for(var/id in ports)
		var/datum/flight_port/port = ports?[id]
		rel_clear(port, nameof(port.occupied_by))
	for(var/id in vessels)
		var/datum/flight_vessel/vessel = vessels?[id]
		if(istype(vessel.ship(), /obj/effect/overmap/visitable/ship/exploration_carrier))
			vessel.docked_port_id = null
			continue
		var/datum/flight_port/current_port = port_for_landmark(vessel.shuttle()?.current_location())
		vessel.docked_port_id = current_port?.id
		if(current_port)
			rel_set(current_port, nameof(current_port.occupied_by), vessel)

/datum/system/flight/proc/set_vessel_docked_port(datum/flight_vessel/vessel, datum/flight_port/new_port)
	if(!vessel)
		return
	var/datum/flight_port/old_port = ports?[vessel.docked_port_id]
	if(old_port?.occupied_by() == vessel)
		rel_clear(old_port, nameof(old_port.occupied_by))
	vessel.docked_port_id = new_port?.id
	if(new_port)
		rel_set(new_port, nameof(new_port.occupied_by), vessel)

/datum/system/flight/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(plan_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/flight/proc/plan_step(dt)
	if(!plans_resuming)
		sync_vessel_destinations()
		current_run = plans.Copy()
	plans_resuming = FALSE
	while(length(current_run))
		var/id = current_run[length(current_run)]
		current_run.len--
		var/datum/flight_plan/plan = plans?[id]
		if(!plan || QDELETED(plan))
			own_take_member(src, nameof(plans), id)
			continue
		process_plan(plan)
		if(KERNEL_OVER_BUDGET)
			plans_resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/flight/proc/process_plan(datum/flight_plan/plan)
	if(plan.state == FLIGHT_PLAN_FAILED)
		if(!BEFORE(src, plan.terminal_cleanup_at, CLOCK_WORLD))
			finish_plan(plan)
		return
	if(plan.cancel_requested)
		plan.state = FLIGHT_PLAN_ABORTING
		plan.failure_reason = "Flight cancelled by operator."
		plan.release_leases(TRUE)
		finish_plan(plan)
		return
	if(plan.state == FLIGHT_PLAN_PREPARING)
		var/obj/effect/overmap/visitable/ship/landable/landable = plan.vessel.ship()
		if(istype(landable) && landable.status == SHIP_STATUS_LANDED)
			if(!landable.landmark || !plan.vessel.shuttle())
				plan.fail("The vessel has no open-space departure landmark.")
				return
			plan.state = FLIGHT_PLAN_UNDOCKING
			EXPIRY_SET(plan, departure_deadline, 20 SECONDS, CLOCK_WORLD)
			plan.vessel.shuttle().short_jump(landable.landmark)
			return
		enter_transit(plan)
		return
	if(plan.state == FLIGHT_PLAN_UNDOCKING)
		var/obj/effect/overmap/visitable/ship/landable/landable = plan.vessel.ship()
		if(istype(landable) && landable.status == SHIP_STATUS_OVERMAP && plan.vessel.shuttle().moving_status == SHUTTLE_IDLE)
			enter_transit(plan)
			return
		if(ELAPSED_SINCE(src, plan.departure_deadline, CLOCK_WORLD) > 0)
			plan.fail("The vessel could not complete undocking.")
		return
	if(plan.state == FLIGHT_PLAN_TRANSIT)
		if(BEFORE(src, plan.estimated_arrival_at, CLOCK_WORLD))
			return
		if(plan.generation_state == FLIGHT_GENERATION_RUNNING)
			plan.state = FLIGHT_PLAN_HOLDING
			return
		if(plan.generation_state == FLIGHT_GENERATION_FAILED)
			plan.fail("Destination generation failed: [plan.generation_stage]")
			return
		plan.state = FLIGHT_PLAN_APPROACH
	if(plan.state == FLIGHT_PLAN_HOLDING)
		if(plan.generation_state == FLIGHT_GENERATION_READY)
			plan.state = FLIGHT_PLAN_APPROACH
		else
			return
	if(plan.state == FLIGHT_PLAN_APPROACH)
		if(!execute_arrival(plan))
			plan.fail("The reserved arrival port became unavailable.")
			return
		if(!plan.arrival_port() && !plan.destination().expedition()?.landing_waypoint)
			plan.state = FLIGHT_PLAN_ARRIVED
			EXPIRY_STAMP(plan, arrival_at, CLOCK_WORLD)
			plan.release_leases()
			finish_plan(plan)
			return
		plan.state = FLIGHT_PLAN_ARRIVING
		EXPIRY_SET(plan, departure_deadline, 30 SECONDS, CLOCK_WORLD)
		return
	if(plan.state == FLIGHT_PLAN_ARRIVING)
		var/obj/effect/overmap/visitable/ship/landable/landable = plan.vessel.ship()
		var/obj/effect/shuttle_landmark/expected_landmark = plan.arrival_port()?.landmark() || plan.destination().expedition()?.landing_waypoint
		if(!plan.vessel.shuttle() || (istype(landable) && landable.status == SHIP_STATUS_LANDED && plan.vessel.shuttle().moving_status == SHUTTLE_IDLE && plan.vessel.shuttle().current_location() == expected_landmark))
			set_vessel_docked_port(plan.vessel, plan.arrival_port())
			plan.state = FLIGHT_PLAN_ARRIVED
			EXPIRY_STAMP(plan, arrival_at, CLOCK_WORLD)
			plan.release_leases()
			finish_plan(plan)
			return
		if(ELAPSED_SINCE(src, plan.departure_deadline, CLOCK_WORLD) > 0)
			plan.fail("The vessel could not complete its landing sequence.")

/datum/system/flight/proc/enter_transit(datum/flight_plan/plan)
	set_vessel_docked_port(plan.vessel, null)
	plan.state = FLIGHT_PLAN_TRANSIT
	EXPIRY_STAMP(plan, departure_at, CLOCK_WORLD)
	EXPIRY_SET(plan, estimated_arrival_at, FLIGHT_DEFAULT_TRANSIT_TIME, CLOCK_WORLD)
	if(plan.generation_state != FLIGHT_GENERATION_RUNNING)
		return TRUE
	plan.generation_stage = "Generating destination during transit"
	if(SSexpedition.materialize_site(plan.destination().expedition(), plan))
		return TRUE
	plan.fail("Destination generation could not be started.")
	return FALSE

/datum/system/flight/proc/execute_arrival(datum/flight_plan/plan)
	var/datum/flight_vessel/vessel = plan.vessel
	var/datum/flight_destination/destination = plan.destination()
	if(vessel.shuttle() && destination.expedition()?.landing_waypoint)
		vessel.shuttle().set_destination(destination.expedition().landing_waypoint)
		vessel.shuttle().short_jump(destination.expedition().landing_waypoint)
		vessel.orbit_parent_id = destination.orbit_parent_id
		vessel.docked_port_id = null
		return TRUE
	if(vessel.shuttle() && plan.arrival_port()?.can_accept(vessel, plan))
		vessel.shuttle().set_destination(plan.arrival_port().landmark())
		vessel.shuttle().short_jump(plan.arrival_port().landmark())
		vessel.orbit_parent_id = destination.orbit_parent_id
		return TRUE
	if(vessel.ship() && destination.kind != FLIGHT_DEST_STATION && destination.kind != FLIGHT_DEST_VESSEL)
		vessel.orbit_parent_id = destination.id
		vessel.docked_port_id = null
		return TRUE
	return FALSE

/datum/system/flight/proc/compatible_waypoint(obj/effect/overmap/visitable/target, datum/shuttle/autodock/overmap/shuttle)
	if(!target || !shuttle)
		return null
	var/list/waypoints = target.get_waypoints(shuttle.name)
	for(var/obj/effect/shuttle_landmark/waypoint in waypoints)
		if(waypoint.is_valid(shuttle))
			return waypoint
	return null

/datum/system/flight/proc/finish_plan(datum/flight_plan/plan)
	own_take_member(src, nameof(plans), plan.id)
	if(plan.vessel?.active_plan == plan)
		own_clear(plan.vessel, nameof(/datum/flight_vessel::active_plan), OWN_DELETE)
		return
	spent(plan)

/datum/system/flight/stat_entry(msg)
	return "[..()]V:[length(vessels)] D:[length(destinations)] F:[length(plans)]"

