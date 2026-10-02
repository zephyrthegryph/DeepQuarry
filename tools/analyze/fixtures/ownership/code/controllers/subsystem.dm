// code/controllers: a core directory and CALLBACK-OK, handles are flagged.
/obj/holder/proc/controller_proc()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(controller_proc))
	var/h = om_handle(src)
