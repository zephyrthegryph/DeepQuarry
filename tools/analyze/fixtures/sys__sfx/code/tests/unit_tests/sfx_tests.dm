/obj/item/test
	var/hitsound = 'sound/test.ogg'

/obj/item/test/proc/run()
	playsound(src, 'sound/test2.ogg', 50)
	playsound(src, "punch")
	new /datum/effect/effect/system/spark_spread
