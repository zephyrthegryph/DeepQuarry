// Core directory (code/datums/om): raw writes are not checked, CALLBACK and handles are fine.
/obj/holder/proc/core_proc(X)
	held = null
	stuff += src
	var/datum/callback/cb = CALLBACK(src, PROC_REF(core_proc))
	var/h = om_handle(src)
	DECLARE_REF(thing)
	own_set(src, "held", src)
	own_set(X, nameof(ghost_in_core), src)

/obj/holder
	var/core_handle
