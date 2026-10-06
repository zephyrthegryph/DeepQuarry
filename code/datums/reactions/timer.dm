// after(): the one timer. rx_after() is its implementation (internal: callers use after(), timed.dm); after()
// and after_slot() (om/timer.dm) are legacy wrappers over it.
//
// A timer with a `key` is a TIMER relation on its owner: scheduling the same key again replaces the
// pending one, cancel_after() cancels it, after_pending() / after_left() read it. `clock` is CLOCK_OWN
// (the owner's clock: paused with it) or CLOCK_WORLD (real time; kept on the global owner, so it holds the
// owner by ref text and never keeps it alive).

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
		id = om_after_list(null, delay, GLOBAL_PROC_REF(rx_timer_fire_ref), list(REF(holder), handler, key, token, handler_args), FALSE)
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

/proc/rx_timer_fire_ref(ref_text, handler, key, token, list/handler_args)
	var/datum/holder = locate(ref_text)
	if(isdatum(holder))
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
