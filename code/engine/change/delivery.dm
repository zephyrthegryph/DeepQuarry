// Delivery of reactions: change drains, operations, notices, band crossings, periodic work and observe().
// The contracts are stated in reactions.dm.

/// Calls `handler` (a PROC_REF on `holder`, or a /proc path) with the rest of the arguments.
/proc/rx_call(datum/holder, handler, ...)
	var/list/rest = length(args) > 2 ? args.Copy(3) : list()
	if(deferred_proc_is_global(handler))
		return call(handler)(arglist(list(holder) + rest)) // globals get the holder first (see reactions.dm)
	return call(holder, handler)(arglist(rest))

/// A runtime subscription made by observe().
/datum/rx_listener
	var/datum/source
	var/datum/reaction/trigger
	var/datum/listener
	var/handler

/// Every listener record and the type it reads is torn down with either end (rx_teardown).
/proc/rx_listener_remove(datum/rx_listener/L)
	var/datum/source = L.source
	var/datum/listener = L.listener
	var/datum/reaction/R = L.trigger
	if(source?.rx)
		source.rx.listeners -= L
		if(!length(source.rx.listeners))
			source.rx.listeners = null
		rx_observed_adjust(source, R, -1)
		rx_ledger_remove(source, RELK_LISTENER, listener, R.sig)
		GLOB.rx_pending_listeners -= L
		if(source.rx.bands && R.kind == RXN_CROSS)
			source.rx.bands -= "[R.sig]"
	if(listener?.rx)
		listener.rx.listening -= L
		if(!length(listener.rx.listening))
			listener.rx.listening = null
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	L.source = null
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	L.listener = null

/proc/rx_observed_adjust(datum/source, datum/reaction/R, delta)
	var/datum/rx_state/S = rx_of(source)
	if(R.kind == RXN_CHANGE || R.kind == RXN_CROSS)
		if(!S.observed)
			S.observed = list()
		for(var/key in R.reads)
			var/n = (S.observed[key] || 0) + delta
			if(n > 0)
				S.observed[key] = n
			else
				S.observed -= key
		if(!length(S.observed))
			S.observed = null
	else if(R.kind == RXN_NOTICE)
		if(!S.notice_types)
			S.notice_types = list()
		var/n = (S.notice_types[R.key] || 0) + delta
		if(n > 0)
			S.notice_types[R.key] = n
		else
			S.notice_types -= R.key
		if(!length(S.notice_types))
			S.notice_types = null

/**
 * `listener` reacts to `trigger` (a reaction made by on_change / on_notice / before_op / after_op /
 * on_cross) on `source`, calling `handler` on the listener: handler(source, ...) with the trigger's own
 * arguments after the source. Stored as a LISTENER relation on the source; both ends drop it when either
 * dies. Returns the record (the same one if it already exists).
 */
/proc/legacy_observe(datum/source, datum/reaction/trigger, datum/listener, handler)
	if(!source || !listener || !istype(trigger) || QDELING(source) || QDELING(listener))
		return null
	for(var/datum/rx_listener/known as anything in source.rx?.listeners)
		if(known.listener == listener && known.trigger.sig == trigger.sig && known.handler == handler)
			return known
	var/datum/rx_listener/L = new
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	L.source = source
	// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	L.trigger = trigger
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	L.listener = listener
	L.handler = handler
	var/datum/rx_state/S = rx_of(source)
	if(!S.listeners)
		S.listeners = list()
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	S.listeners += L
	var/datum/rx_state/LS = rx_of(listener)
	if(!LS.listening)
		LS.listening = list()
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	LS.listening += L
	rx_observed_adjust(source, trigger, 1)
	rx_ledger_add(source, RELK_LISTENER, listener, trigger.sig)
	return L

/// Removes the observations matching `trigger` (null: any trigger) and `listener` (null: any listener) on
/// `source`. Returns how many were removed.
/proc/legacy_unobserve(datum/source, datum/reaction/trigger, datum/listener)
	. = 0
	for(var/datum/rx_listener/L as anything in source?.rx?.listeners?.Copy())
		if(listener && L.listener != listener)
			continue
		if(trigger && L.trigger.sig != trigger.sig)
			continue
		rx_listener_remove(L)
		.++

// ---------------------------------------------------------------- change reactions

/// (holder -> (reaction or listener -> list of keys)) waiting for the drain.
GLOBAL_LIST_EMPTY(rx_pending)
/// Listener records with pending work (for cleanup on removal).
GLOBAL_LIST_EMPTY(rx_pending_listeners)
GLOBAL_VAR_INIT(rx_draining, FALSE)

/proc/rx_pend(datum/E, target, key)
	var/list/per = GLOB.rx_pending[E]
	if(!per)
		per = list()
		GLOB.rx_pending[E] = per
	var/list/keys = per[target]
	if(!keys)
		keys = list()
		per[target] = keys
		if(istype(target, /datum/rx_listener))
			GLOB.rx_pending_listeners += target
	keys |= key

/**
 * Runs the change handlers queued by publish_change(): each handler once per holder however many of its
 * reads changed, with the list of those keys. Handlers that change more state queue the next pass; a loop
 * that keeps re-queueing for one holder and reaction is reported and quarantined for that drain (RX_DRAIN_PASSES deliveries); the rest drain on. Called at the start of every
 * refresh drain, and by tests.
 */
/proc/rx_drain()
	if(GLOB.rx_draining || !(length(GLOB.rx_pending) || length(GLOB.rx_cross_jobs)))
		return
	GLOB.rx_draining = TRUE
	while(length(GLOB.rx_cross_jobs))
		var/list/job = GLOB.rx_cross_jobs[1]
		GLOB.rx_cross_jobs.Cut(1, 2)
		rx_deliver_cross(job[1], job[2], job[3], job[4], job[5])
	// (holder -> (reaction or listener -> deliveries this drain)): a pair delivered more than RX_DRAIN_PASSES times is
	// looping (its handler keeps changing what it reads) and is quarantined; every other pair keeps draining.
	var/list/deliveries = list()
	var/list/quarantined = list()
	while(length(GLOB.rx_pending))
		var/list/batch = GLOB.rx_pending
		GLOB.rx_pending = list()
		GLOB.rx_pending_listeners = list()
		for(var/datum/E as anything in batch)
			if(QDELETED(E))
				continue
			var/list/per = batch[E]
			var/list/counts = deliveries[E]
			if(!counts)
				counts = list()
				deliveries[E] = counts
			for(var/target in per)
				var/count = (counts[target] || 0) + 1
				counts[target] = count
				if(count > RX_DRAIN_PASSES)
					if(!quarantined[target] || !(E in quarantined[target]))
						LAZYADD(quarantined[target], E)
						rx_drain_report_loop(E, target)
					continue
				var/list/keys = per[target]
				try
					if(istype(target, /datum/reaction))
						var/datum/reaction/R = target
						// at_most: inside its window the keys are held for one delivery when it ends.
						if(R.at_most && !rx_at_most_admit(E, R, keys))
							continue
						rx_call_reaction(E, R, keys)
					else
						var/datum/rx_listener/L = target
						if(L.source && L.listener && !QDELETED(L.listener))
							rx_call(L.listener, L.handler, E, keys)
				catch(var/exception/e)
					stack_trace("rx_drain: [E.type]: [e] ([e.file]:[e.line])")
	GLOB.rx_draining = FALSE

/// A change reaction of `E` kept re-queueing itself past RX_DRAIN_PASSES deliveries in one drain: names the pair (the rest
/// of the drain carries on without it).
/proc/rx_drain_report_loop(datum/E, target)
	var/handler = istype(target, /datum/reaction) ? "[target:handler]" : "observer [target:handler]"
	var/message = "rx_drain: [E.type] [handler] still queued after [RX_DRAIN_PASSES] deliveries in one drain (a handler keeps changing what it reads?): quarantined for this drain, other holders carry on"
	if(GLOB.rx_drain_loop_expected)
		log_runtime(message)
	else
		stack_trace(message)

/// Set by a test that provokes the loop on purpose.
GLOBAL_VAR_INIT(rx_drain_loop_expected, FALSE)

/**
 * on_change(at_most =): TRUE when `R` may deliver to `E` now (its window since the last delivery is over), and then
 * `keys` also carries what was held. Otherwise the keys are held and one keyed timer delivers them, together, when
 * the window ends. Time is the scheduler's (world time; a test scheduler's injected time).
 */
/proc/rx_at_most_admit(datum/E, datum/reaction/R, list/keys)
	var/datum/rx_state/S = rx_of(E)
	var/now = time_scheduler().now()
	var/sig = R.sig
	var/last = S.at_most_last?[sig]
	if(!isnull(last) && now < last + R.at_most)
		var/list/held = S.at_most_held?[sig]
		if(!held)
			held = list()
			LAZYSET(S.at_most_held, sig, held)
		held |= keys
		var/timer_key = "at_most:[sig]"
		if(!after_pending(E, timer_key))
			// World time (a stasis pause must not hold a presentation refresh back); the holder is found by ref when
			// it fires, so the timer keeps nothing alive.
			after(E, last + R.at_most - now, TYPE_PROC_REF(/datum, rx_at_most_release), key = timer_key, clock = CLOCK_WORLD, with = list(sig))
		return FALSE
	LAZYSET(S.at_most_last, sig, now)
	var/list/held = S.at_most_held?[sig]
	if(held)
		// The window ended before its timer ran: this delivery takes what it held.
		keys |= held
		S.at_most_held -= sig
		if(!length(S.at_most_held))
			S.at_most_held = null
		cancel_after(E, "at_most:[sig]")
	return TRUE

/// An at_most window ended: what it held is queued for the next drain (the window is open again).
/datum/proc/rx_at_most_release(sig)
	if(QDELETED(src))
		return
	var/datum/rx_state/S = rx
	var/list/held = S?.at_most_held?[sig]
	if(!held)
		return
	S.at_most_held -= sig
	if(!length(S.at_most_held))
		S.at_most_held = null
	if(S.at_most_last)
		S.at_most_last -= sig
	var/datum/rx_table/T = rx_table_of(src)
	var/datum/reaction/R = T?.at_most_by_sig?[sig]
	if(!R)
		return
	for(var/key in held)
		rx_pend(src, R, key)

// ---------------------------------------------------------------- band crossings

/// The band of `value` among ascending `bands`: 0 below the first threshold, n at or above the n-th.
/proc/rx_band_of(value, list/bands)
	. = 0
	if(!isnum(value))
		return
	for(var/threshold in bands)
		if(value >= threshold)
			.++
		else
			break

/// Re-evaluates an on_cross read of `E` (a static reaction, or the observer `L`'s) after it changed.
/proc/rx_cross_check(datum/E, datum/reaction/R, datum/rx_listener/L)
	var/key = R.key
	if(!(key in E.vars))
		return
	var/band = rx_band_of(E.vars[key], R.bands)
	rx_crossed(E, R, band, L)

/**
 * `E`'s read of the on_cross reaction `R` is now in `band` (the Rust frame's CROSSED lands here too, with
 * the band the native watch reports). Delivers handler(band, previous) when the band differs from the last
 * one seen; urgent crossings are requested from the kernel (work.dm), others run at the next drain.
 */
/proc/rx_crossed(datum/E, datum/reaction/R, band, datum/rx_listener/L)
	var/datum/rx_state/S = rx_of(E)
	var/bands_key = "[R.sig]"
	if(!S.bands)
		S.bands = list()
	var/previous = S.bands[bands_key]
	if(isnull(previous))
		S.bands[bands_key] = band // the first sight is a baseline, not a crossing
		return
	if(previous == band)
		return
	S.bands[bands_key] = band
	if(R.urgent)
		// A static urgent reaction is a work item: kernel_urgent() dedups it per holder and the kernel's U phase runs it.
		if(L || !rx_request_cross(E, R, band, previous))
			rx_deliver_cross(E, R, band, previous, L)
	else
		GLOB.rx_cross_jobs += list(list(E, R, band, previous, L))

/// Non-urgent crossings waiting for the drain, in the order they happened (never coalesced).
GLOBAL_LIST_EMPTY(rx_cross_jobs)

/proc/rx_deliver_cross(datum/E, datum/reaction/R, band, previous, datum/rx_listener/L)
	if(QDELETED(E))
		return
	if(L)
		if(L.source && L.listener && !QDELETED(L.listener))
			rx_call(L.listener, L.handler, E, band, previous)
		return
	var/started = TICK_USAGE
	rx_call_reaction(E, R, band, previous)
	R.work?.account(TICK_USAGE_TO_MS(started))

// ---------------------------------------------------------------- operations

/// The reactions of `list_a` and (typed) `list_b` that match an op of `key` on capability `cap_type`.
/proc/rx_op_matches(list/keyed, list/typed, key, cap_type)
	. = list()
	if(key && keyed[key])
		. += keyed[key]
	if(cap_type)
		for(var/datum/reaction/R as anything in typed)
			if(ispath(cap_type, R.key))
				. += R

/**
 * Before an operation commits: runs the holder's before_op reactions for `key` (and for `cap_type` and its
 * ancestors), then observers'. Returns the first non-null return (a reason), which vetoes; null lets it
 * proceed. `ctx` is the operation context handed to each handler.
 */
/proc/rx_before_op(datum/D, key, cap_type, ctx)
	var/datum/rx_table/T = rx_table_of(D)
	if(T)
		for(var/datum/reaction/R as anything in rx_op_matches(T.before_keyed, T.before_typed, key, cap_type))
			var/veto = rx_call_reaction(D, R, ctx)
			if(!isnull(veto))
				return veto
	for(var/datum/rx_listener/L as anything in D.rx?.listeners?.Copy())
		var/datum/reaction/R = L.trigger
		if(R.kind == RXN_BEFORE_OP && rx_op_listener_matches(R, key, cap_type) && L.listener && !QDELETED(L.listener))
			var/veto = rx_call(L.listener, L.handler, D, ctx)
			if(!isnull(veto))
				return veto
	return null

/// After an operation committed: runs the holder's after_op reactions, then observers'.
/proc/rx_after_op(datum/D, key, cap_type, ctx)
	var/datum/rx_table/T = rx_table_of(D)
	if(T)
		for(var/datum/reaction/R as anything in rx_op_matches(T.after_keyed, T.after_typed, key, cap_type))
			rx_call_reaction(D, R, ctx)
	for(var/datum/rx_listener/L as anything in D.rx?.listeners?.Copy())
		var/datum/reaction/R = L.trigger
		if(R.kind == RXN_AFTER_OP && rx_op_listener_matches(R, key, cap_type) && L.listener && !QDELETED(L.listener))
			rx_call(L.listener, L.handler, D, ctx)

/proc/rx_op_listener_matches(datum/reaction/R, key, cap_type)
	if(ispath(R.key))
		return cap_type && ispath(cap_type, R.key)
	return R.key == key

// ---------------------------------------------------------------- notices

/**
 * An occurrence: something that happened once and must be heard in order (a door opened, a shot hit), as
 * opposed to a state that is. Pooled (code/datums/lifecycle/pool.dm): take_notice() takes a released one, and it is
 * released after its delivery, so handlers must not keep it. Fields go back to their initial values on release;
 * subtypes name their fields and override fill() (and reset() for what a field cannot express).
 */
/datum/notice
	/// The arguments PUBLISH passed (the default fill()). A notice is an act context (code/engine/actions/notices.dm), whose `source` is the
	/// publisher for the legacy handlers and the activation's source for the hooks.
	var/list/data

/// Sets the notice up from PUBLISH's arguments.
/datum/notice/proc/fill(...)
	data = args.Copy()

/// The notices waiting behind the delivery in progress: (source, notice) pairs in publish order.
GLOBAL_LIST_EMPTY(rx_notice_queue)
GLOBAL_VAR_INIT(rx_notice_delivering, FALSE)

/// A notice of `type` taken from its pool and filled from the arguments after it. PUBLISH's helper: the
/// notice is released by publish() once delivered.
/proc/take_notice(type, ...)
	RETURN_TYPE(/datum/notice)
	var/datum/notice/N = take(type)
	N.fill(arglist(length(args) > 1 ? args.Copy(2) : list()))
	return N

/// TRUE when a static reaction of E's type, or an observer of E, wants notices of `type`.
/proc/rx_wants_notice(datum/E, type)
	var/list/dynamic = E.rx?.notice_types
	if(dynamic)
		for(var/wanted in dynamic)
			if(ispath(type, wanted))
				return TRUE
	var/datum/rx_table/T = GLOB.rx_tables?[E.type]
	if(isnull(T))
		T = rx_table_build(E)
	if(!T || !length(T.notices))
		return FALSE
	var/cached = T.notice_cache[type]
	if(isnull(cached))
		cached = FALSE
		for(var/datum/reaction/R as anything in T.notices)
			if(ispath(type, R.key))
				cached = TRUE
				break
		T.notice_cache[type] = cached
	return cached

/**
 * Delivers `N` (from take_notice) to the holder's on_notice reactions and observers, in that order, each
 * in registration order. Occurrences are never coalesced or dropped: one published while another is
 * being delivered (from a handler) is queued behind it and delivered, in order, before this returns to the
 * outermost caller. A chain longer than RX_NOTICE_LIMIT is reported and cut.
 */
/proc/publish(datum/E, datum/notice/N)
	if(!E || !N)
		return

	N.source = E
	if(GLOB.rx_notice_delivering)
		GLOB.rx_notice_queue += list(list(E, N))
		return
	GLOB.rx_notice_delivering = TRUE
	var/delivered = 0
	rx_deliver_notice(E, N)
	while(length(GLOB.rx_notice_queue))
		var/list/next = GLOB.rx_notice_queue[1]
		GLOB.rx_notice_queue.Cut(1, 2)
		if(++delivered > RX_NOTICE_LIMIT)
			stack_trace("publish: more than [RX_NOTICE_LIMIT] notices chained from one delivery (a handler republishes what it hears?); dropping [length(GLOB.rx_notice_queue) + 1]")
			for(var/list/rest as anything in GLOB.rx_notice_queue)
				var/datum/notice/dropped = rest[2]
				dropped.release()
			GLOB.rx_notice_queue.Cut()
			var/datum/notice/cut = next[2]
			cut.release()
			break
		rx_deliver_notice(next[1], next[2])
	GLOB.rx_notice_delivering = FALSE

/proc/rx_deliver_notice(datum/E, datum/notice/N)
	rx_deliver_notice_to(E, N)
	notice_deliver_hooks(E, N, ACT_COMMITTED) // the hooks of the engine (code/engine/actions) hear a legacy publish too
	N.release()

/// The legacy half of a delivery: E's on_notice() reactions and observers, without releasing N.
/proc/rx_deliver_notice_to(datum/E, datum/notice/N)
	if(!QDELETED(E))
		var/datum/rx_table/T = rx_table_of(E)
		if(T)
			for(var/datum/reaction/R as anything in T.notices)
				if(!istype(N, R.key))
					continue
				var/started = TICK_USAGE
				var/faulted = FALSE
				try
					rx_call_reaction(E, R, N)
				catch(var/exception/e)
					faulted = TRUE
					stack_trace("notice [N.type] handler [R.handler] on [E.type]: [e] ([e.file]:[e.line])")
				R.work?.account(TICK_USAGE_TO_MS(started), faulted) // per-reaction cost; delivery stays synchronous and in order
		for(var/datum/rx_listener/L as anything in E.rx?.listeners?.Copy())
			var/datum/reaction/R = L.trigger
			if(R.kind != RXN_NOTICE || !istype(N, R.key) || !L.listener || QDELETED(L.listener))
				continue
			try
				rx_call(L.listener, L.handler, E, N)
			catch(var/exception/e2)
				stack_trace("notice [N.type] observer [L.handler] on [L.listener.type]: [e2] ([e2.file]:[e2.line])")
