/obj/effect/mine/gadget
	mineitemtype = /obj/item/mine/gadget

/obj/effect/mine/gadget/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)

	if(trap)
		trigger_trap(M)
		visible_message("\The [src.name] flashes as it is triggered!")

	else
		explosion(loc, 0, 0, 2, 2)
		visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)

	consume(src)
