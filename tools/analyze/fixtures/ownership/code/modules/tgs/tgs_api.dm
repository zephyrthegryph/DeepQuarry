// Exempt path: the vendored tgstation-server DMAPI is kept verbatim.
/obj/holder/proc/tgs_everything()
	held = null
	var/datum/callback/cb = CALLBACK(src, PROC_REF(tgs_everything))
	var/h = om_handle(src)
	DECLARE_REF(thing)
	own_set(src, "held", src)
	own_set(src, nameof(ghost_in_tgs), src)

/obj/holder
	var/tgs_handle
