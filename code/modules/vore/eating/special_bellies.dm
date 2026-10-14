// Special Vorebelly types. For general use bellies that have abnormal functionality.
// Also ones that probably shouldn't be savable.
// PS: I'm adding this file in the middle of a toilet overhaul PR.
// If that's not the definition of scope increase, I dont know what is. -Reo

/obj/belly/special //parant type for bellies you dont want to be treated like normal bellies to use
	prevent_saving = TRUE

/obj/belly/special/teleporter
	var/tmp/atom/movable/target
	var/target_turf = TRUE
	var/teleport_delay = 3 SECONDS

/obj/belly/special/teleporter/Entered(atom/movable/thing, atom/OldLoc)
	. = ..()
	if(teleport_delay <= 0) //just try to teleport immediately.
		try_tele(thing)
		return
	after(src, teleport_delay, PROC_REF(try_tele), with = list(thing))

/obj/belly/special/teleporter/periodic_step(wait)
	if(istype(target(), /atom/movable))
		return ..()
	for(var/atom/movable/AM in contents)
		try_tele(AM)
	. = ..()

/obj/belly/special/teleporter/proc/try_tele(atom/movable/thing)
	if(!thing || !istype(target(), /atom/movable))
		return
	if(isturf(target())) // if it's a turf, we dont need to do anything else, just teleport to it
		thing.forceMove(target())
	else
		thing.forceMove(target_turf ? get_turf(target()) : target() )

/// the target this refers to (a relation view: null once it is deleted).
/obj/belly/special/teleporter/proc/target() as /atom/movable
	return target
