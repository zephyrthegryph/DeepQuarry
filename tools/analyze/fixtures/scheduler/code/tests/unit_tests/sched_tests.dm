// Exempt path: unit tests build the forbidden things on purpose.
/datum/unit_test/proc/everything()
	spawn(0)
	sleep(1)
	addtimer(CALLBACK(src, PROC_REF(everything)), 1)
	INVOKE_ASYNC(src, PROC_REF(everything))
	do_after(usr, 5)
	stoplag()
	var/a = input(usr, "q")
	set waitfor = 0
	var/r = WEAKREF(src)
	del(src)
	winget(usr, "a", "b")
