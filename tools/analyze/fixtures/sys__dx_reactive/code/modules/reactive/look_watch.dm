/obj/machinery/watcher
	var/obj/machinery/other/neighbour
	var/obj/machinery/other/stranger

/obj/machinery/watcher/draw(datum/look/look)
	..()
	look.watch(neighbour)
	look.overlay("a-[neighbour.zap]")
	look.overlay("b-[stranger.zap]")
	for(var/obj/machinery/other/O in oview(src, 1))
		look.watch(O)
		look.overlay("c-[O.zap]")
	look.overlay("d-[neighbour.dir]")
	look.overlay("e-[stranger.dir]")
