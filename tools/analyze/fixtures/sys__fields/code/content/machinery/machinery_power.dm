/obj/machinery/proc/set_powered(v)
	stat_add(NOPOWER)
	stat_remove(NOPOWER)
	stat_add(BROKEN)

/obj/machinery/proc/other_power(v)
	stat_add(NOPOWER)

/obj/machinery/proc/atom_break()
	stat_add(BROKEN)
