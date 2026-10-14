// An unbalanced apostrophe in code makes code_only drop lines: the Python indexes the raw lines with the
// code view's line numbers, so everything after it is read from the wrong raw line.
/obj/holder/proc/drift()
	var/x = 'a
	held = null
	var/y = b'
	occupant = null
	own_set(src, "ghost_drift", src)
	DECLARE_REF(thing)
	var/datum/callback/cb = CALLBACK(src, PROC_REF(drift))
	stuff += src
