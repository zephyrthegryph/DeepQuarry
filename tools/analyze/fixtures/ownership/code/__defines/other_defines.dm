// Not exempt (only tgs.dm is): a core directory, so raw writes are skipped, callbacks are fine,
// handles are fine, but a removed form and a string name still count.
/obj/holder/proc/defines_proc()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(defines_proc))
	var/h = om_handle(src)
	DECLARE_REF(thing)
	own_set(src, "held", src)

/obj/holder
	var/define_handle
