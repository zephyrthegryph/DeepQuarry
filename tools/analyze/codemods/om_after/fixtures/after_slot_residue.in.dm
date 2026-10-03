/datum/thing/proc/slots()
	var/ok = after_slot(src, "x", 1, PROC_REF(tick))
	if(after_slot(src, "y", 1, PROC_REF(tick)))
		return
	after_slot(src, "c" /* why */, 1, PROC_REF(tick))
	after_slot(src, "named", 1, PROC_REF(tick), foo = 2)
	after_slot(src, "short", 1)
	after_slot(src, "spread", 1, PROC_REF(tick), arglist(list(1)))
	after_slot(src, "fine", 1, PROC_REF(tick), 1)
