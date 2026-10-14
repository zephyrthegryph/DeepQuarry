// Outside code/: the ownership lint only reads code/**/*.dm.
/obj/holder/proc/map_proc()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(map_proc))
	own_set(src, "ghost_map", src)
