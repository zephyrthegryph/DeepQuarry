// code/_helpers: CALLBACK is fine here, but it is not a raw-write core and handles are flagged.
/obj/holder/proc/helper_proc()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(helper_proc))
	var/h = om_handle(src)

/obj/holder
	var/helper_handle
