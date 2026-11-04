//Lasertag mines

/obj/effect/mine/lasertag
	mineitemtype = /obj/item/mine/lasertag
	var/beam_types = list(/obj/item/projectile/bullet/foam_dart_riot) // you fool, you baffoon, you used these, you absolute ignoramous, why did you not read this!
	var/spread_range = 3

/obj/effect/mine/lasertag/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = 1
	fx_sparks(src, 3)
	var/turf/O = get_turf(src)
	if(!O)
		return
	src.launch_many_projectiles(O, spread_range, beam_types)
	visible_message("\The [src.name] detonates!")
	consume(src)

/obj/effect/mine/lasertag/red
	mineitemtype = /obj/item/mine/lasertag/red
	beam_types = list(/obj/item/projectile/beam/lasertag/red)

/obj/effect/mine/lasertag/blue
	mineitemtype = /obj/item/mine/lasertag/blue
	beam_types = list(/obj/item/projectile/beam/lasertag/blue)

/obj/effect/mine/lasertag/omni
	mineitemtype = /obj/item/mine/lasertag/omni
	beam_types = list(/obj/item/projectile/beam/lasertag/omni)

/obj/effect/mine/lasertag/all
	mineitemtype = /obj/item/mine/lasertag/all
	beam_types = list(/obj/item/projectile/beam/lasertag/red,/obj/item/projectile/beam/lasertag/blue,/obj/item/projectile/beam/lasertag/omni)
