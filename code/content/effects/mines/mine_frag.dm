/obj/effect/mine/frag
	mineitemtype = /obj/item/mine/frag
	var/fragment_types = list(/obj/item/projectile/bullet/pellet/fragment)
	var/num_fragments = 20  //total number of fragments produced by the grenade
	//The radius of the circle used to launch projectiles. Lower values mean less projectiles are used but if set too low gaps may appear in the spread pattern
	var/spread_range = 7

/obj/effect/mine/frag/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	var/turf/O = get_turf(src)
	if(!O)
		return
	src.fragmentate(O, num_fragments, spread_range, fragment_types) //only 20 weak fragments because you're stepping directly on it
	visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)
	consume(src)
