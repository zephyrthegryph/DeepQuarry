/obj/machinery/proc/atom_break()
	stat_add(BROKEN)
	stat_add(NOPOWER)

/obj/machinery/proc/atom_fix()
	stat_remove(BROKEN)

/obj/machinery/proc/set_powered(v)
	stat_add(NOPOWER)

/obj/machinery/proc/something_else()
	set_stat(BROKEN)
