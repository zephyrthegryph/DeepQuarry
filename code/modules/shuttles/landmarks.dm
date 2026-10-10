//making this separate from /obj/effect/landmark until that mess can be dealt with
/obj/effect/shuttle_landmark
	name = "Nav Point"
	icon = 'icons/effects/effects.dmi'
	icon_state = "energynet"
	anchored = TRUE
	unacidable = TRUE
	simulated = FALSE
	invisibility = INVISIBILITY_ABSTRACT
	flags = SLANDMARK_FLAG_AUTOSET // We generally want to use current area/turf as base.

	//ID of the landmark
	var/landmark_tag
	//ID of the controller on the dock side (intialize to id_tag, becomes reference)
	var/tmp/datum/embedded_program/docking/docking_controller
	var/docking_controller_tag	// the tag it starts as; resolved into docking_controller at init
	//Map of shuttle names to ID of controller used for this landmark for shuttles with multiple ones.
	var/list/special_dock_targets

	//When the shuttle leaves this landmark, it will leave behind the base area
	//also used to determine if the shuttle can arrive here without obstruction
	var/base_area	// the area type (or area) configured; Initialize() resolves it into landing_area()
	/// The resolved area (a plain area var, set at Initialize()).
	var/tmp/area/landing_area
	//Will also leave this type of turf behind if set.
	var/base_turf
	//Name of the shuttle, null for generic waypoint
	var/shuttle_restricted
	//does it use docking codes?
	var/use_docking_codes = TRUE

/obj/effect/shuttle_landmark/Initialize(mapload)
	. = ..()

	// Even if this flag is set, hardcoded values take precedence.
	if(flags & SLANDMARK_FLAG_AUTOSET)
		if(ispath(base_area))
			var/area/A = locate(base_area)
			if(!istype(A))
				CRASH("Shuttle landmark \"[landmark_tag]\" couldn't locate area [base_area].")
			landing_area = A
		else
			landing_area = get_area(src)
		var/turf/T = get_turf(src)
		if(T && !base_turf)
			base_turf = T.type
	else
		landing_area = isarea(base_area) ? base_area : locate(base_area || world.area)
	SSshuttles.register_landmark(landmark_tag, src)

CAPABILITIES(/obj/effect/shuttle_landmark)
	after_init(0, then(PROC_REF(find_docking_controller)))

/// Finds the docking controller its tag names, once the map has made it.
/obj/effect/shuttle_landmark/proc/find_docking_controller(datum/act/timer/A)
	if(!docking_controller_tag)
		return
	var/docking_tag = docking_controller_tag
	rel_set(src, nameof(docking_controller), SSshuttles.docking_registry[docking_tag])
	if(!istype(docking_controller(), /datum/embedded_program/docking))
		log_mapping("Could not find docking controller for shuttle waypoint '[name]', docking tag was '[docking_tag]'.")
	// No QDELETING registration: docking_controller is a relation view, cleared when the controller dies.
	if(using_map.use_overmap)
		var/obj/effect/overmap/visitable/location = get_overmap_sector(z)
		if(location && location.docking_codes && use_docking_codes)
			docking_controller().docking_codes = location.docking_codes

/obj/effect/shuttle_landmark/forceMove(atom/destination, direction, movetime)
	var/obj/effect/overmap/visitable/map_origin = get_overmap_sector(z)
	. = ..()
	var/obj/effect/overmap/visitable/map_destination = get_overmap_sector(z)
	if(map_origin != map_destination)
		if(map_origin)
			map_origin.remove_landmark(src, shuttle_restricted)
		if(map_destination)
			map_destination.add_landmark(src, shuttle_restricted)

//Called when the landmark is added to an overmap sector.
/obj/effect/shuttle_landmark/proc/sector_set(obj/effect/overmap/visitable/O, shuttle_name)
	shuttle_restricted = shuttle_name

/obj/effect/shuttle_landmark/proc/is_valid(datum/shuttle/shuttle)
	if(shuttle.current_location() == src)
		return FALSE
	for(var/area/A in shuttle.shuttle_area)
		var/list/translation = get_turf_translation(get_turf(shuttle.current_location()), get_turf(src), A.contents)
		if(check_collision(landing_area(), list_values(translation)))
			return FALSE
	var/conn = GetConnectedZlevels(z)
	for(var/w in (z - shuttle.multiz) to z)
		if(!(w in conn))
			return FALSE
	return TRUE

// This creates a graphical warning to where the shuttle is about to land in approximately five seconds.
/obj/effect/shuttle_landmark/proc/create_warning_effect(datum/shuttle/shuttle)
	if(shuttle.current_location() == src)
		return // TOO LATE!
	for(var/area/A in shuttle.shuttle_area)
		var/list/translation = get_turf_translation(get_turf(shuttle.current_location()), get_turf(src), A.contents)
		for(var/T in list_values(translation))
			new /obj/effect/temporary_effect/shuttle_landing(T) // It'll delete itself when needed.
	return

// Should return a readable description of why not if it can't depart.
/obj/effect/shuttle_landmark/proc/cannot_depart(datum/shuttle/shuttle)
	return FALSE

/obj/effect/shuttle_landmark/proc/shuttle_departed(datum/shuttle/shuttle)
	return

/obj/effect/shuttle_landmark/proc/shuttle_arrived(datum/shuttle/shuttle)
	return

/proc/check_collision(area/target_area, list/target_turfs)
	for(var/target_turf in target_turfs)
		var/turf/target = target_turf
		if(!target)
			return TRUE //collides with edge of map
		if(target.loc != target_area)
			return TRUE //collides with another area
		if(target.density)
			return TRUE //dense turf
	return FALSE

//
//Self-naming/numbering ones.
//
/obj/effect/shuttle_landmark/automatic
	name = "Navpoint"
	landmark_tag = "navpoint"
	flags = SLANDMARK_FLAG_AUTOSET
	var/original_name = null // Save our mapped-in name so we can rebuild our name when moving sectors.

// ALLOW(init/INSTANCE_STATE): tags itself with its coordinates and a random id
/obj/effect/shuttle_landmark/automatic/Initialize(mapload)
	original_name = name
	landmark_tag += "-[x]-[y]-[z]-[random_id("landmarks",1,9999)]"
	return ..()

/obj/effect/shuttle_landmark/automatic/sector_set(obj/effect/overmap/visitable/O)
	..()
	name = ("[O.name] - [original_name] ([x],[y])")

//Subtype that calls explosion on init to clear space for shuttles
/obj/effect/shuttle_landmark/automatic/clearing
	var/radius = 10

/// A clearing landmark also clears the dense turfs around it.
/obj/effect/shuttle_landmark/automatic/clearing/find_docking_controller(datum/act/timer/A)
	..()
	for(var/turf/T in range(radius, src))
		if(T.density)
			T.ChangeTurf(get_base_turf_by_area(T))

//
// Bluespace flare landmark beacon
//
/obj/item/spaceflare
	name = "bluespace flare"
	desc = "Burst transmitter used to broadcast all needed information for shuttle navigation systems. Has a flare attached for marking the spot where you probably shouldn't be standing."
	icon = 'icons/obj/device.dmi'
	icon_state = "bluflare"
	light_color = "#3728ff"
	var/active
TRACKED(/obj/item/spaceflare, active)

CAPABILITIES(/obj/item/spaceflare)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/spaceflare/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!active)
		act_message(user, src, others = span_notice("%U% pulls the cord, activating %T%."))
		activate()
	return TRUE

/obj/item/spaceflare/proc/activate()
	if(active)
		return
	var/turf/T = get_turf(src)
	var/mob/M = loc
	if(istype(M) && !M.unEquip(src, T))
		return

	set_active(1)
	set_anchored(TRUE)

	var/obj/effect/shuttle_landmark/automatic/mark = new(T)
	mark.name = ("Beacon signal ([T.x],[T.y])")
	T.hotspot_expose(1500, 5)

/obj/item/spaceflare/draw(datum/look/look)
	..()
	if(active)
		look.state("bluflare_on")
		look.light(0.3, 0.1, 6)

/// Accessor for the docking_controller var.
/obj/effect/shuttle_landmark/proc/docking_controller() as /datum/embedded_program/docking
	return docking_controller

/// The area this landmark leaves behind when a shuttle departs (resolved from base_area at Initialize()).
/obj/effect/shuttle_landmark/proc/landing_area() as /area
	return landing_area
