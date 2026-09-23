SUBSYSTEM_DEF(flight_operations)
	name = "Flight Operations"
	wait = 1 SECOND
	priority = FIRE_PRIORITY_DEFAULT
	dependencies = list(/datum/controller/subsystem/shuttles)
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	var/list/destinations = list()
	var/list/destination_by_target = list()
	var/list/vessels = list()
	var/list/vessel_by_ship = list()
	var/list/ports = list()
	var/list/port_by_landmark = list()
	var/list/plans = list()
	var/tmp/list/current_run

/datum/controller/subsystem/flight_operations/Initialize()
	rebuild_registry()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/flight_operations/Recover()
	destinations = SSflight_operations.destinations
	destination_by_target = SSflight_operations.destination_by_target
	vessels = SSflight_operations.vessels
	vessel_by_ship = SSflight_operations.vessel_by_ship
	ports = SSflight_operations.ports
	port_by_landmark = SSflight_operations.port_by_landmark
	plans = SSflight_operations.plans

/datum/controller/subsystem/flight_operations/proc/rebuild_registry()
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
	destinations[system.id] = system
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

/datum/controller/subsystem/flight_operations/proc/make_id(prefix, value)
	var/safe = lowertext(replacetext("[value]", " ", "-"))
	safe = replacetext(safe, "—", "-")
	var/base = "[prefix]-[safe]"
	var/candidate = base
	var/suffix = 2
	while(destinations[candidate] || vessels[candidate])
		candidate = "[base]-[suffix++]"
	return candidate

/datum/controller/subsystem/flight_operations/proc/register_destination(obj/effect/overmap/visitable/target)
	if(!target || QDELETED(target))
		return null
	var/existing_id = destination_by_target[REF(target)]
	if(existing_id)
		return destinations[existing_id]
	var/datum/flight_destination/destination = new
	destination.id = make_id("destination", target.name)
	destination.name = target.name
	destination.description = target.desc
	destination.target = target
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
	destinations[destination.id] = destination
	destination_by_target[REF(target)] = destination.id
	return destination

/datum/controller/subsystem/flight_operations/proc/first_planet_id()
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations[id]
		if(destination.kind == FLIGHT_DEST_SURFACE)
			return destination.id
	return "system-vir"

/datum/controller/subsystem/flight_operations/proc/planet_id_named(planet_name)
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations[id]
		if(destination.kind == FLIGHT_DEST_SURFACE && lowertext(destination.name) == lowertext(planet_name))
			return destination.id
	return null

/datum/controller/subsystem/flight_operations/proc/destination_id_named(destination_name)
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations[id]
		if(lowertext(destination.name) == lowertext(destination_name))
			return destination.id
	return null

/datum/controller/subsystem/flight_operations/proc/normalize_celestial_hierarchy()
	var/sif_id = planet_id_named("Sif") || first_planet_id()
	for(var/id in destinations)
		var/datum/flight_destination/destination = destinations[id]
		if(destination.kind == FLIGHT_DEST_STATION)
			destination.orbit_parent_id = sif_id
		else if(destination.kind == FLIGHT_DEST_VESSEL || destination.kind == FLIGHT_DEST_ORBIT)
			if(!destination.orbit_parent_id || destination.orbit_parent_id == "system-vir")
				destination.orbit_parent_id = sif_id

/datum/controller/subsystem/flight_operations/proc/seed_expedition_catalog()
	for(var/id in destinations.Copy())
		var/datum/flight_destination/planet = destinations[id]
		if(planet.kind != FLIGHT_DEST_SURFACE)
			continue
		var/site_count = 0
		for(var/site_id in destinations)
			var/datum/flight_destination/site_destination = destinations[site_id]
			if(site_destination.kind == FLIGHT_DEST_EXPEDITION && site_destination.orbit_parent_id == planet.id)
				site_count++
		while(site_count < 4)
			var/list/mission_types = expedition_mission_types()
			var/mission_type = pick(mission_types)
			var/difficulty = pick(EXP_DIFF_LOW, EXP_DIFF_LOW, EXP_DIFF_MED, EXP_DIFF_HIGH)
			var/datum/expedition_mission/mission = new mission_type(difficulty)
			mission.faction_type = expedition_pick_faction(difficulty)
			var/datum/expedition_site/site = SSexpedition.create_site_descriptor(mission, difficulty, null, null, planet.id)
			if(!site)
				qdel(mission)
				break
			site_count++

/datum/controller/subsystem/flight_operations/proc/register_expedition(datum/expedition_site/site)
	if(!site || QDELETED(site))
		return null
	if(site.flight_destination_id && destinations[site.flight_destination_id])
		return destinations[site.flight_destination_id]
	var/datum/flight_destination/destination = new
	destination.id = make_id("expedition", site.name)
	destination.name = site.name
	destination.description = site.mission?.desc || "A procedurally surveyed expedition site."
	destination.kind = FLIGHT_DEST_EXPEDITION
	destination.expedition = site
	destination.target = site.overmap_sector
	destination.required_capabilities = FLIGHT_CAP_EXPEDITION | FLIGHT_CAP_LAND
	destination.orbit_parent_id = site.parent_destination_id || first_planet_id()
	destination.body_radius = 0.45
	destination.body_color = "#ffc45c"
	destination.surface_latitude = rand(-75, 75)
	destination.surface_longitude = rand(-180, 180)
	destinations[destination.id] = destination
	if(destination.target)
		destination_by_target[REF(destination.target)] = destination.id
	site.flight_destination_id = destination.id
	return destination

/datum/controller/subsystem/flight_operations/proc/unregister_destination(id)
	var/datum/flight_destination/destination = destinations[id]
	if(!destination)
		return
	if(destination.target)
		destination_by_target -= REF(destination.target)
	destinations -= id
	qdel(destination)

/datum/controller/subsystem/flight_operations/proc/destination_for_target(atom/target)
	RETURN_TYPE(/datum/flight_destination)
	if(!target)
		return null
	var/id = destination_by_target[REF(target)]
	return destinations[id]

/datum/controller/subsystem/flight_operations/proc/register_vessel(obj/effect/overmap/visitable/ship/ship)
	if(!ship || QDELETED(ship))
		return null
	var/existing_id = vessel_by_ship[REF(ship)]
	if(existing_id)
		var/datum/flight_vessel/existing = vessels[existing_id]
		if(istype(ship, /obj/effect/overmap/visitable/ship/landable))
			var/obj/effect/overmap/visitable/ship/landable/landable = ship
			existing.shuttle = SSshuttles.shuttles[landable.shuttle]
			if(existing.shuttle)
				existing.capabilities |= FLIGHT_CAP_LAND | FLIGHT_CAP_EXPEDITION
		return existing
	var/datum/flight_vessel/vessel = new
	vessel.id = make_id("vessel", ship.name)
	vessel.name = ship.name
	vessel.ship = ship
	vessel.capabilities = FLIGHT_CAP_STRATEGIC | FLIGHT_CAP_DOCK
	if(istype(ship, /obj/effect/overmap/visitable/ship/landable))
		var/obj/effect/overmap/visitable/ship/landable/landable = ship
		vessel.shuttle = SSshuttles.shuttles[landable.shuttle]
		vessel.capabilities |= FLIGHT_CAP_LAND | FLIGHT_CAP_EXPEDITION
	vessels[vessel.id] = vessel
	vessel_by_ship[REF(ship)] = vessel.id
	ship.flight_vessel_id = vessel.id
	register_destination(ship)
	var/obj/effect/overmap/visitable/physical_target
	if(vessel.shuttle?.current_location)
		physical_target = waypoint_sector(vessel.shuttle.current_location)
	var/datum/flight_destination/physical_context = destination_for_target(physical_target)
	vessel.orbit_parent_id = physical_context?.orbit_parent_id || planet_id_named("Sif") || first_planet_id()
	if(vessel.shuttle?.current_location)
		var/datum/flight_port/current_port = port_for_landmark(vessel.shuttle.current_location)
		if(current_port)
			vessel.docked_port_id = current_port.id
			current_port.occupied_by = vessel
	else if(istype(ship, /obj/effect/overmap/visitable/ship/exploration_carrier))
		vessel.orbit_parent_id = planet_id_named("Sif") || first_planet_id()
		vessel.docked_port_id = null
	return vessel

/datum/controller/subsystem/flight_operations/proc/sync_vessel_destinations()
	var/sif_id = planet_id_named("Sif") || first_planet_id()
	for(var/id in vessels)
		var/datum/flight_vessel/vessel = vessels[id]
		var/datum/flight_destination/destination = destination_for_target(vessel.ship)
		if(!destination)
			continue
		if(istype(vessel.ship, /obj/effect/overmap/visitable/ship/exploration_carrier))
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
		if(!istype(vessel.ship, /obj/effect/overmap/visitable/ship/exploration_carrier))
			destination.orbit_period = 600

/datum/controller/subsystem/flight_operations/proc/register_mapped_ports()
	for(var/id in ports)
		qdel(ports[id])
	ports.Cut()
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
		port.landmark = landmark
		if(host_id == station_id)
			port.berth_group = "southern-cross-hangar-three"
		ports[port.id] = port
		port_by_landmark[REF(landmark)] = port.id

/datum/controller/subsystem/flight_operations/proc/sync_vessel_ports()
	for(var/id in ports)
		var/datum/flight_port/port = ports[id]
		port.occupied_by = null
	for(var/id in vessels)
		var/datum/flight_vessel/vessel = vessels[id]
		if(istype(vessel.ship, /obj/effect/overmap/visitable/ship/exploration_carrier))
			vessel.docked_port_id = null
			continue
		var/datum/flight_port/current_port = port_for_landmark(vessel.shuttle?.current_location)
		vessel.docked_port_id = current_port?.id
		if(current_port)
			current_port.occupied_by = vessel

/datum/controller/subsystem/flight_operations/proc/port_for_landmark(obj/effect/shuttle_landmark/landmark)
	return ports[port_by_landmark[REF(landmark)]]

/datum/controller/subsystem/flight_operations/proc/reserve_arrival_port(datum/flight_plan/plan)
	if(!plan?.vessel?.shuttle)
		return null
	for(var/id in ports)
		var/datum/flight_port/port = ports[id]
		if(!port.serves(plan.destination.id) || !port.can_accept(plan.vessel, plan))
			continue
		port.reserved_by = plan
		return port
	return null

/datum/controller/subsystem/flight_operations/proc/set_vessel_docked_port(datum/flight_vessel/vessel, datum/flight_port/new_port)
	if(!vessel)
		return
	var/datum/flight_port/old_port = ports[vessel.docked_port_id]
	if(old_port?.occupied_by == vessel)
		old_port.occupied_by = null
	vessel.docked_port_id = new_port?.id
	if(new_port)
		new_port.occupied_by = vessel

/datum/controller/subsystem/flight_operations/proc/vessel_for_ship(obj/effect/overmap/visitable/ship/ship)
	var/id = ship?.flight_vessel_id || vessel_by_ship[REF(ship)]
	return vessels[id]

/datum/controller/subsystem/flight_operations/proc/create_plan(datum/flight_vessel/vessel, destination_id)
	var/datum/flight_destination/destination = destinations[destination_id]
	if(!vessel || !destination?.is_available() || vessel.active_plan)
		return null
	if(destination.expedition)
		var/datum/expedition_site/site = destination.expedition
		if(site.assigned_flight_vessel && site.assigned_flight_vessel != vessel)
			return null
		site.assigned_flight_vessel = vessel
		site.assigned_shuttle = vessel.shuttle
		vessel.active_expedition = site
	var/datum/flight_destination/origin = destinations[vessel.current_destination_id()]
	var/datum/flight_plan/plan = new(vessel, origin, destination)
	vessel.active_plan = plan
	plans[plan.id] = plan
	return plan

/datum/controller/subsystem/flight_operations/fire(resumed = FALSE)
	if(!resumed)
		sync_vessel_destinations()
		current_run = plans.Copy()
	while(length(current_run))
		var/id = current_run[length(current_run)]
		current_run.len--
		var/datum/flight_plan/plan = plans[id]
		if(!plan || QDELETED(plan))
			plans -= id
			continue
		process_plan(plan)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/flight_operations/proc/process_plan(datum/flight_plan/plan)
	if(plan.state == FLIGHT_PLAN_FAILED)
		if(world.time >= plan.terminal_cleanup_at)
			finish_plan(plan)
		return
	if(plan.cancel_requested)
		plan.state = FLIGHT_PLAN_ABORTING
		plan.failure_reason = "Flight cancelled by operator."
		plan.release_leases(TRUE)
		finish_plan(plan)
		return
	if(plan.state == FLIGHT_PLAN_PREPARING)
		var/obj/effect/overmap/visitable/ship/landable/landable = plan.vessel.ship
		if(istype(landable) && landable.status == SHIP_STATUS_LANDED)
			if(!landable.landmark || !plan.vessel.shuttle)
				plan.fail("The vessel has no open-space departure landmark.")
				return
			plan.state = FLIGHT_PLAN_UNDOCKING
			plan.departure_deadline = world.time + 20 SECONDS
			plan.vessel.shuttle.short_jump(landable.landmark)
			return
		enter_transit(plan)
		return
	if(plan.state == FLIGHT_PLAN_UNDOCKING)
		var/obj/effect/overmap/visitable/ship/landable/landable = plan.vessel.ship
		if(istype(landable) && landable.status == SHIP_STATUS_OVERMAP && plan.vessel.shuttle.moving_status == SHUTTLE_IDLE)
			enter_transit(plan)
			return
		if(world.time > plan.departure_deadline)
			plan.fail("The vessel could not complete undocking.")
		return
	if(plan.state == FLIGHT_PLAN_TRANSIT)
		if(world.time < plan.estimated_arrival_at)
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
		if(!plan.arrival_port && !plan.destination.expedition?.landing_waypoint)
			plan.state = FLIGHT_PLAN_ARRIVED
			plan.arrival_at = world.time
			plan.release_leases()
			finish_plan(plan)
			return
		plan.state = FLIGHT_PLAN_ARRIVING
		plan.departure_deadline = world.time + 30 SECONDS
		return
	if(plan.state == FLIGHT_PLAN_ARRIVING)
		var/obj/effect/overmap/visitable/ship/landable/landable = plan.vessel.ship
		var/obj/effect/shuttle_landmark/expected_landmark = plan.arrival_port?.landmark || plan.destination.expedition?.landing_waypoint
		if(!plan.vessel.shuttle || (istype(landable) && landable.status == SHIP_STATUS_LANDED && plan.vessel.shuttle.moving_status == SHUTTLE_IDLE && plan.vessel.shuttle.current_location == expected_landmark))
			set_vessel_docked_port(plan.vessel, plan.arrival_port)
			plan.state = FLIGHT_PLAN_ARRIVED
			plan.arrival_at = world.time
			plan.release_leases()
			finish_plan(plan)
			return
		if(world.time > plan.departure_deadline)
			plan.fail("The vessel could not complete its landing sequence.")

/datum/controller/subsystem/flight_operations/proc/enter_transit(datum/flight_plan/plan)
	set_vessel_docked_port(plan.vessel, null)
	plan.state = FLIGHT_PLAN_TRANSIT
	plan.departure_at = world.time
	plan.estimated_arrival_at = world.time + FLIGHT_DEFAULT_TRANSIT_TIME
	if(plan.generation_state != FLIGHT_GENERATION_RUNNING)
		return TRUE
	plan.generation_stage = "Generating destination during transit"
	if(SSexpedition.materialize_site(plan.destination.expedition, plan))
		return TRUE
	plan.fail("Destination generation could not be started.")
	return FALSE

/datum/controller/subsystem/flight_operations/proc/execute_arrival(datum/flight_plan/plan)
	var/datum/flight_vessel/vessel = plan.vessel
	var/datum/flight_destination/destination = plan.destination
	if(vessel.shuttle && destination.expedition?.landing_waypoint)
		vessel.shuttle.set_destination(destination.expedition.landing_waypoint)
		vessel.shuttle.short_jump(destination.expedition.landing_waypoint)
		vessel.orbit_parent_id = destination.orbit_parent_id
		vessel.docked_port_id = null
		return TRUE
	if(vessel.shuttle && plan.arrival_port?.can_accept(vessel, plan))
		vessel.shuttle.set_destination(plan.arrival_port.landmark)
		vessel.shuttle.short_jump(plan.arrival_port.landmark)
		vessel.orbit_parent_id = destination.orbit_parent_id
		return TRUE
	if(vessel.ship && destination.kind != FLIGHT_DEST_STATION && destination.kind != FLIGHT_DEST_VESSEL)
		vessel.orbit_parent_id = destination.id
		vessel.docked_port_id = null
		return TRUE
	return FALSE

/datum/controller/subsystem/flight_operations/proc/compatible_waypoint(obj/effect/overmap/visitable/target, datum/shuttle/autodock/overmap/shuttle)
	if(!target || !shuttle)
		return null
	var/list/waypoints = target.get_waypoints(shuttle.name)
	for(var/obj/effect/shuttle_landmark/waypoint in waypoints)
		if(waypoint.is_valid(shuttle))
			return waypoint
	return null

/datum/controller/subsystem/flight_operations/proc/finish_plan(datum/flight_plan/plan)
	plans -= plan.id
	if(plan.vessel?.active_plan == plan)
		plan.vessel.active_plan = null
	qdel(plan)

/datum/controller/subsystem/flight_operations/stat_entry(msg)
	msg = "V:[length(vessels)] D:[length(destinations)] F:[length(plans)]"
	return ..()
