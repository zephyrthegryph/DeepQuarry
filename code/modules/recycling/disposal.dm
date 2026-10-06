// Disposal pipes
/obj/structure/disposalpipe
	icon = 'icons/obj/pipes/disposal.dmi'
	name = "disposal pipe"
	desc = "An underfloor disposal pipe."
	anchored = TRUE
	density = FALSE
	unacidable = TRUE

	level = 1			// underfloor only
	var/dpdir = 0		// bitmask of pipe directions
	dir = 0				// dir will contain dominant direction for junction pipes
	max_integrity = 10
	// Crossing this threshold leaves broken pipe segments in place (atom_break);
	// reaching 0 clears the pipe entirely (atom_destruction).
	integrity_failure = 0.1
	plane = PLATING_PLANE
	layer = DISPOSAL_LAYER	// slightly lower than wires and other pipes
	var/base_icon_state	// initial icon state on map
	var/sortType = ""
	var/subtype = 0

// new pipe, set the icon_state as on map
// ALLOW(init/INSTANCE_STATE): remembers the sprite it was placed with as its base
/obj/structure/disposalpipe/Initialize(mapload)
	. = ..()
	base_icon_state = icon_state

// returns the direction of the next pipe object, given the entrance dir
// by default, returns the bitmask of remaining directions
/obj/structure/disposalpipe/proc/nextdir(fromdir)
	return dpdir & (~turn(fromdir, 180))

// transfer the holder through this pipe segment
// overriden for special behaviour
/obj/structure/disposalpipe/proc/transfer(obj/structure/disposalholder/H)
	var/nextdir = nextdir(H.dir)
	H.set_dir(nextdir)
	var/turf/T = H.nextloc()
	var/obj/structure/disposalpipe/P = H.findpipe(T)

	if(P)
		// find other holder in next loc, if inactive merge it with current
		var/obj/structure/disposalholder/H2 = locate_within(P, /obj/structure/disposalholder)
		if(H2 && !H2.active)
			H.merge(H2)

		H.forceMove(P)
	else			// if wasn't a pipe, then set loc to turf
		H.forceMove(T)
		return null

	return P

// update the icon_state to reflect hidden status
/obj/structure/disposalpipe/proc/update()
	var/turf/T = get_turf(src)
	hide(!T.is_plating() && !istype(T,/turf/space))	// space never hides pipes

// hide called by levelupdate if turf intact status changes
// change visibility status and force update of icon
/obj/structure/disposalpipe/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE	// hide if floor is intact
	changed(src)

// update actual icon_state depending on visibility
// if invisible, append "f" to icon_state to show faded version
// this will be revealed if a T-scanner is used
// if visible, use regular icon_state
/// The look (the draw sweep: from its template).
/obj/structure/disposalpipe/draw(datum/look/look)
	..()
	look.state("[base_icon_state]")

// expel the held objects into a turf
// called when there is a break in the pipe
/obj/structure/disposalpipe/proc/pipe_expel(obj/structure/disposalholder/H, turf/T, direction)
	if(!istype(H))
		return

	if(!isturf(T)) // try very hard to ensure we have a valid turf target
		var/turf/GT = get_turf(T)
		T = (GT ? GT : get_turf(src))

	// Empty the holder if it is expelled into a dense turf.
	// Leaving it intact and sitting in a wall is stupid.
	if(T.density)
		for(var/atom/movable/AM in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
			AM.forceMove(T)
			AM.pipe_eject(0)
		spent(H)
		return

	if(!T.is_plating() && istype(T,/turf/simulated/floor)) //intact floor, pop the tile
		var/turf/simulated/floor/F = T
		F.make_plating(TRUE)

	var/turf/target
	if(direction)		// direction is specified
		if(istype(T, /turf/space)) // if ended in space, then range is unlimited
			target = get_edge_target_turf(T, direction)
		else						// otherwise limit to 10 tiles
			target = get_ranged_target_turf(T, direction, 10)

		play_sfx(src, SFX_MACHINES_HISS)
		if(H)
			for(var/atom/movable/AM in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
				if(QDELETED(AM))
					continue
				AM.forceMove(T)
				AM.pipe_eject(direction)
				AM.throw_at(target, 100, 1)

			H.vent_gas(T)
			spent(H)

	else	// no specified direction, so throw in random direction

		play_sfx(src, SFX_MACHINES_HISS)
		if(H)
			for(var/atom/movable/AM in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
				if(QDELETED(AM))
					continue
				target = get_offset_target_turf(T, rand(5)-rand(5), rand(5)-rand(5))
				AM.forceMove(T)
				AM.pipe_eject(0)
				AM.throw_at(target, 5, 1)

			H.vent_gas(T)	// all gas vent to turf
			spent(H)

	return

// call to break the pipe
// will expel any holder inside at the time
// then delete the pipe
// remains : set to leave broken pipe pieces in place
/obj/structure/disposalpipe/proc/broken(remains = 0)
	if(remains)
		for(var/D in GLOB.cardinal)
			if(D & dpdir)
				var/obj/structure/disposalpipe/broken/P = new(get_turf(src))
				P.set_dir(D)

	invisibility = INVISIBILITY_ABSTRACT	// make invisible (since we won't delete the pipe immediately)
	var/obj/structure/disposalholder/H = locate_within(src, /obj/structure/disposalholder)
	if(H)
		// holder was present
		H.set_active(FALSE)
		var/turf/T = get_turf(src)
		if(T.density)
			// broken pipe is inside a dense turf (wall)
			// this is unlikely, but just dump out everything into the turf in case

			for(var/atom/movable/AM in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
				AM.forceMove(T)
				AM.pipe_eject(0)
			spent(H)
			return

		// otherwise, do normal expel from turf
		if(H)
			pipe_expel(H, T, 0)

	om_qdel_after(src, 2) // delete pipe after 2 ticks to ensure expel proc finished

// pipe affected by explosion
// Light damage leaves broken pipe segments in place.
/obj/structure/disposalpipe/atom_break(damage_flag)
	. = ..()
	broken(1)

// Heavy damage clears the pipe entirely.
/obj/structure/disposalpipe/atom_destruction(damage_flag)
	broken(0)
	return ..()

//attack by item
//weldingtool: unfasten and convert to obj/disposalconstruct
/obj/structure/disposalpipe/welder_act(mob/user, obj/item/I)
	var/turf/T = get_turf(src)
	if(!T.is_plating())
		return ITEM_INTERACT_BLOCKING // prevent interaction with T-scanner revealed pipes
	add_fingerprint(user)
	use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 100, start_self = "You start slicing [src]....", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user), on_fail = PROC_REF(welder_act_tool_failed), fail_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposalpipe/proc/welder_act_tool_done(mob/user)
	if(!src)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You slice [src]")
	welded()

/obj/structure/disposalpipe/proc/welder_act_tool_failed(mob/user)
	to_chat(user, "You must stay still while welding the pipe.")

// called when pipe is cut with welder
/obj/structure/disposalpipe/proc/welded()

	var/obj/structure/disposalconstruct/C = new (get_turf(src))
	switch(base_icon_state)
		if("pipe-s")
			C.ptype = 0
		if("pipe-c")
			C.ptype = 1
		if("pipe-j1")
			C.ptype = 2
		if("pipe-j2")
			C.ptype = 3
		if("pipe-y")
			C.ptype = 4
		if("pipe-t")
			C.ptype = 5
		if("pipe-j1s")
			C.ptype = 9
			C.sortType = sortType
		if("pipe-j2s")
			C.ptype = 10
			C.sortType = sortType
///// Z-Level stuff
		if("pipe-u")
			C.ptype = 11
		if("pipe-d")
			C.ptype = 12
///// Z-Level stuff
		if("pipe-tagger")
			C.ptype = 13
		if("pipe-tagger-partial")
			C.ptype = 14
	C.subtype = subtype
	transfer_fingerprints_to(C)
	C.set_dir(dir)
	C.set_density(FALSE)
	C.set_anchored(TRUE)
	C.update()

	replace_with(src, C)

// pipe is deleted
// ensure if holder is present, it is expelled
// a holder travelling in it is expelled.
/obj/structure/disposalpipe/on_destroy(force)
	var/obj/structure/disposalholder/H = locate_within(src, /obj/structure/disposalholder)
	if(H)
		// holder was present
		H.set_active(FALSE)
		var/turf/T = get_turf(src)
		if(T.density)
			// deleting pipe is inside a dense turf (wall)
			// this is unlikely, but just dump out everything into the turf in case

			for(var/atom/movable/AM in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
				AM.forceMove(T)
				AM.pipe_eject(0)
			ended_with(H, src)
			..()
			return

		// otherwise, do normal expel from turf
		if(H)
			pipe_expel(H, T, 0)
	..()

/obj/structure/disposalpipe/hides_under_flooring()
	return 1

// *** TEST verb
//client/verb/dispstop()
//	for(var/obj/structure/disposalholder/H in world)
//		H.active = 0

// a straight or bent segment
/obj/structure/disposalpipe/segment
	icon_state = "pipe-s"

// ALLOW(init/INSTANCE_STATE): its pipe directions follow the way it was placed
/obj/structure/disposalpipe/segment/Initialize(mapload)
	. = ..()
	if(icon_state == "pipe-s")
		dpdir = dir | turn(dir, 180)
	else
		dpdir = dir | turn(dir, -90)

	update()

///// Z-Level stuff
/obj/structure/disposalpipe/up
	icon_state = "pipe-u"

// ALLOW(init/INSTANCE_STATE): its pipe direction follows the way it was placed
/obj/structure/disposalpipe/up/Initialize(mapload)
	. = ..()
	dpdir = dir
	update()

/obj/structure/disposalpipe/up/nextdir(fromdir)
	var/nextdir
	if(fromdir == 11)
		nextdir = dir
	else
		nextdir = 12
	return nextdir

/obj/structure/disposalpipe/up/transfer(obj/structure/disposalholder/H)
	var/nextdir = nextdir(H.dir)
	H.set_dir(nextdir)

	var/turf/T
	var/obj/structure/disposalpipe/P

	if(nextdir == 12)
		T = GetAbove(src)
		if(!T)
			H.forceMove(loc)
			return
		else
			for(var/obj/structure/disposalpipe/down/F in turf_contents_of_type(T, /obj/structure/disposalpipe/down))
				P = F

	else
		T = get_step(get_turf(src), H.dir)
		P = H.findpipe(T)

	if(P)
		// find other holder in next loc, if inactive merge it with current
		var/obj/structure/disposalholder/H2 = locate_within(P, /obj/structure/disposalholder)
		if(H2 && !H2.active)
			H.merge(H2)

		H.forceMove(P)
	else			// if wasn't a pipe, then set loc to turf
		H.forceMove(T)
		return null

	return P

/obj/structure/disposalpipe/down
	icon_state = "pipe-d"

// ALLOW(init/INSTANCE_STATE): its pipe direction follows the way it was placed
/obj/structure/disposalpipe/down/Initialize(mapload)
	. = ..()
	dpdir = dir
	update()

/obj/structure/disposalpipe/down/nextdir(fromdir)
	var/nextdir
	if(fromdir == 12)
		nextdir = dir
	else
		nextdir = 11
	return nextdir

/obj/structure/disposalpipe/down/transfer(obj/structure/disposalholder/H)
	var/nextdir = nextdir(H.dir)
	H.dir = nextdir

	var/turf/T
	var/obj/structure/disposalpipe/P

	if(nextdir == 11)
		T = GetBelow(src)
		if(!T)
			H.forceMove(get_turf(src))
			return
		else
			for(var/obj/structure/disposalpipe/up/F in turf_contents_of_type(T, /obj/structure/disposalpipe/up))
				P = F

	else
		T = get_step(get_turf(src), H.dir)
		P = H.findpipe(T)

	if(P)
		// find other holder in next loc, if inactive merge it with current
		var/obj/structure/disposalholder/H2 = locate_within(P, /obj/structure/disposalholder)
		if(H2 && !H2.active)
			H.merge(H2)

		H.forceMove(P)
	else			// if wasn't a pipe, then set loc to turf
		H.forceMove(T)
		return null

	return P

// a broken pipe
/obj/structure/disposalpipe/broken
	icon_state = "pipe-b"
	dpdir = 0		// broken pipes have dpdir=0 so they're not found as 'real' pipes
					// i.e. will be treated as an empty turf
	desc = "A broken piece of disposal pipe."

/obj/structure/disposalpipe/broken/Initialize(mapload)
	. = ..()
	update()

// called when welded
/obj/structure/disposalpipe/broken/welded()
	destroyed(src, null, "deconstructed")

// called when movable is expelled from a disposal pipe or outlet
// by default does nothing, override for special behaviour
/atom/movable/proc/pipe_eject(direction)
	return

// check if mob has client, if so restore client view on eject
/mob/pipe_eject(direction)
	reset_perspective()

/obj/effect/decal/cleanable/blood/gibs/pipe_eject(direction)
	var/list/dirs
	if(direction)
		dirs = list( direction, turn(direction, -45), turn(direction, 45))
	else
		dirs = GLOB.alldirs.Copy()
	streak(dirs)

/obj/effect/decal/cleanable/blood/gibs/robot/pipe_eject(direction)
	var/list/dirs
	if(direction)
		dirs = list( direction, turn(direction, -45), turn(direction, 45))
	else
		dirs = GLOB.alldirs.Copy()
	streak(dirs)
