OM_FIELD(/obj/testthing, mode, 0, CHANGE_TEST)

/obj/machinery/proc/ut_proc()
	on = 1
	stat & BROKEN
	stat_add(BROKEN)
	inoperable()
