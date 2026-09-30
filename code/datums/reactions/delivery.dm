// Delivery of reactions: change drains, operations, notices, band crossings, periodic work and observe().
// The contracts are stated in reactions.dm.

/// Calls `handler` (a PROC_REF on `holder`, or a /proc path) with the rest of the arguments.
/proc/rx_call(datum/holder, handler, ...)
	var/list/rest = length(args) > 2 ? args.Copy(3) : list()
	if(om_proc_is_global(handler))
		return call(handler)(arglist(rest))
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
/proc/observe(datum/source, datum/reaction/trigger, datum/listener, handler)
	if(!source || !listener || !istype(trigger) || QDELING(source) || QDELING(listener))
		return null
	for(var/datum/rx_listener/known as anything in source.rx?.listeners)
		if(known.listener == listener && known.trigger.sig == trigger.sig && known.handler == handler)
			return known
	var/datum/rx_listener/L = new
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	L.source = source
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
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
/proc/unobserve(datum/source, datum/reaction/trigger, datum/listener)
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
 * that does not settle in RX_DRAIN_PASSES passes is reported and dropped. Called at the start of every
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
	var/passes = 0
	while(length(GLOB.rx_pending))
		if(++passes > RX_DRAIN_PASSES)
			stack_trace("rx_drain: change reactions still queued after [RX_DRAIN_PASSES] passes (a handler keeps changing what it reads?): [length(GLOB.rx_pending)] holders")
			GLOB.rx_pending.Cut()
			GLOB.rx_pending_listeners.Cut()
			break
		var/list/batch = GLOB.rx_pending
		GLOB.rx_pending = list()
		GLOB.rx_pending_listeners = list()
		for(var/datum/E as anything in batch)
			if(QDELETED(E))
				continue
			var/list/per = batch[E]
			for(var/target in per)
				var/list/keys = per[target]
				try
					if(istype(target, /datum/reaction))
						var/datum/reaction/R = target
						rx_call(E, R.handler, keys)
					else
						var/datum/rx_listener/L = target
						if(L.source && L.listener && !QDELETED(L.listener))
							rx_call(L.listener, L.handler, E, keys)
				catch(var/exception/e)
					stack_trace("rx_drain: [E.type]: [e] ([e.file]:[e.line])")
	GLOB.rx_draining = FALSE

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
		// A static urgent reaction is a work item: request_urgent() dedups it per holder and the kernel's U phase runs it.
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
	rx_call(E, R.handler, band, previous)
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
			var/veto = rx_call(D, R.handler, ctx)
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
			rx_call(D, R.handler, ctx)
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
	parent_type = /datum/pooled
	/// Who published it.
	var/datum/source
	/// The arguments PUBLISH passed (the default fill()).
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
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
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
	if(!QDELETED(E))
		var/datum/rx_table/T = rx_table_of(E)
		if(T)
			for(var/datum/reaction/R as anything in T.notices)
				if(!istype(N, R.key))
					continue
				var/started = TICK_USAGE
				var/faulted = FALSE
				try
					rx_call(E, R.handler, N)
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
	N.release()
