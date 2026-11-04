/obj/effect/mine/stun
	mineitemtype = /obj/item/mine/stun

/obj/effect/mine/stun/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		M.status_at_least(STAT_STUNNED, 30)
	visible_message("\The [src.name] flashes violently before disintegrating!")
	SSmotiontracker.ping(src,100)
	consume(src)
