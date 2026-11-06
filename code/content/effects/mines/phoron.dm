/obj/effect/mine/phoron
	mineitemtype = /obj/item/mine/phoron

/obj/effect/mine/phoron/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	for (var/turf/simulated/floor/target in range(1,src))
		if(!target.blocks_air)
			target.assume_gas(GAS_PHORON, 30)
			target.hotspot_expose(1000, CELL_VOLUME)
	visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)
	consume(src)
