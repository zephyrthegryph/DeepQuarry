/obj/machinery/skip/machine_step(dt)
	if(!on) return PROCESS_KILL

/obj/machinery/skip/proc/loop()
	om_after(src, 5 SECONDS, PROC_REF(loop))

/obj/machinery/skip/proc/toggle(value)
	running = value
	om_task_periodic(src, PERIODIC_FAST)
	MACHINE_SLEEP(src)

/obj/machinery/dv/proc/derived_skip()
	changed(src, CHANGE_EXPLICIT)
