/// D's OM timer clock in deciseconds (the clock after() timers on D run on). Falls back to
/// world.time for a null or deleted datum so a read on a dead holder never runtimes.
/proc/expiry_clock_now(datum/D)
	READS_FROM() // a clock, asked when a choice is made, never cached
	if(!D || QDELETED(D))
		return world.time
	var/datum/scheduler_record/rec = scheduler_record_of(D)
	if(!rec)
		return world.time
	return timer_local(rec)
