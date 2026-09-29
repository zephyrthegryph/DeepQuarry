/obj/effect/overmap/visitable/planet/sif/navigation
	name = "Sif"
	desc = "The frozen garden world at the heart of inhabited Vir space."
	surface_color = "#477761"
	water_color = "#315f82"
	icecaps = "ice"

/obj/effect/overmap/visitable/ship/exploration_carrier
	name = "Exploration Carrier"
	desc = "Southern Cross expedition carrier and mobile hangar complex."
	vessel_mass = 250000
	vessel_size = SHIP_SIZE_LARGE

/// Physical station berth used by carrier-based expedition craft.
/obj/effect/shuttle_landmark/southern_cross/expedition_station
	name = "Southern Cross Hangar Three"
	landmark_tag = "hangar_3"
	base_area = /area/hangar/three
	base_turf = /turf/simulated/floor/reinforced
	use_docking_codes = FALSE
	var/list/accepted_shuttles

/obj/effect/shuttle_landmark/southern_cross/expedition_station/proc/accepts_shuttle(datum/shuttle/shuttle)
	return !LAZYLEN(accepted_shuttles) || (shuttle?.name in accepted_shuttles)

/obj/effect/shuttle_landmark/southern_cross/expedition_station/general
	landmark_tag = "hangar_3_expedition"
	accepted_shuttles = list("Stargazer", "Baby_mammoth", "Ursula", "Needle")

/obj/effect/shuttle_landmark/southern_cross/expedition_station/echidna
	name = "Southern Cross Hangar Three - Echidna alignment"
	landmark_tag = "hangar_3_echidna"
	accepted_shuttles = list("Echidna")

/datum/flight_destination
	var/id
	var/name = "Unknown Destination"
	var/description = "No navigational data is available."
	var/kind = FLIGHT_DEST_ORBIT
	/// Celestial body whose transform this destination inherits.
	var/orbit_parent_id
	var/x = 0
	var/y = 0
	var/orbit_radius = 0
	var/orbit_period = 0
	var/orbit_phase = 0
	var/orbit_inclination = 0
	var/body_radius = 1
	var/body_color = "#93a9c7"
	var/surface_latitude
	var/surface_longitude
	var/required_capabilities = 0
	var/tmp/atom/target
	var/tmp/datum/expedition_site/expedition
	var/discovered = TRUE
	var/list/active_plans

/datum/flight_destination/proc/is_available()
	if(kind == FLIGHT_DEST_SYSTEM)
		return FALSE
	if(expedition())
		return !QDELETED(expedition()) && expedition().status != EXP_STATUS_EXPIRED
	return target() && !QDELETED(target())

/datum/flight_vessel
	var/id
	var/name = "Unregistered Vessel"
	var/capabilities = 0
	var/tmp/obj/effect/overmap/visitable/ship/ship
	var/tmp/datum/shuttle/autodock/overmap/shuttle
	var/datum/flight_plan/active_plan
	var/tmp/datum/expedition_site/active_expedition
	/// Authoritative celestial context; replaces hidden overmap tile coordinates.
	var/orbit_parent_id
	/// Reserved port occupied by the vessel, if physically docked.
	var/docked_port_id


/datum/flight_vessel/proc/has_capabilities(required)
	return (capabilities & required) == required

/datum/flight_vessel/proc/current_destination_id()
	if(docked_port_id)
		var/datum/flight_port/port = GLOB.flight_service?.ports[docked_port_id]
		if(port?.host_destination_id)
			return port.host_destination_id
	return orbit_parent_id

/datum/flight_port
	var/id
	var/name = "Unnamed port"
	/// Destination which owns this physical port.
	var/host_destination_id
	/// Logical destinations whose routes may terminate at this port. The physical
	/// host remains authoritative for rendering and occupancy.
	var/list/serves_destination_ids
	var/tmp/obj/effect/shuttle_landmark/landmark
	var/tmp/datum/flight_vessel/occupied_by
	var/tmp/datum/flight_plan/reserved_by
	/// Ports in the same physical bay exclude one another even when their alignment landmarks differ.
	var/berth_group

/datum/flight_port/proc/serves(destination_id)
	return host_destination_id == destination_id || (destination_id in serves_destination_ids)

/datum/flight_port/proc/can_accept(datum/flight_vessel/vessel, datum/flight_plan/requesting_plan)
	if(!vessel?.shuttle() || !landmark() || QDELETED(landmark()) || !landmark().is_valid(vessel.shuttle()))
		return FALSE
	if(istype(landmark(), /obj/effect/shuttle_landmark/southern_cross/expedition_station))
		var/obj/effect/shuttle_landmark/southern_cross/expedition_station/station_berth = landmark()
		if(!station_berth.accepts_shuttle(vessel.shuttle()))
			return FALSE
	if(berth_group)
		for(var/id in GLOB.flight_service.ports)
			var/datum/flight_port/sibling = GLOB.flight_service.ports[id]
			if(sibling != src && sibling.berth_group == berth_group && (sibling.occupied_by() || (sibling.reserved_by() && sibling.reserved_by() != requesting_plan)))
				return FALSE
	if(occupied_by() && occupied_by() != vessel)
		return FALSE
	return !reserved_by() || reserved_by() == requesting_plan

/datum/flight_plan
	var/id
	var/datum/flight_vessel/vessel
	var/tmp/datum/flight_destination/origin
	var/tmp/datum/flight_destination/destination
	var/tmp/datum/flight_port/arrival_port
	var/state = FLIGHT_PLAN_DRAFT
	var/failure_reason
	var/created_at
	var/departure_at
	var/arrival_at
	var/estimated_arrival_at
	var/departure_deadline
	var/terminal_cleanup_at
	var/generation_state = FLIGHT_GENERATION_NONE
	var/generation_progress = 0
	var/generation_stage = "Not required"
	var/cancel_requested = FALSE

/datum/flight_plan/New(datum/flight_vessel/new_vessel, datum/flight_destination/new_origin, datum/flight_destination/new_destination)
	..()
	rel_set(src, "vessel", new_vessel)
	rel_set(src, "origin", new_origin)
	rel_set(src, "destination", new_destination)
	LAZYADD(destination().active_plans, src)
	created_at = world.time
	id = "flight-[REF(src)]"
	if(destination()?.expedition() && destination().expedition().z_level <= 0)
		generation_state = FLIGHT_GENERATION_QUEUED
		generation_stage = "Awaiting departure"

// its leases are released.
/datum/flight_plan/on_destroy(force)
	release_leases(state != FLIGHT_PLAN_ARRIVED)
	..()

/datum/flight_plan/proc/release_leases(release_assignment = FALSE)
	if(destination())
		LAZYREMOVE(destination().active_plans, src)
	if(om_handle_is(arrival_port()?.reserved_by, src))
		rel_clear(arrival_port(), "reserved_by")
	if(release_assignment && destination()?.expedition()?.assigned_flight_vessel() == vessel)
		rel_clear(destination().expedition(), "assigned_flight_vessel")
		rel_clear(destination().expedition(), "assigned_shuttle")
		if(vessel?.active_expedition() == destination().expedition())
			rel_clear(vessel, "active_expedition")

/datum/flight_plan/proc/state_name()
	switch(state)
		if(FLIGHT_PLAN_DRAFT) return "Flight plan ready"
		if(FLIGHT_PLAN_PREPARING) return "Preparing"
		if(FLIGHT_PLAN_UNDOCKING) return "Undocking"
		if(FLIGHT_PLAN_TRANSIT) return "In transit"
		if(FLIGHT_PLAN_HOLDING) return "Holding for destination"
		if(FLIGHT_PLAN_APPROACH) return "Approach"
		if(FLIGHT_PLAN_ARRIVING) return "Landing"
		if(FLIGHT_PLAN_ARRIVED) return "Arrived"
		if(FLIGHT_PLAN_ABORTING) return "Aborting"
		if(FLIGHT_PLAN_FAILED) return "Failed"
	return "Unknown"

/datum/flight_plan/proc/start()
	if(state != FLIGHT_PLAN_DRAFT || !vessel || !destination()?.is_available())
		return FALSE
	if(!vessel.has_capabilities(destination().required_capabilities))
		fail("Vessel lacks the capabilities required for this destination.")
		return FALSE
	if(destination().kind == FLIGHT_DEST_STATION)
		rel_set(src, "arrival_port", GLOB.flight_service.reserve_arrival_port(src))
		if(!arrival_port())
			fail("No compatible station berth is available.")
			return FALSE
	if(destination().kind == FLIGHT_DEST_VESSEL)
		rel_set(src, "arrival_port", GLOB.flight_service.reserve_arrival_port(src))
		if(!arrival_port())
			fail("No compatible arrival port is available.")
			return FALSE
	state = FLIGHT_PLAN_PREPARING
	estimated_arrival_at = world.time + FLIGHT_DEFAULT_TRANSIT_TIME
	if(generation_state == FLIGHT_GENERATION_QUEUED)
		generation_state = FLIGHT_GENERATION_RUNNING
		generation_stage = "Reserving destination"
	log_world("Flight plan [id] engaged: [vessel.name] from [origin()?.name || "local orbit"] to [destination().name].")
	return TRUE

/datum/flight_plan/proc/fail(reason)
	if(state == FLIGHT_PLAN_FAILED || state == FLIGHT_PLAN_ARRIVED)
		return
	failure_reason = reason
	state = FLIGHT_PLAN_FAILED
	release_leases(TRUE)
	terminal_cleanup_at = world.time + 10 SECONDS
	log_world("Flight plan [id] for [vessel?.name || "unknown vessel"] failed: [reason]")

/datum/flight_plan/proc/request_abort()
	if(state == FLIGHT_PLAN_ARRIVED || state == FLIGHT_PLAN_ABORTING)
		return FALSE
	cancel_requested = TRUE
	return TRUE

/// LC-refs: the landmark this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_port/proc/landmark() as /obj/effect/shuttle_landmark
	return landmark

/// LC-refs: the origin this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_plan/proc/origin() as /datum/flight_destination
	return origin

/// LC-refs: the ship this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_vessel/proc/ship() as /obj/effect/overmap/visitable/ship
	return ship

/// LC-refs: the occupied_by this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_port/proc/occupied_by() as /datum/flight_vessel
	return occupied_by

/// LC-refs: the reserved_by this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_port/proc/reserved_by() as /datum/flight_plan
	return reserved_by

/// LC-refs: the expedition this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_destination/proc/expedition() as /datum/expedition_site
	return expedition

/// LC-refs: the destination this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_plan/proc/destination() as /datum/flight_destination
	return destination

/// LC-refs: the arrival_port this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_plan/proc/arrival_port() as /datum/flight_port
	return arrival_port

/// LC-refs: the shuttle this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_vessel/proc/shuttle() as /datum/shuttle/autodock/overmap
	return shuttle

/// LC-refs: the target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_destination/proc/target() as /atom
	return target

/// LC-refs: the active_expedition this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/flight_vessel/proc/active_expedition() as /datum/expedition_site
	return active_expedition

