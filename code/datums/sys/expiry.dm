// Expiry runtime (code/__defines/sys_expiry.dm, doc/rewrite/systems.md section 17).

/// D's OM timer clock in deciseconds (the clock om_after() timers on D run on). Falls back to
/// world.time for a null or deleted datum so a read on a dead holder never runtimes.
/proc/expiry_clock_now(datum/D)
	if(!D || QDELETED(D))
		return world.time
	var/datum/om/rec/rec = om_rec_of(D)
	if(!rec)
		return world.time
	return om_timer_local(rec)
