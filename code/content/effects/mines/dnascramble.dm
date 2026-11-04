/obj/effect/mine/dnascramble
	mineitemtype = /obj/item/mine/dnascramble

/obj/effect/mine/dnascramble/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		M.add_radiation(50)
		randmutb(M)
		domutcheck(M,null)
		M.UpdateAppearance()
	visible_message("\The [src.name] flashes violently before disintegrating!")
	SSmotiontracker.ping(src,100)
	consume(src)
