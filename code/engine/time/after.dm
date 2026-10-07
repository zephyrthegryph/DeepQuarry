// after(): the one timer (the time engine: doc/rewrite/framework_gaps.md C1). rx_after() is its implementation (callers use after());
// timer_schedule() and after_slot() (timers.dm) are legacy wrappers over it, and the timer store itself is timers.dm.
//
// A timer with a `key` is a TIMER relation on its owner: scheduling the same key again replaces the
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
	if(isnull(key) && clock == CLOCK_OWN)
		return timer_schedule_list(owner, delay, handler, handler_args, keeps_dead)
	var/datum/holder = owner || om_global_owner()
	if(!isnull(key))
		cancel_after(holder, key)
	var/token = ++GLOB.rx_timer_seq
	var/id
	if(clock == CLOCK_WORLD)
		var/holder_handle = om_handle(holder)
		if(isnull(holder_handle))
			return 0 // the owner is already gone
		id = timer_schedule_list(null, delay, GLOBAL_PROC_REF(rx_timer_fire_ref), list(holder_handle, handler, key, token, handler_args), keeps_dead)
	else
		// The holder is the timer's owner: passed first when it fires (OM_TIMER_OWNER_FIRST), not captured as an argument.
		id = timer_schedule_list(holder, delay, GLOBAL_PROC_REF(rx_timer_fire), list(handler, key, token, handler_args), keeps_dead, owner_first = TRUE)
	if(id && !isnull(key))
		rx_ledger_add(holder, RELK_TIMER, key, token)
		var/list/ids = rx_of(holder).timer_ids
		if(!ids)
			ids = list()
			rx_of(holder).timer_ids = ids
		ids[key] = list(id, token, clock)
	return id

/// Cancels the pending timer of `key` on `owner`. Returns TRUE if one was pending.
/proc/cancel_after(datum/owner, key)
	var/datum/holder = owner || om_global_owner()
	var/list/pending = holder.rx?.timer_ids?[key]
	if(!pending)
		return FALSE
	holder.rx.timer_ids -= key
	if(!length(holder.rx.timer_ids))
		holder.rx.timer_ids = null
	rx_ledger_remove(holder, RELK_TIMER, key, pending[2]) // the key is the timer's one `what`: no scan of the ledger
	return om_cancel_timer(pending[3] == CLOCK_WORLD ? om_global_owner() : holder, pending[1])

/// TRUE while a timer of `key` is pending on `owner`.
/proc/after_pending(datum/owner, key)
	var/datum/holder = owner || om_global_owner()
	return !!holder.rx?.timer_ids?[key]

/// A world-clock timer went off: its owner is resolved from its handle, so a datum that was deleted (or whose ref was reused) never receives it.
/proc/rx_timer_fire_ref(holder_handle, handler, key, token, list/handler_args)
	var/datum/holder = om_resolve(holder_handle)
	if(!isdatum(holder))
		log_qdel("OM: world timer [handler] dropped: its owner [holder_handle] no longer exists")
		return
	rx_timer_fire(holder, handler, key, token, handler_args)

/// A keyed timer went off: it is dropped from the owner's ledger first (so the handler may re-arm it),
/// unless it was replaced or cancelled since (the token no longer matches).
/proc/rx_timer_fire(datum/holder, handler, key, token, list/handler_args)
	if(!holder || QDELETED(holder))
		return
	if(!isnull(key))
		var/list/pending = holder.rx?.timer_ids?[key]
		if(!pending || pending[2] != token)
			return
		holder.rx.timer_ids -= key
		if(!length(holder.rx.timer_ids))
			holder.rx.timer_ids = null
		rx_ledger_remove(holder, RELK_TIMER, key, token)
	if(om_proc_is_global(handler))
		call(handler)(arglist(handler_args || list()))
	else
		call(holder, handler)(arglist(handler_args || list()))

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

/// The completion of an async API that took `then =`, `owner =` and `with =` (the same shape as after()): schedules
/// after(owner, 0, then, with = with + the results). Nothing happens without a `then`; an owner that died meanwhile drops the call, as after() does.
/proc/after_done(datum/owner, then, list/with, ...)
	if(!then)
		return null
	var/list/call_with = with ? with.Copy() : list()
	for(var/i in 4 to length(args))
		call_with += list(args[i])
	return after(owner, 0, then, with = call_with)

/// after() with the default (drop on a deleted datum argument) spelled out; kept for callers that name it.
/proc/after_if_alive(datum/owner, delay, handler, list/with = null)
	return timer_schedule_list(owner, delay, handler, with, nulls_for_gone = FALSE)

/// Deciseconds left on the pending timer of `key` on `owner` (on the clock it was armed on), or 0 when none is.
/proc/after_left(datum/owner, key)
	var/datum/holder = owner || om_global_owner()
	var/list/pending = holder.rx?.timer_ids?[key]
	if(!pending)
		return 0
	return om_timer_left(pending[3] == CLOCK_WORLD ? om_global_owner() : holder, pending[1]) || 0

// ---- unique calls: one pending timer per (owner, handler, arguments) ----

/// after(), unless the same call (owner, handler, `with`) is already pending: then nothing, and the pending timer's id is returned. Keyed by the call itself, not
/// by a name: for work that many triggers ask for and one run answers (coalesce()). `handler` is a PROC_REF on the owner or a TYPE_PROC_REF.
/proc/after_unique(datum/owner, delay, handler, list/with = null)
	var/datum/holder = owner || om_global_owner()
	return om_scheduler().after_unique(arglist(list(holder, delay, handler) + (with || list())))

/// TRUE while a call made by after_unique(owner, ..., handler, with) is pending.
/proc/after_unique_pending(datum/owner, handler, list/with = null)
	var/datum/holder = owner || om_global_owner()
	var/datum/om/rec/rec = holder.om_rec
	return !!rec && !!om_scheduler().timer_find(rec, handler, with || list())

/// Cancels the pending call of after_unique(owner, ..., handler, with). TRUE when one was pending.
/proc/cancel_after_unique(datum/owner, handler, list/with = null)
	var/datum/holder = owner || om_global_owner()
	var/datum/om/rec/rec = holder.om_rec
	if(!rec)
		return FALSE
	var/i = om_scheduler().timer_find(rec, handler, with || list())
	if(!i)
		return FALSE
	return om_cancel_timer(holder, rec.timers[i])
