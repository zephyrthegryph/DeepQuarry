/obj/effect/mine/incendiary
	mineitemtype = /obj/item/mine/incendiary

/obj/effect/mine/incendiary/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		M.adjust_fire_stacks(5)
		M.fire_act()
	visible_message("\The [src.name] bursts into flames!")
	SSmotiontracker.ping(src,100)
	consume(src)
