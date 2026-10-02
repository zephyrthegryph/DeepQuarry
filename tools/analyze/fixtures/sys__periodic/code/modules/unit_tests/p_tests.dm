/obj/machinery/utest/machine_step(dt)
	if(!on) return PROCESS_KILL

/obj/machinery/utest/proc/loop()
	om_after(src, 5 SECONDS, PROC_REF(loop))
