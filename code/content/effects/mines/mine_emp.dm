/obj/effect/mine/emp
	mineitemtype = /obj/item/mine/emp

/obj/effect/mine/emp/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	visible_message("\The [src.name] flashes violently before disintegrating!")
	SSmotiontracker.ping(src,100)
	empulse(loc, 2, 4, 7, 10, 1) // As strong as an EMP grenade
	consume(src)

/obj/effect/mine/emp/camo
	camo_net = TRUE
