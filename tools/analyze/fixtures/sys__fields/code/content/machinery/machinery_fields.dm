/obj/machinery/proc/runtime_a()
	if(inoperable())
		return
	stat & BROKEN
	stat |= 1
	on = 1
	stat_add(BROKEN)
	stat_add(NOPOWER)
	set_stat(BROKEN)
