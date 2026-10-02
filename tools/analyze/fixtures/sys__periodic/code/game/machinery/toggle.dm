/obj/machinery/tog/proc/set_running(value)
	running = value
	om_task_periodic(src, PERIODIC_FAST)

/obj/machinery/tog/proc/set_running2(value)
	om_task_periodic(src, PERIODIC_FAST)
	set_running(value)

/obj/machinery/tog/proc/set_running3(value)
	src.running += 1
	MACHINE_WAKE(src)

/obj/machinery/tog/proc/set_running4(value)
	MACHINE_WAKE(src)
	set_on(TRUE)

/obj/machinery/tog/proc/set_running5(value)
	MACHINE_WAKE(src)
	thing_add(3)

/obj/machinery/tog/proc/set_running6(value)
	var/x = 1
	MACHINE_WAKE(src)
	var/y = 2

/obj/machinery/tog/proc/set_running7(value)
	MACHINE_WAKE(src)
	x++

/obj/machinery/tog/proc/branch(value)
	if(on)
		om_task_periodic(src, PERIODIC_FAST)
	else
		om_task_periodic_stop(src)

/obj/machinery/tog/proc/branch2(value)
	if(!operable())
		MACHINE_SLEEP(src)

/obj/machinery/tog/proc/branch3(value)
	if(prob(5))
		MACHINE_WAKE(src)

/obj/machinery/tog/proc/branch4(value)
	if(on) MACHINE_WAKE(src)

/obj/machinery/tog/proc/branch5(value)
	if(x)
		do_something()
	else
		MACHINE_WAKE(src)

/obj/machinery/tog/proc/branch6(value)
	if(foo())
		do_something()
	else
		MACHINE_WAKE(src)

/obj/machinery/tog/proc/branch7(value)
	if(active)
		do_something()
	else
		if(prob(2))
			do_other()
		MACHINE_WAKE(src)

/obj/machinery/tog/proc/branch8(value)
	if(has_stat(BROKEN))
		if(active)
			MACHINE_WAKE(src)

/obj/machinery/tog/proc/hand_stop()
	om_task_periodic_stop(src)

/obj/machinery/tog/proc/hand_stop2()
	MACHINE_SLEEP(src)

/obj/machinery/tog/machine_step(dt)
	MACHINE_SLEEP(src)

/obj/machinery/tog/proc/periodic_step(dt)
	om_task_periodic_stop(src)

/obj/machinery/tog/on_destroy(force)
	MACHINE_SLEEP(src)
	. = ..()

/obj/machinery/tog/proc/lifecycle_prerelease()
	om_task_periodic_stop(src)

/obj/machinery/tog/proc/on_dematerialize()
	om_task_periodic_stop(src)

/obj/machinery/tog/proc/lifecycle_dematerialize()
	MACHINE_SLEEP(src)

/obj/machinery/tog/proc/not_toggle()
	om_task_periodic(other, PERIODIC_FAST)
	MACHINE_WAKE(other)
	var/a = 3
	MACHINE_WAKE(src)

/obj/machinery/tog/proc/allowed_toggle(value)
	running = value
	// ALLOW(sys_periodic_toggle): this one is the declaration's own start
	om_task_periodic(src, PERIODIC_FAST)

/obj/machinery/tog/proc/commented_toggle(value)
	running = value
	// om_task_periodic(src, PERIODIC_FAST)
	x = 5 // om_task_periodic(src, PERIODIC_FAST)

/obj/machinery/tog/proc/indent_mismatch(value)
	running = value
		om_task_periodic(src, PERIODIC_FAST)

/obj/machinery/tog/proc/writes(value)
	var/q = 2
	src.running = TRUE
	om_task_periodic(src, PERIODIC_FAST)
	thing_remove(2)
	MACHINE_WAKE(src)

/obj/machinery/tog/proc/writes2(value)
	foo_bar_add(2)
	MACHINE_WAKE(src)
	a == b
	MACHINE_WAKE(src)
	a |= 2
	MACHINE_WAKE(src)
	.= 5
	MACHINE_WAKE(src)
