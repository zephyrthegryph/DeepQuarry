// Exempt file: the one DMAPI define file outside the tgs directory.
/obj/holder/proc/tgs_define_everything()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(tgs_define_everything))
	var/h = om_handle(src)
	DECLARE_REF(thing)
	own_set(src, "held", src)

/obj/holder
	var/tgs_define_handle
