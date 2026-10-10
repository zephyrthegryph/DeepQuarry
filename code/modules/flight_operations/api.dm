// The flight operations system's API (code/modules/flight_operations/flight_controller.dm declares the system).
//
//   SSflight.register_vessel(ship) / vessel_for_ship(ship)          vessels
//   SSflight.register_expedition(site) / unregister_destination(id) / destination_for_target(target)   destinations
//   SSflight.reserve_arrival_port(...) / port_for_landmark(landmark)    ports
//   SSflight.create_plan(vessel, destination)                       a flight plan

/datum/system/flight/proc/register_vessel(obj/effect/overmap/visitable/ship/ship)
	if(!ship || QDELETED(ship))
		return null
	var/existing_id = vessel_by_ship[REF(ship)]
	if(existing_id)
		var/datum/flight_vessel/existing = vessels?[existing_id]
		if(istype(ship, /obj/effect/overmap/visitable/ship/landable))
			var/obj/effect/overmap/visitable/ship/landable/landable = ship
			rel_set(existing, nameof(existing.shuttle), shuttles_shuttles()[landable.shuttle])
			if(existing.shuttle())
				existing.capabilities |= FLIGHT_CAP_LAND | FLIGHT_CAP_EXPEDITION
		return existing
	var/datum/flight_vessel/vessel = new
	vessel.id = make_id("vessel", ship.name)
	vessel.name = ship.name
	rel_set(vessel, nameof(vessel.ship), ship)
	vessel.capabilities = FLIGHT_CAP_STRATEGIC | FLIGHT_CAP_DOCK
	if(istype(ship, /obj/effect/overmap/visitable/ship/landable))
		var/obj/effect/overmap/visitable/ship/landable/landable = ship
		rel_set(vessel, nameof(vessel.shuttle), shuttles_shuttles()[landable.shuttle])
		vessel.capabilities |= FLIGHT_CAP_LAND | FLIGHT_CAP_EXPEDITION
	rel_add(src, nameof(vessels), vessel, vessel.id)
	var/ship_ref = REF(ship) // lookup keyed by ref string: plain data
	vessel_by_ship[ship_ref] = vessel.id
	ship.flight_vessel_id = vessel.id
	register_destination(ship)
	var/obj/effect/overmap/visitable/physical_target
	if(vessel.shuttle()?.current_location())
		physical_target = waypoint_sector(vessel.shuttle().current_location())
	var/datum/flight_destination/physical_context = destination_for_target(physical_target)
	vessel.orbit_parent_id = physical_context?.orbit_parent_id || planet_id_named("Sif") || first_planet_id()
	if(vessel.shuttle()?.current_location())
		var/datum/flight_port/current_port = port_for_landmark(vessel.shuttle().current_location())
		if(current_port)
			vessel.docked_port_id = current_port.id
			rel_set(current_port, nameof(current_port.occupied_by), vessel)
	else if(istype(ship, /obj/effect/overmap/visitable/ship/exploration_carrier))
		vessel.orbit_parent_id = planet_id_named("Sif") || first_planet_id()
		vessel.docked_port_id = null
	return vessel

/datum/system/flight/proc/vessel_for_ship(obj/effect/overmap/visitable/ship/ship)
	var/id = ship?.flight_vessel_id || vessel_by_ship[REF(ship)]
	return vessels?[id]

/datum/system/flight/proc/register_expedition(datum/expedition_site/site)
	if(!site || QDELETED(site))
		return null
	if(site.flight_destination_id && destinations?[site.flight_destination_id])
		return destinations?[site.flight_destination_id]
	var/datum/flight_destination/destination = new
	destination.id = make_id("expedition", site.name)
	destination.name = site.name
	destination.description = site.mission?.desc || "A procedurally surveyed expedition site."
	destination.kind = FLIGHT_DEST_EXPEDITION
	rel_set(destination, nameof(destination.expedition), site)
	rel_set(destination, nameof(destination.target), site.overmap_sector())
	destination.required_capabilities = FLIGHT_CAP_EXPEDITION | FLIGHT_CAP_LAND
	destination.orbit_parent_id = site.parent_destination_id || first_planet_id()
	destination.body_radius = 0.45
	destination.body_color = "#ffc45c"
	destination.surface_latitude = rand(-75, 75)
	destination.surface_longitude = rand(-180, 180)
	rel_add(src, nameof(destinations), destination, destination.id)
	if(destination.target())
		destination_by_target[REF(destination.target())] = destination.id
	site.flight_destination_id = destination.id
	return destination

/datum/system/flight/proc/unregister_destination(id)
	var/datum/flight_destination/destination = destinations?[id]
	if(!destination)
		return
	if(destination.target())
		destination_by_target -= REF(destination.target())
	own_take_member(src, nameof(destinations), id)
	spent(destination)

/datum/system/flight/proc/destination_for_target(atom/target)
	RETURN_TYPE(/datum/flight_destination)
	if(!target)
		return null
	var/id = destination_by_target[REF(target)]
	return destinations?[id]

/datum/system/flight/proc/reserve_arrival_port(datum/flight_plan/plan)
	if(!plan?.vessel?.shuttle())
		return null
	for(var/id in ports)
		var/datum/flight_port/port = ports?[id]
		if(!port.serves(plan.destination().id) || !port.can_accept(plan.vessel, plan))
			continue
		rel_set(port, nameof(port.reserved_by), plan)
		return port
	return null

/datum/system/flight/proc/port_for_landmark(obj/effect/shuttle_landmark/landmark)
	return ports?[port_by_landmark[REF(landmark)]]

/datum/system/flight/proc/create_plan(datum/flight_vessel/vessel, destination_id)
	var/datum/flight_destination/destination = destinations?[destination_id]
	if(!vessel || !destination?.is_available() || vessel.active_plan)
		return null
	if(destination.expedition())
		var/datum/expedition_site/site = destination.expedition()
		if(site.assigned_flight_vessel() && site.assigned_flight_vessel() != vessel)
			return null
		rel_set(site, nameof(site.assigned_flight_vessel), vessel)
		rel_set(site, nameof(site.assigned_shuttle), vessel.shuttle())
		rel_set(vessel, nameof(vessel.active_expedition), site)
	var/datum/flight_destination/origin = destinations?[vessel.current_destination_id()]
	var/datum/flight_plan/plan = new(vessel, origin, destination)
	rel_set(vessel, nameof(vessel.active_plan), plan) // the vessel owns its active plan; plans is the service's id lookup
	rel_add(src, nameof(plans), plan, plan.id)
	return plan
