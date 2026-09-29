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

/// var name -> list(token, prior value, clock).
/datum/var/tmp/list/timed_until

OWN_TIMER(/datum, timed)

/// Identifies one timed_set() so a replaced timer that still fires is ignored.
GLOBAL_VAR_INIT(timed_token_seq, 0)

#define TIMED_TOKEN 1
#define TIMED_PRIOR 2
#define TIMED_CLOCK 3
/// The value timed_set wrote: the revert only fires while the var still holds it (M5).
#define TIMED_SET_VALUE 4

/// Writes V on D through its setter (or directly, then changed()). Framework use only.
/proc/timed_write(datum/D, var_name, value)
	var/setter = "set_[var_name]"
	if(hascall(D, setter))
		call(D, setter)(value)
		return
	if(D.vars[var_name] == value)
		return
	D.vars[var_name] = value // ALLOW(api): the timed-state writer for a var with no setter
	changed(D)

/proc/timed_set(datum/D, var_name, value, for_time, clock = CLOCK_WORLD, keep_longer = FALSE, revert_to)
	if(!D || QDELING(D) || !(var_name in D.vars))
		CRASH("timed_set: [D?.type] has no var [var_name]")
	var/list/pending = D.timed_until?[var_name]
	if(keep_longer && pending && time_left(D, var_name) > for_time)
		return FALSE
	var/prior = pending ? pending[TIMED_PRIOR] : D.vars[var_name]
	if(!isnull(revert_to))
		prior = revert_to
	if(pending)
		timed_cancel(D, var_name)
	timed_write(D, var_name, value)
	if(!for_time)
		return TRUE
	var/token = ++GLOB.timed_token_seq
	LAZYSET(D.timed_until, var_name, list(token, prior, clock, D.vars[var_name]))
	if(clock == CLOCK_WORLD)
		// Real time runs on the global owner. It holds a ref text, not D, so the timer never keeps a
		// deleted holder alive; the token check drops a stale or reused ref.
		after_slot(null, "timed:[SHARED_CACHE_UID(D)]:[var_name]", for_time, GLOBAL_PROC_REF(timed_expire_ref), REF(D), var_name, token)
	else
		after_slot(D, "timed:[var_name]", for_time, GLOBAL_PROC_REF(timed_expire), D, var_name, token)
	return TRUE

/proc/timed_expire_ref(ref_text, var_name, token)
	var/datum/D = locate(ref_text)
	if(isdatum(D))
		timed_expire(D, var_name, token)

/proc/timed_expire(datum/D, var_name, token)
	if(QDELETED(D))
		return
	var/list/pending = D.timed_until?[var_name]
	if(!pending || pending[TIMED_TOKEN] != token)
		return
	LAZYREMOVE(D.timed_until, var_name)
	// M5: something else wrote the var since (through its setter, the only other writer): keep it.
	if(D.vars[var_name] != pending[TIMED_SET_VALUE])
		return
	timed_write(D, var_name, pending[TIMED_PRIOR])

/**
 * A delayed action (the third time form, next to timed_set() and COOLDOWN_*): calls proc_ref on E after
 * delay, as a dispatched call (E is marked changed afterwards). Owned by E: E's teardown cancels it.
 * Returns the OM timer id (never store it in a var; use timed_set() for state that must revert).
 *	after(src, vend_delay, PROC_REF(finish_vend), product, user)
 */
/proc/after(datum/E, delay, proc_ref, ...)
	var/list/call_args = list(E, delay, proc_ref)
	if(length(args) > 3)
		call_args += args.Copy(4)
	return om_after(arglist(call_args))

/// Deciseconds until var_name reverts (0 when nothing is pending), on the clock it was set on.
/proc/time_left(datum/D, var_name)
	var/list/pending = D.timed_until?[var_name]
	if(!pending)
		return 0
	if(pending[TIMED_CLOCK] == CLOCK_WORLD)
		return om_timer_slot_left(null, "timed:[SHARED_CACHE_UID(D)]:[var_name]") || 0
	return om_timer_slot_left(D, "timed:[var_name]") || 0

/// Cancels a pending revert, leaving the current value.
/proc/timed_cancel(datum/D, var_name)
	var/list/pending = D.timed_until?[var_name]
	if(!pending)
		return
	LAZYREMOVE(D.timed_until, var_name)
	if(pending[TIMED_CLOCK] == CLOCK_WORLD)
		om_cancel_timer_slot(null, "timed:[SHARED_CACHE_UID(D)]:[var_name]")
	else
		om_cancel_timer_slot(D, "timed:[var_name]")

#undef TIMED_TOKEN
#undef TIMED_PRIOR
#undef TIMED_CLOCK
#undef TIMED_SET_VALUE
