// Timed state (doc/rewrite/dx_conventions.md §7).
//
//	timed_set(src, nameof(emp_disabled), TRUE, for_time = 90 SECONDS / severity)
//	time_left(src, nameof(emp_disabled))
//
// timed_set() writes the var through its setter (set_<var>() when the type has one, else a direct
// write plus changed()), and when for_time runs out writes the var's value from before the call back
// the same way, so every reader (draw, should_run, UI) reacts on its own: there is no lapse hook.
// CLOCK_OWN runs on the holder's own clock (paused in stasis or suspension) in an owned timer slot
// that the holder's teardown cancels; CLOCK_WORLD runs on real time. Setting again replaces the timer;
// keep_longer = TRUE keeps whichever of the two ends later.

/datum/var/tmp/list/timed_until

OWN_TIMER(/datum, timed)

/// Writes V on D through its setter (or directly, then changed()). Framework use only.
/proc/timed_write(datum/D, var_name, value)
	var/setter = "set_[var_name]"
	if(hascall(D, setter))
		call(D, setter)(value)
		return
	if(D.vars[var_name] == value)
		return
	D.vars[var_name] = value // ALLOW(timed:direct_write): the timed-state writer for a var with no setter
	changed(D)

/proc/timed_set(datum/D, var_name, value, for_time, clock = CLOCK_OWN, keep_longer = FALSE, revert_to)
	if(!D || QDELING(D) || !(var_name in D.vars))
		CRASH("timed_set: [D?.type] has no var [var_name]")
	var/ends = world.time + for_time
	var/pending = D.timed_until?[var_name]
	if(keep_longer && pending && pending[1] > ends)
		return FALSE
	var/prior = pending ? pending[2] : D.vars[var_name]
	if(!isnull(revert_to))
		prior = revert_to
	timed_write(D, var_name, value)
	if(!for_time)
		return TRUE
	LAZYSET(D.timed_until, var_name, list(ends, prior, D.vars[var_name]))
	var/slot = "timed:[var_name]"
	if(clock == CLOCK_WORLD)
		// Real time runs on the global owner; the call is dropped if D is deleted first.
		om_after_slot(null, "timed:[SHARED_CACHE_UID(D)]:[var_name]", for_time, GLOBAL_PROC_REF(timed_expire), D, var_name, ends)
	else
		om_after_slot(D, slot, for_time, GLOBAL_PROC_REF(timed_expire), D, var_name, ends)
	return TRUE

/proc/timed_expire(datum/D, var_name, ends)
	if(QDELETED(D))
		return
	var/list/pending = D.timed_until?[var_name]
	if(!pending || pending[1] != ends)
		return
	LAZYREMOVE(D.timed_until, var_name)
	// M5: something else wrote the var since (it had the right to, through the setter): keep its value.
	if(D.vars[var_name] != pending[3])
		return
	timed_write(D, var_name, pending[2])

/// Deciseconds until var_name reverts (0 when nothing is pending).
/proc/time_left(datum/D, var_name)
	var/list/pending = D.timed_until?[var_name]
	return pending ? max(0, pending[1] - world.time) : 0

/// Cancels a pending revert, leaving the current value.
/proc/timed_cancel(datum/D, var_name)
	if(!D.timed_until?[var_name])
		return
	LAZYREMOVE(D.timed_until, var_name)
	om_cancel_timer_slot(D, "timed:[var_name]")
