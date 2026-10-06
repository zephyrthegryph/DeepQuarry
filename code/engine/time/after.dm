// after(): the one timer (the time engine: doc/rewrite/framework_gaps.md C1). rx_after() is its implementation (callers use after());
// om_after() and after_slot() (timers.dm) are legacy wrappers over it, and the timer store itself is timers.dm.
//
// A timer with a `key` is a TIMER relation on its owner: scheduling the same key again replaces the
// pending one, cancel_after() cancels it, after_pending() / after_left() read it. `clock` is CLOCK_OWN
// (the owner's clock: paused with it) or CLOCK_WORLD (real time; kept on the global owner, so it holds the
// owner by handle and never keeps it alive). A world timer, keyed or not, names its owner by handle (handles.dm), whose generation is the token:
// a reused slot or ref text never fires it on another datum, and a gone owner drops the call with a log line.

GLOBAL_VAR_INIT(rx_timer_seq, 0)

/**
 * Runs `handler` (a PROC_REF on `owner`, or a GLOBAL_PROC_REF called with `handler_args`) after `delay`
 * deciseconds. Returns the timer id. A datum argument deleted before it fires arrives as null.
 * `key`: names the timer; a pending timer of the same key on the same owner is replaced.
 */
/proc/rx_after(datum/owner, delay, handler, key, clock = CLOCK_OWN, list/handler_args, nulls_for_gone = TRUE)
	if(isnull(key) && clock == CLOCK_OWN)
		return om_after_list(owner, delay, handler, handler_args, nulls_for_gone)
	var/datum/holder = owner || om_global_owner()
	if(!isnull(key))
		cancel_after(holder, key)
	var/token = ++GLOB.rx_timer_seq
	var/id
	if(clock == CLOCK_WORLD)
		var/holder_handle = om_handle(holder)
		if(isnull(holder_handle))
			return 0 // the owner is already gone
		id = om_after_list(null, delay, GLOBAL_PROC_REF(rx_timer_fire_ref), list(holder_handle, handler, key, token, handler_args), FALSE)
	else
		// The holder is the timer's owner: passed first when it fires (OM_TIMER_OWNER_FIRST), not captured as an argument.
		id = om_after_list(holder, delay, GLOBAL_PROC_REF(rx_timer_fire), list(handler, key, token, handler_args), nulls_for_gone, owner_first = TRUE)
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
 * - `with`: the handler's arguments. A datum argument deleted meanwhile arrives as null, so cleanup always
 *   happens; the handler checks its args (null policy). Only the owner's own deletion drops the call.
 * Returns the timer id (never store it in a var; use a key).
 */
/proc/after(datum/owner, delay, handler, key = null, clock = CLOCK_OWN, list/with = null)
	return rx_after(owner, delay, handler, key, clock, with, TRUE)

/// after() for a pure effect that makes no sense once any datum argument is gone: the call is dropped
/// (counted and logged by the scheduler).
/proc/after_if_alive(datum/owner, delay, handler, list/with = null)
	return om_after_list(owner, delay, handler, with, nulls_for_gone = FALSE)

/// Deciseconds left on the pending timer of `key` on `owner` (on the clock it was armed on), or 0 when none is.
/proc/after_left(datum/owner, key)
	var/datum/holder = owner || om_global_owner()
	var/list/pending = holder.rx?.timer_ids?[key]
	if(!pending)
		return 0
	return om_timer_left(pending[3] == CLOCK_WORLD ? om_global_owner() : holder, pending[1]) || 0
