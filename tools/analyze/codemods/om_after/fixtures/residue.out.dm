#define LATER(x) om_after(src, 5, PROC_REF(x))

/datum/thing/proc/odd(list/args_list)
	om_after(src, 5, PROC_REF(tick), foo = 1)
	om_after(src, 5, PROC_REF(tick), arglist(args_list))
	om_after(src, 5)
	var/ref = GLOBAL_PROC_REF(om_after)
	// still converted: the sites above do not stop their neighbours
	after(src, 5, PROC_REF(tick), with = list(id))
