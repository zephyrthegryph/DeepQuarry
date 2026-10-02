// One positive and the near misses for each of the eleven rules.
/obj/thing/proc/spawn_cases()
	spawn(0)
	spawn (5)
	spawn(1) spawn(2)
	x.spawn(1)
	respawn(1)
	var/spawned = 1
	/datum/proc/spawn(delay)
	return spawn(10)

/obj/thing/proc/addtimer_cases()
	addtimer(CALLBACK(src, PROC_REF(spawn_cases)), 5)
	addtimer (CALLBACK(src, PROC_REF(spawn_cases)), 5)
	obj.addtimer(1)
	my_addtimer(1)

/obj/thing/proc/invoke_cases()
	INVOKE_ASYNC(src, PROC_REF(spawn_cases))
	INVOKE_ASYNC(src, PROC_REF(spawn_cases)) INVOKE_ASYNC(src, PROC_REF(spawn_cases))
	MY_INVOKE_ASYNC(src)
	INVOKE_ASYNC_X(src)
	x.INVOKE_ASYNC(src)

/obj/thing/proc/do_after_cases()
	do_after(usr, 5)
	do_after (usr, 5)
	x.do_after(usr, 5)
	/proc/do_after(a)
	redo_after(usr)
	var/ok = do_after_done

/obj/thing/proc/sleep_cases()
	sleep(1)
	sleep (1)
	usr.sleep(2)
	/proc/sleep(a)
	unsleep(1)
	sleeping(1)
	sleep(1); sleep(2)

/obj/thing/proc/stoplag_cases()
	stoplag()
	stoplag (2)
	x.stoplag()
	/proc/stoplag(a)

/obj/thing/proc/prompt_cases()
	var/a = input(usr, "q") as text
	var/b = alert(usr, "q")
	var/c = tgui_input_list(usr, "q", "t", list())
	var/d = tgui_input_text(usr, "q")
	var/e = tgui_alert(usr, "q")
	var/f = my_input(usr)
	var/g = x.input(usr)
	var/h = alert_user(usr)
	var/i = input
	var/j = /proc/input(a)
	var/k = tgui_input(usr)

/obj/thing/proc/waitfor_cases()
	set waitfor = FALSE
	set  waitfor=0
	set	waitfor = 0
	reset waitfor = 0
	set waitforit = 1
	var/set_waitfor = 1

/obj/thing/proc/weakref_cases()
	var/datum/weakref/ref = WEAKREF(src)
	var/w = new /datum/weakref()
	var/x = WeakRef
	var/y = weakreference
	var/z = "weakref"

/obj/thing/proc/del_cases()
	del(src)
	del (src)
	qdel(src)
	x.del(src)
	/proc/del(a)
	delete(src)
	var/model = 1
	del(a); del(b)

/obj/thing/proc/blocking_cases()
	var/a = winget(usr, "map", "size")
	winexists(usr, "map")
	shell("ls")
	var/w = text.MeasureText("hi")
	usr.shell("ls")
	x.winget(usr)
	/proc/winget(a)
	var/size = text .MeasureText("hi")
	var/s = my_shell("ls")
	var/t = shelf("ls")
	var/u = winget_x(1)
