/obj/structure/stairs
	name = "Stairs"
	desc = "Stairs leading to another deck.  Not too useful if the gravity goes out."
	icon = 'icons/obj/structures/multiz.dmi'
	icon_state = "stair"
	opacity = 0
	density = FALSE
	anchored = TRUE
	unacidable = TRUE
	layer = STAIRS_LAYER

/obj/structure/stairs/Initialize(mapload)
	. = ..()
	check_integrity()

// Returns TRUE if the stairs are a complete and connected unit, FALSE if a piece is missing or obstructed
// Will attempt to reconnect broken pieces
// Parameters:
//  - B1: Loc of bottom stair
//  - B2: Loc of middle stair
//  - T1: Openspace over bottom stair
//  - T2: Loc of top stair, over middle stair
/obj/structure/stairs/proc/check_integrity(obj/structure/stairs/bottom/B = null,
										   obj/structure/stairs/middle/M = null,
										   obj/structure/stairs/top/T = null,
										   turf/simulated/open/O = null)

	// Base cases: Something is missing!
	// The parent type doesn't know enough about the positional relations to find neighbors, only evaluate if they're connected
	if(!istype(B) || !istype(M) || !istype(T) || !istype(O))
		return FALSE

	// Case 1: In working order
	if(B.top == T && M.bottom == B && T.bottom == B && \
			get_turf(M) == get_step(B, B.dir) && O == GetAbove(B) && get_turf(T) == GetAbove(M))
		return TRUE

	// Case 2: The top is linked to someone else
	if(istype(T.bottom) && T.bottom != B)
		return FALSE

	// Case 3: The bottom is linked to someone else
	if(istype(B.top) && B.top != T)
		return FALSE

	// Case 4: They're unlinked
	B.dir = get_dir(get_turf(B), get_turf(M))
	rel_set(B, nameof(B.top), T)
	rel_set(B, nameof(B.middle), M)
	T.dir	 = B.dir
	rel_set(T, nameof(T.middle), M) // pairs: also sets T.bottom, M.bottom and M.top
	M.dir	 = B.dir
	return TRUE

// Used to actually move stuff up/down stairs. Removed from Crossed for special cases
/obj/structure/stairs/proc/use_stairs(atom/movable/AM, atom/oldloc)
	return

/obj/structure/stairs/proc/use_stairs_instant(atom/movable/AM)
	return

//////////////////////////////////////////////////////////////////////
// Bottom piece that you step ontor //////////////////////////////////
//////////////////////////////////////////////////////////////////////
/obj/structure/stairs/bottom
	icon_state = "stair_l"
	var/obj/structure/stairs/top/top = null
	var/obj/structure/stairs/middle/middle = null

/obj/structure/stairs/bottom/Initialize(mapload)
	. = ..()
	if(!GetAbove(src))
		WARNING("Stair created without level above: ([loc.x], [loc.y], [loc.z])")
		return INITIALIZE_HINT_QDEL

CAPABILITIES(/obj/structure/stairs/bottom)
	links(/obj/structure/stairs/bottom::top, /obj/structure/stairs/top::bottom)
	links(/obj/structure/stairs/bottom::middle, /obj/structure/stairs/middle::bottom)

// These are necessarily fairly similar, but because the positional relations are different, we have to copy-pasta a fair bit
/obj/structure/stairs/bottom/check_integrity(obj/structure/stairs/bottom/B = null,
												obj/structure/stairs/middle/M = null,
												obj/structure/stairs/top/T = null,
												turf/simulated/open/O = null)

	// In the case where we're provided all the pieces, just try connecting them.
	// In order: all exist, they are appropriately adjacent, and they can connect
	if(istype(B) && istype(M) && istype(T) && istype(O) && \
			B.Adjacent(M) && (GetBelow(O) == get_turf(B)) && T.Adjacent(O) && \
			..())
		return TRUE

	// If we're already configured, just check those
	else if(istype(top) && istype(middle))
		O = locate_within(GetAbove(src), /turf/simulated/open)
		if(..(src, middle, top, O))
			return TRUE

	var/turf/B2 = get_step(src, src.dir)
	O = GetAbove(src)
	var/turf/T2 = GetAbove(B2)

	// T1 is the same regardless of B1's dir, so we can enforce it here
	if(!istype(O))
		return FALSE

	T = locate_on(T2, /obj/structure/stairs/top)
	M = locate_on(B2, /obj/structure/stairs/middle)

	// If you set the dir, that's the dir it *wants* to connect in. It only chooses the others if that doesn't work
	// Everything is simply linked in our original direction
	if(istype(M) && istype(T) && ..(src, M, T, O))
		return TRUE

	// Else, we have to look in other directions
	for(var/dir in GLOB.cardinal - src.dir)
		B2 = get_step(src, dir)
		T2 = GetAbove(B2)
		if(!istype(B2) || !istype(T2))
			continue

		T = locate_on(T2, /obj/structure/stairs/top)
		M = locate_on(B2, /obj/structure/stairs/middle)
		if(..(src, M, T, O))
			return TRUE

	// Out of the dir check, we have no valid neighbors, and thus are not complete.
	return FALSE

/obj/structure/stairs/bottom/Crossed(atom/movable/AM, atom/oldloc)
	if(isliving(AM))
		var/mob/living/L = AM
		if((L.ai_brain != null))
			use_stairs(AM, oldloc)
	..()

/obj/structure/stairs/bottom/use_stairs(atom/movable/AM, atom/oldloc)
	// If we're coming from the top of the stairs, don't trap us in an infinite staircase
	// Or if we fell down the openspace
	if((top in oldloc) || oldloc == GetAbove(src))
		return
	// ition Start
	if(istype(AM, /obj/effect/plant))
		return
	// ition End
	if(isobserver(AM)) // Ghosts have their own methods for going up and down
		return
	if(AM?.pulled_by_mob()) // Animating the movement of pulled things is handled when the puller goes up the stairs
		return

	if(AM.has_buckled_mobs()) // Similarly, the rider entering the turf will bring along whatever they're buckled to
		return

	var/list/atom/movable/pulling = list() // Will also include grabbed mobs
	if(isliving(AM))
		var/mob/living/L = AM

		if(LAZYLEN(L?.grabbed_by_list())) // Same as pulledby, whoever's holding you will keep you from going down stairs.
			return

		if(L?.buckled_to())
			pulling |= L?.buckled_to()

		// If the object is pulling or grabbing anything, we'll want to move those too. A grab chain may be disrupted in doing so.
		var/atom/movable/L_pulling = L?.pulling_target()
		if(L_pulling && !L_pulling.anchored)
			pulling |= L_pulling
		for(var/obj/item/grab/G in list(L.get_equipped_item(SLOT_ID_HAND_L), L.get_equipped_item(SLOT_ID_HAND_R)))
			pulling |= G?.grab_target()

	// If the stairs aren't broken, go up.
	if(check_integrity())
		AM.set_dir(src.dir)

		// Bring the pulled/grabbed object(s) along behind us
		for(var/atom/movable/P in pulling)
			P.forceMove(get_turf(src)) // They will move onto the turf but won't get past the check earlier in crossed. Aligns animation more cleanly

		// Move to Top
		AM.forceMove(get_turf(top))

		// If something is being pulled, bring it along directly to avoid the mob being torn away from it due to movement delays
		for(var/atom/movable/P in pulling)
			P.forceMove(get_turf(top)) // Just bring it along directly, no fussing with animation timing
			if(isliving(P))
				var/mob/living/L = P
				if(L.client)
					L.client.Process_Grab() // Update any miscellanous grabs, possibly break grab-chains
	return TRUE

/obj/structure/stairs/bottom/use_stairs_instant(atom/movable/AM)
	if(isobserver(AM)) // Ghosts have their own methods for going up and down
		return
	// ition Start
	if(istype(AM, /obj/effect/plant))
		return
	// ition End
	if(isliving(AM))
		var/mob/living/L = AM

		if(LAZYLEN(L?.grabbed_by_list())) // Same as pulledby, whoever's holding you will keep you from going down stairs.
			return

		if(L?.buckled_to())
			var/atom/movable/_tmp_buck_35 = L?.buckled_to()
			_tmp_buck_35.forceMove(get_turf(top))

		var/atom/movable/P = null
		var/atom/movable/L_pulling = L?.pulling_target()
		if(L_pulling && !L_pulling.anchored)
			P = L_pulling
			P.forceMove(get_turf(L))

		L.forceMove(get_turf(top))

		// If the object is pulling or grabbing anything, we'll want to move those too. A grab chain may be disrupted in doing so.
		if(P)
			P.forceMove(get_turf(top))
			L.continue_pulling(P)

		for(var/obj/item/grab/G in list(L.get_equipped_item(SLOT_ID_HAND_L), L.get_equipped_item(SLOT_ID_HAND_R)))
			var/mob/grabbed = G?.grab_target()
			grabbed.forceMove(get_turf(top))

		if(L.client)
			L.client.Process_Grab()
	else
		AM.forceMove(get_turf(top))

//////////////////////////////////////////////////////////////////////
// Middle piece that you are animated onto/off of ////////////////////
//////////////////////////////////////////////////////////////////////
/obj/structure/stairs/middle
	icon_state = "stair_u"
	opacity   = TRUE
	density   = TRUE // Too high to simply step up on

	var/obj/structure/stairs/top/top = null
	var/obj/structure/stairs/bottom/bottom = null

CAPABILITIES(/obj/structure/stairs/middle)
	links(/obj/structure/stairs/middle::top, /obj/structure/stairs/top::middle)
	climb()
	op("interaction_drag", item(/mob), gesture(GESTURE_DRAG), priority(OP_PRIORITY_PART + 1), then(PROC_REF(interaction_drag)))

/obj/structure/stairs/middle/Initialize(mapload)
	. = ..()
	if(!GetAbove(src))
		WARNING("Stair created without level above: ([loc.x], [loc.y], [loc.z])")
		return INITIALIZE_HINT_QDEL


// These are necessarily fairly similar, but because the positional relations are different, we have to copy-pasta a fair bit
/obj/structure/stairs/middle/check_integrity(obj/structure/stairs/bottom/B = null,
												obj/structure/stairs/middle/M = null,
												obj/structure/stairs/top/T = null,
												turf/simulated/open/O = null)

	// In the  case where we're provided all the pieces, just try connecting them.
	// In order: all exist, they are appropriately adjacent, and they can connect
	if(istype(B) && istype(M) && istype(T) && istype(O) && \
			B.Adjacent(M) && (GetBelow(O) == B.loc) && T.Adjacent(O) && \
			..())
		return TRUE

	else if(istype(top) && istype(bottom))
		O = locate_within(GetAbove(bottom), /turf/simulated/open)
		if(..(bottom, src, top, O))
			return TRUE

	var/turf/B1 = get_step(src, turn(src.dir, 180))
	O = GetAbove(B1)
	var/turf/T2 = GetAbove(src)

	B = locate_on(B1, /obj/structure/stairs/bottom)
	T = locate_on(T2, /obj/structure/stairs/top)

	// Top is static for Middle stair, if it's invalid we can't do much
	if(!istype(T))
		return FALSE

	// If you set the dir, that's the dir it *wants* to connect in. It only chooses the others if that doesn't work
	// Everything is simply linked in our original direction
	if(istype(B1) && istype(T2) && istype(O) && ..(B, src, T, O))
		return TRUE

	// Else, we have to look in other directions
	for(var/dir in GLOB.cardinal - src.dir)
		B1 = get_step(src, turn(dir, 180))
		O = GetAbove(B1)
		if(!istype(B1) || !istype(O))
			continue

		B = locate_on(B1, /obj/structure/stairs/bottom)
		if(..(B, src, T, O))
			return TRUE

	// The middle stair has some further special logic, in that it can be climbed, and so is technically valid if only the top exists
	// T is enforced by a prior if
	rel_set(T, nameof(T.middle), src) // pair: sets our top too
	src.dir = T.dir
	return TRUE

/// Old MouseDrop_T.
/obj/structure/stairs/middle/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	if(check_integrity())
		user.forceMove(get_turf(top)) // You can't really drag things when you have to climb up the gap in the stairs yourself
	return OP_PASS

/obj/structure/stairs/middle/Bumped(mob/user)
	if(check_integrity() && bottom && (bottom in get_turf(user))) // Bottom must be enforced because the middle stairs don't actually need the bottom
		bottom.use_stairs_instant(user)

//////////////////////////////////////////////////////////////////////
// Top piece that you step onto //////////////////////////////////////
//////////////////////////////////////////////////////////////////////
/obj/structure/stairs/top
	icon_state = "stair_l" // Darker, marginally less contrast w/ openspace
	var/obj/structure/stairs/middle/middle = null
	var/obj/structure/stairs/bottom/bottom = null

/obj/structure/stairs/top/Initialize(mapload)
	. = ..()
	if(!GetBelow(src))
		WARNING("Stair created without level below: ([loc.x], [loc.y], [loc.z])")
		return INITIALIZE_HINT_QDEL


// These are necessarily fairly similar, but because the positional relations are different, we have to copy-pasta a fair bit
/obj/structure/stairs/top/check_integrity(obj/structure/stairs/bottom/B = null,
										  obj/structure/stairs/middle/M = null,
										  obj/structure/stairs/top/T = null,
										  turf/simulated/open/O = null)

	// In the  case where we're provided all the pieces, just try connecting them.
	// In order: all exist, they are appropriately adjacent, and they can connect
	if(istype(B) && istype(M) && istype(T) && istype(O) && \
			B.Adjacent(M) && (GetBelow(O) == B.loc) && T.Adjacent(O) && \
			(. = ..()))
		return

	else if(istype(middle) && istype(bottom))
		O = locate_within(GetAbove(bottom), /turf/simulated/open)
		if(..(bottom, middle, src, O))
			return TRUE

	O = get_step(src, turn(src.dir, 180))
	var/turf/B1 = GetBelow(O)
	var/turf/B2 = GetBelow(src)

	B = locate_on(B1, /obj/structure/stairs/bottom)
	M = locate_on(B2, /obj/structure/stairs/middle)

	// Middle stair is static for Top stair, so if it's invalid we can't do much
	if(!istype(M))
		return FALSE

	// If you set the dir, that's the dir it *wants* to connect in. It only chooses the others if that doesn't work
	// Everything is simply linked in our original direction
	if(istype(B) && istype(O) && (. = ..(B, M, src, O)))
		return

	// Else, we have to look in other directions
	for(var/dir in GLOB.cardinal - src.dir)
		O = get_step(src, turn(dir, 180))
		B1 = GetBelow(O)
		if(!istype(B1) || !istype(O))
			continue

		B = locate_on(B1, /obj/structure/stairs/bottom)
		if((. = ..(B, M, src, O)))
			return

	// Out of the dir check, we have no valid neighbors, and thus are not complete. `.` was set by ..()
	return

/obj/structure/stairs/top/Crossed(atom/movable/AM, atom/oldloc)
	if(isliving(AM))
		var/mob/living/L = AM
		if((L.ai_brain != null))
			use_stairs(AM, oldloc)
	..()

/obj/structure/stairs/top/Uncrossed(atom/movable/AM)
	// Going down stairs from the topstair piece
	if(AM.dir == turn(dir, 180) && isturf(AM.loc) && check_integrity())
		use_stairs_instant(AM)
		return

/obj/structure/stairs/top/use_stairs(atom/movable/AM, atom/oldloc)
	// If we're coming from the bottom of the stairs, don't trap us in an infinite staircase
	// Or if we climb up the middle
	if((bottom in oldloc) || oldloc == GetBelow(src))
		return
	// ition Start
	if(istype(AM, /obj/effect/plant))
		return
	// ition End
	if(isobserver(AM)) // Ghosts have their own methods for going up and down
		return
	if(AM?.pulled_by_mob()) // Animating the movement of pulled things is handled when the puller goes up the stairs
		return

	if(AM.has_buckled_mobs()) // Similarly, the rider entering the turf will bring along whatever they're buckled to
		return

	var/list/atom/movable/pulling = list() // Will also include grabbed mobs
	if(isliving(AM))
		var/mob/living/L = AM

		if(LAZYLEN(L?.grabbed_by_list())) // Same as pulledby, whoever's holding you will keep you from going down stairs.
			return

		if(L?.buckled_to())
			pulling |= L?.buckled_to()

		// If the object is pulling or grabbing anything, we'll want to move those too. A grab chain may be disrupted in doing so.
		var/atom/movable/L_pulling = L?.pulling_target()
		if(L_pulling && !L_pulling.anchored)
			pulling |= L_pulling
		for(var/obj/item/grab/G in list(L.get_equipped_item(SLOT_ID_HAND_L), L.get_equipped_item(SLOT_ID_HAND_R)))
			pulling |= G?.grab_target()

	// If the stairs aren't broken, go up.
	if(check_integrity())
		AM.set_dir(turn(src.dir, 180))
		// Bring the pulled/grabbed object(s) along behind us
		for(var/atom/movable/P in pulling)
			P.forceMove(get_turf(src)) // They will move onto the turf but won't get past the check earlier in crossed. Aligns animation more cleanly

		// Move to Top
		AM.forceMove(get_turf(bottom))

		// If something is being pulled, bring it along directly to avoid the mob being torn away from it due to movement delays
		for(var/atom/movable/P in pulling)
			P.forceMove(get_turf(bottom)) // Just bring it along directly, no fussing with animation timing
			if(isliving(P))
				var/mob/living/L = P
				if(L.client)
					L.client.Process_Grab() // Update any miscellanous grabs, possibly break grab-chains
		PUBLISH_LEGACY(AM, /datum/notice/moved_down_stairs, oldloc)
	return TRUE

/obj/structure/stairs/top/use_stairs_instant(atom/movable/AM)
	if(isobserver(AM)) // Ghosts have their own methods for going up and down
		return
	// ition Start
	if(istype(AM, /obj/effect/plant))
		return
	// ition End
	if(isliving(AM))
		var/mob/living/L = AM
		if(LAZYLEN(L?.grabbed_by_list())) // Same as pulledby, whoever's holding you will keep you from going down stairs.
			return

		if(L?.buckled_to())
			var/atom/movable/_tmp_buck_36 = L?.buckled_to()
			_tmp_buck_36.forceMove(get_turf(bottom))

		var/atom/movable/P = null
		var/atom/movable/L_pulling = L?.pulling_target()
		if(L_pulling && !L_pulling.anchored)
			P = L_pulling
			P.forceMove(get_turf(L))

		L.forceMove(get_turf(bottom))

		// If the object is pulling or grabbing anything, we'll want to move those too. A grab chain may be disrupted in doing so.
		if(P)
			P.forceMove(get_turf(bottom))
			L.continue_pulling(P)

		for(var/obj/item/grab/G in list(L.get_equipped_item(SLOT_ID_HAND_L), L.get_equipped_item(SLOT_ID_HAND_R)))
			var/mob/grabbed = G?.grab_target()
			grabbed.forceMove(get_turf(bottom))

		if(L.client)
			L.client.Process_Grab()
	else
		AM.forceMove(get_turf(bottom))
	PUBLISH_LEGACY(AM, /datum/notice/moved_down_stairs, null)

// Mapping pieces, placed at the bottommost part of the stairs
/obj/structure/stairs/spawner
	name = "Stairs spawner"
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""

CAPABILITIES(/obj/structure/stairs/spawner)
	map_resolver(GLOBAL_PROC_REF(resolve_stairs_spawner))

/proc/resolve_stairs_spawner(atom/loc, path, list/varedits)
	map_resolve_later(GLOBAL_PROC_REF(stairs_spawner_build), get_turf(loc), path, varedits)
	return TRUE

/// Builds the three stair pieces from the bottommost tile `B2` in the spawner's direction.
/proc/stairs_spawner_build(turf/B2, path, list/varedits)
	var/obj/structure/stairs/spawner/P = path
	var/dir = MAP_VAR(P, varedits, dir)
	var/turf/B1 = get_step(B2, turn(dir, 180))
	var/turf/T1 = GetAbove(B1)
	var/turf/T2 = GetAbove(B2)

	if(!istype(B1) || !istype(B2))
		WARNING("Stair created at invalid loc: ([B2?.x], [B2?.y], [B2?.z])")
		return
	if(!istype(T1) || !istype(T2))
		WARNING("Stair created without level above: ([B2.x], [B2.y], [B2.z])")
		return

	// Spawn the stairs
	// Railings sold separately
	var/turf/simulated/open/O = T1
	var/obj/structure/stairs/top/T 	  = new(T2)
	var/obj/structure/stairs/middle/M = new(B2)
	var/obj/structure/stairs/bottom/B = new(B1)
	if(!isopenspace(O))
		O = new(O)

	B.dir = dir
	M.dir = dir
	T.dir = dir
	B.check_integrity(B, M, T, O)

// For ease of spawning. While you *can* spawn the base type and set its dir, this is useful for adminbus and a little bit quicker to map in
/obj/structure/stairs/spawner/north
	dir = NORTH
	bound_height = 64
	pixel_y = -32

/obj/structure/stairs/spawner/south
	dir = SOUTH
	bound_height = 64

/obj/structure/stairs/spawner/east
	dir = EAST
	bound_width = 64
	pixel_x = -32

/obj/structure/stairs/spawner/west
	dir = WEST
	bound_width = 64
