// virtual disposal object
// travels through pipes in lieu of actual items
// contents will be items flushed by the disposal
// this allows the gas flushed to be tracked

/obj/structure/disposalholder
	invisibility = INVISIBILITY_ABSTRACT
	var/datum/gas_mixture/gas = null	// gas used to flush, will appear at exit point
	var/count = 2048	//*** can travel 2048 steps before going inactive (in case of loops)
	var/destinationTag = "" // changes if contains a delivery container
	var/hasmob = FALSE //If it contains a mob
	var/partialTag = "" //set by a partial tagger the first time round, then put in destinationTag if it goes through again.
	flags = REMOTEVIEW_ON_ENTER
	dir = 0

CAPABILITIES(/obj/structure/disposalholder)
	owns_one(nameof(gas), /datum/gas_mixture)

// C11: one slot, accepting anything (a holder in transit carries whatever was
// flushed into it). Legacy forceMove()s into and out of the holder (move(),
// the disposal machine's flush, pipe transit) are still accounted for by
// doMove()'s bookkeeping, so slot_contents() stays correct. Whatever is still
// riding when the holder is destroyed spills onto its turf.
/datum/om/relation/slot/disposal_holder
	holder = /obj/structure/disposalholder
	slot_id = CONTAINER_SLOT_DISPOSAL
	name = "contents"
	drop_policy = SLOT_DROP_SPILL
	exposure = SLOT_EXPOSURE_SEALED

/// TRUE while the holder is moving through pipes: move() runs every decisecond.
OM_FIELD(/obj/structure/disposalholder, active, FALSE, CHANGE_EXPLICIT)
DECLARE_REPEAT(/obj/structure/disposalholder, 1 DECISECONDS, move, "active")

/obj/structure/disposalholder/proc/init(list/flush_list, datum/gas_mixture/flush_gas)
	own_move(flush_gas, src, nameof(gas)) // transfer gas resv. into holder object (from whoever owns it now) -- let's be explicit about the data this proc consumes, please.

	//Check for any living mobs trigger hasmob.
	//hasmob effects whether the package goes to cargo or its tagged destination.
	for(var/mob/living/M in flush_list)
		if(M.stat != DEAD && !istype(M,/mob/living/silicon/robot/drone))
			hasmob = TRUE
			break

	//Checks 1 contents level deep. This means that players can be sent through disposals...
	//...but it should require a second person to open the package. (i.e. person inside a wrapped locker)
	for(var/obj/O in flush_list)
		if(!O.contents)
			continue
		for(var/mob/living/M in contents_of(O))
			if(M && M.stat != DEAD && !istype(M,/mob/living/silicon/robot/drone))
				hasmob = TRUE
				break

	// now everything inside the disposal gets put into the holder
	// note AM since can contain mobs or objs
	for(var/atom/movable/AM in flush_list)
		AM.forceMove(src)
		// Mail will use it's sorting tag if dropped into disposals
		if(!hasmob)
			if(istype(AM, /obj/structure/bigDelivery))
				var/obj/structure/bigDelivery/T = AM
				src.destinationTag = T.sortTag
			if(istype(AM, /obj/item/smallDelivery))
				var/obj/item/smallDelivery/T = AM
				src.destinationTag = T.sortTag
			if(istype(AM, /obj/item/mail))
				var/obj/item/mail/T = AM
				src.destinationTag = T.sortTag
		// Drones can mail themselves through maint.
		if(istype(AM, /mob/living/silicon/robot/drone))
			var/mob/living/silicon/robot/drone/drone = AM
			src.destinationTag = drone.mail_destination

// movement process, persists while holder is moving through pipes (declared: while active)
/obj/structure/disposalholder/proc/move()
	/* // Clonk n' bonk // Non-damaging Disposals Edit Start
	if(hasmob && prob(3))
		for(var/mob/living/H in src)
			if(!istype(H,/mob/living/silicon/robot/drone)) //Drones use the mailing code to move through the disposal system,
				H.injure(INJURY_BLUNT, 20) */ // horribly maim any living creature jumping down disposals. c'est la vie // Non-damaging Disposals Edit End

	// Transfer to next segment
	var/obj/structure/disposalpipe/last = loc
	var/obj/structure/disposalpipe/curr = last.transfer(src)
	if(!active)
		return REPEAT_STOP // Handled by a machine connected to a trunk during transfer()
	if(!curr)
		last.pipe_expel(src, get_turf(loc), dir)
		return REPEAT_STOP

	// Onto the next segment
	if(!(count--))
		set_active(FALSE)
		return REPEAT_STOP

// find the turf which should contain the next pipe
/obj/structure/disposalholder/proc/nextloc()
	return get_step(loc,dir)

// find a matching pipe on a turf
/obj/structure/disposalholder/proc/findpipe(turf/T)
	if(!T)
		return null
	var/fdir = turn(dir, 180)	// flip the movement direction
	for(var/obj/structure/disposalpipe/P in turf_contents_of_type(T, /obj/structure/disposalpipe))
		if(fdir & P.dpdir)		// find pipe direction mask that matches flipped dir
			return P
	// if no matching pipe, return null
	return null

// merge two holder objects
// used when a a holder meets a stuck holder
/obj/structure/disposalholder/proc/merge(obj/structure/disposalholder/other)
	for(var/atom/movable/AM in other)
		AM.forceMove(src)		// move everything in other holder to this one
	consumed(other, src)

/obj/structure/disposalholder/proc/settag(new_tag)
	destinationTag = new_tag

/obj/structure/disposalholder/proc/setpartialtag(new_tag)
	if(partialTag == new_tag)
		destinationTag = new_tag
		partialTag = ""
	else
		partialTag = new_tag

// Nolonger shall you be stuck forever in the tubes. ...It might just hurt a bit.
/obj/structure/disposalholder/container_resist(mob/living/escapee)
	. = ..()
	if(!istype(loc, /obj/structure/disposalpipe))
		return //Somehow we're not in a pipe, shits probably fucked
	var/obj/structure/disposalpipe/transport_cylinder = loc
	if(active)
		return
	to_chat(escapee, span_warning("You push against the thin pipe walls..."))
	play_sfx(loc, SFX_MACHINES_DOOR_AIRLOCK_CREAKING, 0.3, vary = FALSE, extrarange = 3) //yeah I know but at least it sounds like metal being bent.

	task_timed(escapee, 20 SECONDS, transport_cylinder, src, PROC_REF(burst_pipe), list(transport_cylinder))

/obj/structure/disposalholder/proc/burst_pipe(obj/structure/disposalpipe/transport_cylinder)
	if(loc != transport_cylinder || active)
		return
	for(var/mob/living/jailbird in contents)
		jailbird.injure(INJURY_BLUNT, rand(5,15), null, src)
	transport_cylinder.pipe_expel(src, get_turf(loc), NONE) //Direction: NONE, this makes the stuff spew everywhere (lol)

// called when player tries to move while in a pipe
/obj/structure/disposalholder/relaymove(mob/living/user)
	if(!isliving(user))
		return
	// If someone has sent you here to add a delay to this proc, inform them that it is a bug with /relaymove
	// it's a minor bug, but it results in the proc being called much more frequently than it should, and when the bug is fixed the delay will work properly.
	if(user.stat)
		return

	if(QDELETED(src))
		return

	for(var/mob/M in hearers(get_turf(src)))
		M.show_message("<FONT size=[max(0, 5 - get_dist(src, M))]>CLONG, clong!</FONT>", AUDIBLE_MESSAGE)
	play_sfx(src, SFX_EFFECTS_CLANG, 2, vary = FALSE, extrarange = 0)

// called to vent all gas in holder to a location
/obj/structure/disposalholder/proc/vent_gas(atom/location)
	location.assume_air(gas)  // vent all gas to turf
	return
