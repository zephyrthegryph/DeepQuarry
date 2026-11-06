// after(): the one timer (the time engine: doc/rewrite/framework_gaps.md C1). rx_after() is its implementation (callers use after());
// timer_schedule() and after_slot() (timers.dm) are legacy wrappers over it, and the timer store itself is timers.dm.
//
// A timer with a `key` is kept by key in its owner's record (rec.timer_keys, timers.dm): scheduling the same key again replaces the
// pending one, cancel_after() cancels it, after_pending() / after_left() read it. `clock` is CLOCK_OWN
// (the owner's clock: paused with it) or CLOCK_WORLD (real time; kept on the global owner, so it holds the
// owner by handle and never keeps it alive). A world timer, keyed or not, names its owner by handle (handles.dm), whose generation is the token:
// a reused slot or ref text never fires it on another datum, and a gone owner drops the call with a log line.

GLOBAL_VAR_INIT(rx_timer_seq, 0)

/**
 * Runs `handler` (a PROC_REF on `owner`, or a GLOBAL_PROC_REF called with `handler_args`) after `delay`
 * deciseconds. Returns the timer id. A datum argument deleted before it fires drops the call (logged),
 * unless `keeps_dead` is set: then it arrives as null.
 * `key`: names the timer; a pending timer of the same key on the same owner is replaced.
 */
/proc/rx_after(datum/owner, delay, handler, key, clock = CLOCK_OWN, list/handler_args, keeps_dead = FALSE)
	if(!isnull(owner) && !isdatum(owner))
		// DM does not check a typed parameter at runtime: a call written after(delay, handler, ...) lands its delay here as the owner.
		stack_trace("after(): the owner must be a datum or null, got [owner] ([handler]); arguments are after(owner, delay, handler, ...)")
		return 0
	if(isnull(handler) || isnum(handler))
		// after(src, PROC_REF(x), delay) lands the delay here; a null handler would only runtime when it fires, far from the mistake.
		stack_trace("after(): the handler must be a proc reference, got [isnull(handler) ? "null" : "[handler]"] on [owner?.type]; arguments are after(owner, delay, handler, ...)")
		return 0
	if(!isnum(delay))
		// max(text or null, 0) runs the handler on the next tick, whatever was meant. A delay that came out null still runs (dropping gameplay is worse), and says so.
		stack_trace("after(): the delay must be a number of deciseconds, got [isnull(delay) ? "null" : "[delay]"] ([handler] on [owner?.type])")
		if(!isnull(delay))
			return 0
		delay = 0
	if(!isnull(handler_args) && !islist(handler_args))
		// with = probe instead of with = list(probe) would only runtime in arglist() when it fires.
		stack_trace("after(): with must be a list, got [handler_args] ([handler] on [owner?.type])")
		return 0
	if(!isnull(key) && !istext(key) && !isnum(key))
		// after(src, delay, PROC_REF(x), list(a)) lands the arguments here: the handler would run without them, under a key nothing can cancel.
		stack_trace("after(): the key must be text or a number, got [key] ([handler] on [owner?.type]); arguments go in with =")
		return 0
	if(isnull(key) && clock == CLOCK_OWN)
		return timer_schedule_list(owner, delay, handler, handler_args, keeps_dead)
	var/datum/holder = owner || timer_global_owner()
	if(!isnull(key))
		cancel_after(holder, key)
	var/token = ++GLOB.rx_timer_seq
	var/id
	// A keyed timer is in the key table too, so a call dropped for a deleted datum argument must still clear the key: the outer capture keeps the
	// gone argument as null (keeps_dead) and rx_timer_fire() drops the call itself, after the key is cleared, for the positions watched here.
	var/list/watched
	if(!keeps_dead)
		for(var/i in 1 to length(handler_args))
			if(isdatum(handler_args[i]))
				LAZYADD(watched, i)
	if(clock == CLOCK_WORLD)
		var/holder_handle = handle_of(holder)
		if(isnull(holder_handle))
			return 0 // the owner is already gone
		id = timer_schedule_list(null, delay, GLOBAL_PROC_REF(rx_timer_fire_ref), list(holder_handle, handler, key, token, handler_args, watched), TRUE)
	else
		// The holder is the timer's owner: passed first when it fires (SCHED_TIMER_OWNER_FIRST), not captured as an argument.
		id = timer_schedule_list(holder, delay, GLOBAL_PROC_REF(rx_timer_fire), list(handler, key, token, handler_args, watched), TRUE, owner_first = TRUE)
	if(id && !isnull(key))
		timer_key_set(holder, key, id, token, clock)
	return id

/// Cancels the pending timer of `key` on `owner`. Returns TRUE if one was pending.
/proc/cancel_after(datum/owner, key)
	var/datum/holder = owner || timer_global_owner()
	var/list/pending = timer_key_get(holder, key)
	if(!pending)
		return FALSE
	timer_key_clear(holder, key)
	return timer_cancel(pending[3] == CLOCK_WORLD ? timer_global_owner() : holder, pending[1])

/// TRUE while a timer of `key` is pending on `owner`.
/proc/after_pending(datum/owner, key)
	var/datum/holder = owner || timer_global_owner()
	return !!timer_key_get(holder, key)

/// A world-clock timer went off: its owner is resolved from its handle, so a datum that was deleted (or whose ref was reused) never receives it.
/proc/rx_timer_fire_ref(holder_handle, handler, key, token, list/handler_args, list/watched)
	var/datum/holder = handle_get(holder_handle)
	if(!isdatum(holder))
		log_qdel("scheduler: world timer [handler] dropped: its owner [holder_handle] no longer exists")
		return
	rx_timer_fire(holder, handler, key, token, handler_args, watched)

/// A keyed timer went off: it leaves the owner's key table first (so the handler may re-arm it),
/// unless it was replaced or cancelled since (the token no longer matches).
/proc/rx_timer_fire(datum/holder, handler, key, token, list/handler_args, list/watched)
	if(!holder || QDELETED(holder))
		return
	if(!isnull(key))
		var/list/pending = timer_key_get(holder, key)
		if(!pending || pending[2] != token)
			return
		timer_key_clear(holder, key)
	for(var/position in watched)
		if(isnull(handler_args[position]))
			log_qdel("scheduler: timer [handler] dropped: argument [position] no longer exists")
			return
	var/census_start = GLOB.census_on ? TICK_USAGE_REAL : null
	GLOB.km_attr_a = holder.type // attribution: the handler this keyed timer carries, not this dispatcher
	GLOB.km_attr_b = handler
	if(deferred_proc_is_global(handler))
		call(handler)(arglist(handler_args || list()))
	else
		call(holder, handler)(arglist(handler_args || list()))
	if(!isnull(census_start))
		census_timer_note(holder, handler, TICK_DELTA_TO_MS(TICK_USAGE_REAL - census_start))

/**
 * The one timer (the third time form, next to timed_set() and COOLDOWN_*): calls `handler` after `delay`
 * deciseconds, a PROC_REF on `owner` or a GLOBAL_PROC_REF called with `with`. Stored as a TIMER relation on the
 * owner, so the owner's teardown drops it.
 *	after(src, vend_delay, PROC_REF(finish_vend), with = list(product, user))
 *	after(src, 15 MINUTES, PROC_REF(set_grid_check), key = "grid_check", with = list(FALSE))
 * - `key`: names the timer; scheduling the same key on the same owner again replaces the pending one, and
 *   cancel_after() / after_pending() / after_left() find it.
 * - `clock`: CLOCK_OWN (the owner's clock: paused in stasis or suspension) or CLOCK_WORLD (real time; held by
 *   ref, so the timer never keeps a deleted owner alive).
 * - `with`: the handler's arguments. When a datum argument has been deleted by the time the timer fires, the call is
 *   dropped and logged (the handler never sees a dead argument). `keeps_dead = TRUE` opts out: the call still runs and the
 *   deleted argument arrives as null, for a handler that has cleanup to do with the argument gone (re-arming a flag, say).
 *   The owner's own deletion always drops the call.
 * Returns the timer id (never store it in a var; use a key).
 */
/proc/after(datum/owner, delay, handler, key = null, clock = CLOCK_OWN, list/with = null, keeps_dead = FALSE)
	return rx_after(owner, delay, handler, key, clock, with, keeps_dead)

/// after() with the default (drop on a deleted datum argument) spelled out; kept for callers that name it.
/proc/after_if_alive(datum/owner, delay, handler, list/with = null)
	return timer_schedule_list(owner, delay, handler, with, nulls_for_gone = FALSE)

/// Deciseconds left on the pending timer of `key` on `owner` (on the clock it was armed on), or 0 when none is.
/proc/after_left(datum/owner, key)
	var/datum/holder = owner || timer_global_owner()
	var/list/pending = timer_key_get(holder, key)
	if(!pending)
		return 0
	return timer_left(pending[3] == CLOCK_WORLD ? timer_global_owner() : holder, pending[1]) || 0

// ---- unique calls: one pending timer per (owner, handler, arguments) ----

/// after(), unless the same call (owner, handler, `with`) is already pending: then nothing, and the pending timer's id is returned. Keyed by the call itself, not
/// by a name: for work that many triggers ask for and one run answers (coalesce()). `handler` is a PROC_REF on the owner or a TYPE_PROC_REF.
/proc/after_unique(datum/owner, delay, handler, list/with = null)
	var/datum/holder = owner || timer_global_owner()
	return time_scheduler().after_unique(arglist(list(holder, delay, handler) + (with || list())))

/// TRUE while a call made by after_unique(owner, ..., handler, with) is pending.
/proc/after_unique_pending(datum/owner, handler, list/with = null)
	var/datum/holder = owner || timer_global_owner()
	var/datum/scheduler_record/rec = holder.sched_rec
	return !!rec && !!time_scheduler().timer_find(rec, handler, with || list())

/// Cancels the pending call of after_unique(owner, ..., handler, with). TRUE when one was pending.
/proc/cancel_after_unique(datum/owner, handler, list/with = null)
	var/datum/holder = owner || timer_global_owner()
	var/datum/scheduler_record/rec = holder.sched_rec
	if(!rec)
		return FALSE
	var/i = time_scheduler().timer_find(rec, handler, with || list())
	if(!i)
		return FALSE
	return timer_cancel(holder, rec.timers[i])
