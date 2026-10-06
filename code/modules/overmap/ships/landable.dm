// These come with shuttle functionality. Need to be assigned a (unique) shuttle datum name.
// Mapping location doesn't matter, so long as on a map loaded at the same time as the shuttle areas.
// Multiz shuttles currently not supported. Non-autodock shuttles currently not supported.

/obj/effect/overmap/visitable/ship/landable
	var/shuttle                                         // Name of associated shuttle. Must be autodock.
	var/obj/effect/shuttle_landmark/ship/landmark       // Record our open space landmark for easy reference.
	var/multiz = 0										// Index of multi-z levels, starts at 0
	var/status = SHIP_STATUS_LANDED
	icon_state = "shuttle_nosprite"

CAPABILITIES(/obj/effect/overmap/visitable/ship/landable)
	owns_one(nameof(landmark), /obj/effect/shuttle_landmark/ship)

/obj/effect/overmap/visitable/ship/landable/can_burn()
	if(status != SHIP_STATUS_OVERMAP)
		return 0
	return ..()

/obj/effect/overmap/visitable/ship/landable/burn()
	if(status != SHIP_STATUS_OVERMAP)
		return 0
	return ..()

/obj/effect/overmap/visitable/ship/landable/check_ownership(obj/object)
	var/datum/shuttle/shuttle_datum = SSshuttles.shuttles[shuttle]
	if(!shuttle_datum)
		return
	var/list/areas = shuttle_datum.find_childfree_areas()
	if(get_area(object) in areas)
		return 1

// We autobuild our z levels.
/obj/effect/overmap/visitable/ship/landable/find_z_levels()
	rel_set(src, nameof(landmark), new /obj/effect/shuttle_landmark/ship(null, shuttle)) // Create in nullspace since we lazy-create overmap z
	rel_set(landmark, nameof(landmark.ship), src)
	add_landmark(landmark, shuttle)

/obj/effect/overmap/visitable/ship/landable/proc/setup_overmap_location()
	if(LAZYLEN(map_z))
		return // We're already set up!
	for(var/i = 0 to multiz)
		world.increment_max_z()
		map_z += world.maxz

	var/turf/center_loc = locate(round(world.maxx/2), round(world.maxy/2), world.maxz)
	landmark.forceMove(center_loc)

	var/visitor_dir = fore_dir
	for(var/landmark_name in list("FORE", "PORT", "AFT", "STARBOARD"))
		var/turf/visitor_turf = get_ranged_target_turf(center_loc, visitor_dir, round(min(world.maxx/4, world.maxy/4)))
		var/obj/effect/shuttle_landmark/visiting_shuttle/visitor_landmark = new (visitor_turf, landmark, landmark_name)
		add_landmark(visitor_landmark)
		visitor_dir = turn(visitor_dir, 90)

	if(multiz)
		new /obj/effect/landmark/map_data(center_loc, (multiz + 1))
	register_z_levels()
	testing("Setup overmap location for \"[name]\" containing Z [english_list(map_z)]")

/obj/effect/overmap/visitable/ship/landable/get_areas()
	var/datum/shuttle/shuttle_datum = SSshuttles.shuttles[shuttle]
	if(!shuttle_datum)
		return list()
	return shuttle_datum.find_childfree_areas()

/obj/effect/overmap/visitable/ship/landable/populate_sector_objects()
	..()
	var/datum/shuttle/shuttle_datum = SSshuttles.shuttles[shuttle]
	if(istype(shuttle_datum,/datum/shuttle/autodock/overmap))
		var/datum/shuttle/autodock/overmap/oms = shuttle_datum
		rel_set(oms, nameof(oms.myship), src)
	observe(shuttle_datum, /datum/notice/observer_shuttle_pre_move, src, then(PROC_REF(pre_shuttle_jump)))
	observe(shuttle_datum, /datum/notice/observer_shuttle_moved, src, then(PROC_REF(on_shuttle_jump)))
	on_landing(landmark, shuttle_datum.current_location()) // We "land" at round start to properly place ourselves on the overmap.

//
// Center Landmark
//

/obj/effect/shuttle_landmark/ship
	name = "Open Space"
	landmark_tag = "ship"
	flags = SLANDMARK_FLAG_ZERO_G // *Not* AUTOSET, these must be world.turf and world.area for lazy loading to work.
	var/shuttle_name
	/// Relation list: the visitor landmarks where a shuttle is stationed now (it grapples us).
	var/list/obj/effect/shuttle_landmark/visiting_shuttle/visitors
	/// Relation view: the landable ship that made (and owns) this landmark.
	var/tmp/obj/effect/overmap/visitable/ship/landable/ship

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The landmark is tagged for its ship's shuttle.
/obj/effect/shuttle_landmark/ship/proc/tag_for_shuttle(for_shuttle)
	landmark_tag += "_[for_shuttle]"
	base_turf = world.turf

/obj/effect/shuttle_landmark/ship/is_valid(datum/shuttle/shuttle)
	return (isnull(loc) || ..()) // If it doesn't exist yet, its clear

/obj/effect/shuttle_landmark/ship/create_warning_effect(datum/shuttle/shuttle)
	if(isnull(loc))
		return
	..()

/obj/effect/shuttle_landmark/ship/cannot_depart(datum/shuttle/shuttle)
	if(LAZYLEN(visitors))
		return "Grappled by other shuttle; cannot manouver."

//
// Visitor Landmark
//

/obj/effect/shuttle_landmark/visiting_shuttle
	flags = SLANDMARK_FLAG_AUTOSET | SLANDMARK_FLAG_ZERO_G
	var/obj/effect/shuttle_landmark/ship/core_landmark

CAPABILITIES(/obj/effect/shuttle_landmark/visiting_shuttle)
	param(nameof(core_landmark), pos = 1)
	param(nameof(name), pos = 2, apply = PROC_REF(tag_for_master))
	lives_while(nameof(core_landmark))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The landmark is tagged for its master's shuttle.
/obj/effect/shuttle_landmark/visiting_shuttle/proc/tag_for_master(_name)
	landmark_tag = core_landmark.shuttle_name + name

// core_landmark is a one-sided view; visitors lists only the landmarks with a shuttle stationed
// (not a pair: a visitor landmark exists long before anything docks there).

/obj/effect/shuttle_landmark/visiting_shuttle/is_valid(datum/shuttle/shuttle)
	. = ..()
	if(!.)
		return
	var/datum/shuttle/boss_shuttle = SSshuttles.shuttles[core_landmark.shuttle_name]
	if(boss_shuttle.current_location() != core_landmark)
		return FALSE // Only available when our governing shuttle is in space.
	if(shuttle == boss_shuttle) // Boss shuttle only lands on main landmark
		return FALSE

/obj/effect/shuttle_landmark/visiting_shuttle/shuttle_arrived(datum/shuttle/shuttle)
	rel_add(core_landmark, nameof(core_landmark.visitors), src)
	observe(shuttle, /datum/notice/observer_shuttle_moved, src, then(PROC_REF(shuttle_left)))

/obj/effect/shuttle_landmark/visiting_shuttle/proc/shuttle_left(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/shuttle/shuttle = A.target
	var/datum/notice/observer_shuttle_moved/event = A
	if(event.old_location == src)
		unobserve(shuttle, /datum/notice/observer_shuttle_moved, src)
		if(core_landmark)
			rel_remove(core_landmark, nameof(core_landmark.visitors), src)

//
// More ship procs
//

/obj/effect/overmap/visitable/ship/landable/proc/pre_shuttle_jump(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/shuttle/given_shuttle = A.target
	var/datum/notice/observer_shuttle_pre_move/event = A
	var/obj/effect/shuttle_landmark/into = event.destination
	if(given_shuttle != SSshuttles.shuttles[shuttle])
		return
	if(into == landmark)
		setup_overmap_location() // They're coming boys, better actually exist!
		unobserve(SSshuttles.shuttles[shuttle], /datum/notice/observer_shuttle_pre_move, src)

/obj/effect/overmap/visitable/ship/landable/proc/on_shuttle_jump(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/shuttle/given_shuttle = A.target
	var/datum/notice/observer_shuttle_moved/event = A
	var/obj/effect/shuttle_landmark/from = event.old_location
	var/obj/effect/shuttle_landmark/into = event.destination
	if(given_shuttle != SSshuttles.shuttles[shuttle])
		return
	var/datum/shuttle/autodock/auto = given_shuttle
	if(into == auto.landmark_transition())
		status = SHIP_STATUS_TRANSIT
		on_takeoff(from, into)
		return
	if(into == landmark)
		status = SHIP_STATUS_OVERMAP
		on_takeoff(from, into)
		return
	status = SHIP_STATUS_LANDED
	on_landing(from, into)

/obj/effect/overmap/visitable/ship/landable/proc/on_landing(obj/effect/shuttle_landmark/from, obj/effect/shuttle_landmark/into)
	var/obj/effect/overmap/visitable/target = get_overmap_sector(get_z(into))
	var/datum/shuttle/shuttle_datum = SSshuttles.shuttles[shuttle]
	if(into.landmark_tag == shuttle_datum.motherdock) // If our motherdock is a landable ship, it won't be found properly here so we need to find it manually.
		for(var/obj/effect/overmap/visitable/ship/landable/landable in SSshuttles.ships)
			if(landable.shuttle == shuttle_datum.mothershuttle)
				target = landable
				break
	if(!target || target == src)
		return
	var/datum/flight_vessel/vessel = SSflight?.vessel_for_ship(src)
	var/datum/flight_destination/destination = SSflight?.destination_for_target(target)
	if(vessel && destination)
		var/datum/flight_port/port = SSflight.port_for_landmark(into)
		if(vessel.docked_port_id && vessel.docked_port_id != port?.id)
			var/datum/flight_port/old_port = SSflight.ports[vessel.docked_port_id]
			if(old_port?.occupied_by() == vessel)
				rel_clear(old_port, nameof(old_port.occupied_by))
		vessel.docked_port_id = port?.id
		if(port)
			rel_set(port, nameof(port.occupied_by), vessel)
		// A delegated port inherits the physical host's celestial context, while
		// the active flight plan retains the logical route destination.
		var/datum/flight_destination/physical_host = SSflight.destinations[port?.host_destination_id]
		vessel.orbit_parent_id = physical_host?.orbit_parent_id || (destination.kind == FLIGHT_DEST_SURFACE ? destination.id : destination.orbit_parent_id)

/obj/effect/overmap/visitable/ship/landable/proc/on_takeoff(obj/effect/shuttle_landmark/from, obj/effect/shuttle_landmark/into)
	var/datum/flight_vessel/vessel = SSflight?.vessel_for_ship(src)
	if(vessel)
		var/datum/flight_port/port = SSflight.ports[vessel.docked_port_id]
		if(port?.occupied_by() == vessel)
			rel_clear(port, nameof(port.occupied_by))
		vessel.docked_port_id = null

/obj/effect/overmap/visitable/ship/landable/get_landed_info()
	switch(status)
		if(SHIP_STATUS_LANDED)
			var/datum/flight_vessel/vessel = SSflight?.vessel_for_ship(src)
			var/datum/flight_port/port = SSflight?.ports[vessel?.docked_port_id]
			var/datum/flight_destination/location = SSflight?.destinations[port?.host_destination_id]
			return location ? "Docked at [location.name], [port.name]." : "Landed at an unregistered port."
		if(SHIP_STATUS_TRANSIT)
			return "In local transfer."
		if(SHIP_STATUS_OVERMAP)
			var/datum/flight_vessel/vessel = SSflight?.vessel_for_ship(src)
			var/datum/flight_destination/orbit = SSflight?.destinations[vessel?.orbit_parent_id]
			return "In orbit of [orbit?.name || "an unregistered body"]."


/// Owned-child release: the ship's open-space landmark leaves our waypoint lists with it.
/obj/effect/overmap/visitable/ship/landable/on_owned_release(var_name, datum/child)
	if(var_name == "landmark")
		remove_landmark(child, shuttle)
	return ..()

CAPABILITIES(/obj/effect/shuttle_landmark/ship)
	ref_many(nameof(visitors))
	param(nameof(shuttle_name), pos = 1, apply = PROC_REF(tag_for_shuttle))
