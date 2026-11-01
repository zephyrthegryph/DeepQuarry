// CALLBACK_OK names this file exactly.
/obj/holder/proc/callback_file_proc()
	var/datum/callback/cb = CALLBACK(src, PROC_REF(callback_file_proc))
	held = null
