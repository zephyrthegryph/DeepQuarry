/obj/effect/mine/kick
	mineitemtype = /obj/item/mine/kick

/obj/effect/mine/kick/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M, /obj/mecha))
		var/obj/mecha/E = M
		M = E?.slot_item(MECHA_SLOT_PILOT)
	if(istype(M))
		destroyed(M.client, M)
	consume(src)
