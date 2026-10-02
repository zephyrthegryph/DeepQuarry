// A dot directory: glob.glob skips it, so no lint sees this file.
/obj/holder/proc/hidden_proc()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(hidden_proc))
	own_set(src, "ghost_hidden", src)
