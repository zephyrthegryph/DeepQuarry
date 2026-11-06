/obj/effect/mine/n2o
	mineitemtype = /obj/item/mine/n2o

/obj/effect/mine/n2o/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	for (var/turf/simulated/floor/target in range(1,src))
		if(!target.blocks_air)
			target.assume_gas(GAS_N2O, 30)
	visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)
	consume(src)
