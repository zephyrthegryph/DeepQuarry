//////////////////////////////
// Landmarks for asteroid positioning
// Just makes the placement more safe/sane
//////////////////////////////

/obj/asteroid_spawner
	name = "asteroid spawn"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x2"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	var/tmp/datum/rogue/asteroid/myasteroid

/obj/asteroid_spawner/Initialize(mapload)
	. = ..()
	if(loc && istype(loc,/turf/space) && istype(loc.loc,/area/asteroid/rogue))
		var/area/asteroid/rogue/A = loc.loc
		A.asteroid_spawns += src

/obj/rogue_mobspawner
	name = "mob spawn"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	var/tmp/mob/mymob

/obj/rogue_mobspawner/Initialize(mapload)
	. = ..()
	if(loc && istype(loc,/turf/space) && istype(loc.loc,/area/asteroid/rogue))
		var/area/asteroid/rogue/A = loc.loc
		A.mob_spawns += src

/// Accessor for the myasteroid var.
/obj/asteroid_spawner/proc/myasteroid() as /datum/rogue/asteroid
	return myasteroid

/// Accessor for the mymob var.
/obj/rogue_mobspawner/proc/mymob() as /mob
	return mymob
