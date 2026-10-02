/obj/machinery/guarded/machine_step(dt)
	if(!on) return PROCESS_KILL
	do_work()

/obj/machinery/guarded2/proc/periodic_step(dt)
	if(!on || !active)
		return PROCESS_KILL
	do_work()

/obj/machinery/guarded3/machine_step(dt)
	if(!operable())
		return PROCESS_KILL
	if(has_stat(BROKEN | NOPOWER))
		return PROCESS_KILL
	if(src.on && !src.locked) return PROCESS_KILL
	if((on))
		return PROCESS_KILL
	do_work()

/obj/machinery/guarded4/machine_step(dt)
	var/limit = 5
	if(!limit)
		return PROCESS_KILL
	if(!on)
		return PROCESS_KILL
		do_more()
	if(!active)
		return PROCESS_KILL
	do_work()

/obj/machinery/guarded5/machine_step(dt)
	if(on)
		return PROCESS_KILL
	do_work()
	if(!locked)
		return PROCESS_KILL
	return

/obj/machinery/notguard/machine_step(dt)
	if(prob(5)) return PROCESS_KILL
	if(on.thing) return PROCESS_KILL
	if(foo(x)) return PROCESS_KILL
	if(TRUE) return PROCESS_KILL
	if(ACTIVE_CONST) return PROCESS_KILL
	if(on) return TRUE
	else if(!on) return PROCESS_KILL
	do_work()
	if(!on)
		if(!active)
			return PROCESS_KILL

/obj/machinery/notstep/process(dt)
	if(!on) return PROCESS_KILL

/obj/machinery/allowed/machine_step(dt)
	// ALLOW(sys_periodic_guard): the step slides its own deadline
	if(!on) return PROCESS_KILL
	if(!active) return PROCESS_KILL // ALLOW(sys_periodic_guard): legacy gate

/obj/machinery/commented/machine_step(dt)
	// if(!on) return PROCESS_KILL
	if(!on) // comment
		return PROCESS_KILL // trailing
