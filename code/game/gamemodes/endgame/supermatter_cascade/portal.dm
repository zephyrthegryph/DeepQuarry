/*** EXIT PORTAL ***/

/obj/singularity/narsie/large/exit
	name = "Bluespace Rift"
	desc = "NO TIME TO EXPLAIN, JUMP IN"
	icon = 'icons/obj/rift.dmi'
	icon_state = "rift"

	move_self = 0
	announce=0
	cause_hell=0

	plane = PLANE_LIGHTING_ABOVE // ITS SO BRIGHT

	consume_range = 6

/obj/singularity/narsie/large/exit/Initialize(mapload, ...)
	. = ..()
	PERIODIC_START(src, PERIODIC_SLOW)

/obj/singularity/narsie/large/exit/update_icon()
	overlays = 0

/obj/singularity/narsie/large/exit/periodic_step()
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.client)
			see_rift(M, src)
	eat()

/obj/singularity/narsie/large/exit/acquire(mob/food)
	return

/obj/singularity/narsie/large/exit/consume(const/atom/A)
	if(!(A.singuloCanEat()))
		return 0

	if (istype(A, /mob/living/))
		var/mob/living/L = A
		if(BUCKLED(L) && istype(BUCKLED(L),/obj/structure/bed/))
			var/turf/O = BUCKLED(L)
			do_teleport(O, pick(GLOB.endgame_safespawns))
			L.forceMove(O.loc)
		else
			do_teleport(L, pick(GLOB.endgame_safespawns)) //dead-on precision

	else if (istype(A, /obj/mecha/))
		do_teleport(A, pick(GLOB.endgame_safespawns)) //dead-on precision

	else if (isturf(A))
		var/turf/T = A
		var/dist = get_dist(T, src)
		if (dist <= consume_range && T.density)
			T.density = FALSE

		for (var/atom/movable/AM in T.contents)
			if (AM == src) // This is the snowflake.
				continue

			if (dist <= consume_range)
				consume(AM)
				continue

			if (dist > consume_range)
				if(!(AM.singuloCanEat()))
					continue

				if (INVISIBILITY_ABSTRACT == AM.invisibility)
					continue

				AM.singularity_pull(src, src.current_size)


/mob
	//thou shall always be able to see the rift
	var/tmp/image/riftimage = null

/proc/see_rift(mob/source, obj/singularity/narsie/large/exit/R)
	var/turf/T_mob = get_turf(source)
	if((R.z == T_mob.z) && (get_dist(R,T_mob) <= (R.consume_range+10)) && !(R in view(T_mob)))
		if(!source.riftimage)
			source.riftimage = image('icons/obj/rift.dmi',T_mob,"rift",1,1)
			source.riftimage.plane = PLANE_LIGHTING_ABOVE
			source.riftimage.mouse_opacity = 0

		var/new_x = 32 * (R.x - T_mob.x) + R.pixel_x
		var/new_y = 32 * (R.y - T_mob.y) + R.pixel_y
		source.riftimage.pixel_x = new_x
		source.riftimage.pixel_y = new_y
		source.riftimage.loc = T_mob

		source << source.riftimage
	else
		if(source.riftimage)
			qdel(source.riftimage)
