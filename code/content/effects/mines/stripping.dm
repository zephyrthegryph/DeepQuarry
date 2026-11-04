/obj/effect/mine/stripping
	mineitemtype = /obj/item/mine/stripping

/obj/effect/mine/stripping/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		for(var/obj/item/content_item in contents_of(M))
			M.drop_from_inventory(content_item)
	visible_message("\The [src.name] explodes, stripping [M]!")
	SSmotiontracker.ping(src,100)
	consume(src)
