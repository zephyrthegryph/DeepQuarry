// Timers: the owner's timer store and the deadline that fires it (doc/rewrite/framework_gaps.md C1; doc/rewrite/final_api.html section 3).
//
// timer_schedule(E, delay, proc, args...) is a one-shot call on the deadline wheel (after(), after_if_alive() and the keyed forms are in after.dm):
//   - owned by E: cancelled when E is deleted (entity_teardown_rest drops rec.timers);
//   - on E's clock: E's timer clock (timer_clock(), bio for living mobs, machine for machinery) scales it, and suspension or stasis
//     pauses it;
//   - weak: every datum argument is captured as a handle (handles.dm) and resolved when the timer fires. A gone argument arrives as null and
//     the call still runs (cleanup such as vend_ready = TRUE always happens; counted in sched.timers_nulled and logged). after_if_alive()
//     opts a pure effect out: its call is dropped instead (counted in sched.timers_dropped).
// No datum per timer: a timer is six slots in the owner's record (OM_TIMER_STRIDE, code/__defines/engine/time.dm) and the owner has one
// deadline on the wheel (the soonest of its timers), as tasks do. The list is sorted by id (binary search finds a timer); a per-owner
// min-heap of (due, id) pairs, rec.timer_heap, finds the next due timer in O(log n) with lazy deletion (cancelled timers leave stale heap
// entries that are skipped when they surface and compacted when they outnumber the live ones).
//
// The behaviour-keyed deadline underneath is deadline_deadline() (code/datums/om/deadline.dm).

/datum/scheduler_record/var/list/timers
/// The soonest due time in rec.timers (timer-clock ds), or null with no timers. Kept in step by
/// every add/remove so arming the wheel never rescans the list.
/datum/scheduler_record/var/timer_soonest
/// Timer ids, per record.
/datum/scheduler_record/var/timer_seq = 0
/// A binary min-heap of (due, id) pairs over rec.timers (OM_TIMER_HEAP_STRIDE numbers per entry): the next due timer is its root. Entries are
/// deleted lazily: one whose id is no longer in rec.timers is stale and dropped when it reaches the root. Null with no timers.
/datum/scheduler_record/var/list/timer_heap
/// The record's timer clock: list(local ds, settled at (sched ds), rate). Null until a timer.
/datum/scheduler_record/var/list/tclock

/// The clock domain (CLOCK_*) E's timers and task steps follow, or null for real time.
/datum/proc/timer_clock()
	return null


// ---------------------------------------------------------------- global owner

/// The owner of timers that belong to no entity (round events, client real time). One per
/// scheduler, so tests get their own. Never deleted.
/datum/timer_owner

/datum/time_scheduler/var/datum/timer_owner/global_owner
/datum/time_scheduler/var/timers_dropped = 0
/// Timers that ran with at least one deleted argument passed as null (the default, timer_schedule()/after()).
/datum/time_scheduler/var/timers_nulled = 0
/// Deleted arguments resolve_captured_value() replaced with null during the current resolution.
GLOBAL_VAR_INIT(om_resolve_nulled, 0)

/proc/timer_global_owner()
	RETURN_TYPE(/datum/timer_owner)
	var/datum/time_scheduler/sched = time_scheduler()
	if(!sched.global_owner)
		sched.global_owner = sched.make_timer_owner()
		scheduler_record_of(sched.global_owner)
	return sched.global_owner
// ---------------------------------------------------------------- timers

/// Runs `proc` after `delay` deciseconds of E's timer clock. A
/// global proc (/proc/x) gets `call_args`; a type proc is called on E. Returns the timer id
/// (for timer_cancel()), or 0 if E or an argument is already gone. E null: the global owner.
/proc/timer_schedule(datum/E, delay, proc_ref, ...)
	return rx_after(E, delay, proc_ref, null, CLOCK_OWN, length(args) > 3 ? args.Copy(4) : null, FALSE)

/// timer_schedule()'s body. nulls_for_gone (after()'s keeps_dead = TRUE): a captured datum argument
/// deleted before the timer fires, or already deleted when it is scheduled, is passed as null and the
/// call runs. FALSE (the default): the call is dropped, and an already-deleted argument is
/// refused up front (returns 0).
/proc/timer_schedule_list(datum/E, delay, proc_ref, list/call_args, nulls_for_gone = FALSE, owner_first = FALSE)
	if(isnull(E))
		E = timer_global_owner()
	if(!own_guard(E, null, "a timer ([proc_ref])")) // the one teardown guard (guard.dm)
		return 0
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	if(!rec || rec.torn_down)
		return 0
	var/list/captured = null
	var/list/positions = null
	if(call_args)
		var/list/capture = capture_args(call_args, nulls_for_gone)
		if(!capture)
			return 0
		captured = capture[1]
		positions = capture[2]
	var/local = timer_local(rec)
	var/id = ++rec.timer_seq
	var/due = local + max(delay, 0)
	LAZYADD(rec.timers, list(id, due, proc_ref, captured, positions, (deferred_proc_is_global(proc_ref) ? OM_TIMER_GLOBAL : 0) | (nulls_for_gone ? OM_TIMER_NULLS_FOR_GONE : 0) | (owner_first ? OM_TIMER_OWNER_FIRST : 0)))
	timer_heap_push(rec, due, id)
	if(isnull(rec.timer_soonest) || due < rec.timer_soonest)
		rec.timer_soonest = due
		timers_arm(rec)
	return id

// ---------------------------------------------------------------- timer slots (legacy)
//
// LEGACY wrappers over the keyed after() (code/datums/capabilities/timed.dm): a slot is an after() key on the
// owner, a TIMER relation, so fire, cancel and owner teardown leave it empty by construction and scheduling into
// an occupied slot replaces the pending timer. Nothing declares a slot (OWN_TIMER is gone).
//	after_slot(E, "name", d, proc, args...)   ->  after(E, d, proc, key = "name", with = list(args...))
//	timer_slot_pending(E, "name")           ->  after_pending(E, "name")
//	timer_cancel_slot(E, "name")            ->  cancel_after(E, "name")
//	timer_slot_left(E, "name")              ->  after_left(E, "name")

/// Schedules `proc_ref` after `delay` into E's slot `slot` (an after() key), replacing any timer pending there.
/// Returns TRUE if scheduled. E null: the global owner.
/proc/after_slot(datum/E, slot, delay, proc_ref, ...)
	return !!rx_after(E, delay, proc_ref, slot, CLOCK_OWN, length(args) > 4 ? args.Copy(5) : null, FALSE)

/// Cancels whatever is pending in E's slot `slot`. Returns TRUE if a timer was pending.
/proc/timer_cancel_slot(datum/E, slot)
	return cancel_after(E, slot)

/// TRUE while a timer is pending in E's slot `slot`.
/proc/timer_slot_pending(datum/E, slot)
	return after_pending(E, slot)

/// Deciseconds of E's timer clock left on the timer in slot `slot`, or null when none is pending.
/proc/timer_slot_left(datum/E, slot)
	if(!after_pending(E, slot))
		return null
	return after_left(E, slot)

/// TRUE when `proc_ref` is a global proc (/proc/x), FALSE for a type proc. Decided once, when a
/// deferred call is recorded, so firing never stringifies the proc.
/proc/deferred_proc_is_global(proc_ref)
	// Memoized per proc ref: stringifying a proc path costs microseconds, and reaction delivery (rx_call) asks on
	// every call. The set of proc refs is the code's, so the table is bounded.
	var/static/list/answers = list()
	if(isnull(proc_ref))
		return FALSE
	. = answers[proc_ref]
	if(isnull(.))
		. = answers[proc_ref] = (copytext("[proc_ref]", 1, 7) == "/proc/")

/// The position in rec.timers of timer `id`, or 0. Binary search: the list is sorted by id.
/proc/timer_index(datum/scheduler_record/rec, id)
	var/list/T = rec?.timers
	if(!T || !isnum(id))
		return 0
	var/lo = 1
	var/hi = length(T) / OM_TIMER_STRIDE
	while(lo <= hi)
		var/mid = round((lo + hi) / 2)
		var/at = (mid - 1) * OM_TIMER_STRIDE + 1
		var/mid_id = T[at]
		if(mid_id == id)
			return at
		if(mid_id < id)
			lo = mid + 1
		else
			hi = mid - 1
	return 0

/// Removes the timer at position `at`, keeping timer_soonest right (a rescan only when the
/// soonest one leaves). Does not arm the wheel: the caller does, once.
/proc/timer_remove_at(datum/scheduler_record/rec, at)
	var/list/T = rec.timers
	var/due = T[at + 1]
	T.Cut(at, at + OM_TIMER_STRIDE)
	if(!length(T))
		timers_clear(rec)
		return TRUE
	if(due <= rec.timer_soonest)
		timers_recompute_soonest(rec)
		return TRUE
	return FALSE

/// The soonest due time of rec.timers, read from the heap root (stale entries above it are dropped). O(log n) amortized, never a scan.
/proc/timers_recompute_soonest(datum/scheduler_record/rec)
	timer_heap_clean_top(rec)
	var/list/H = rec.timer_heap
	rec.timer_soonest = length(H) ? H[1] : null

/// Drops every timer of the record (its owner's teardown, or its last timer leaving).
/proc/timers_clear(datum/scheduler_record/rec)
	rec.timers = null
	rec.timer_heap = null
	rec.timer_soonest = null

// ---- the due-order heap (rec.timer_heap) ----

/// Adds timer `id` due at `due` to the heap. A heap that has grown past the live timers (cancellations leave stale entries) is rebuilt first.
/proc/timer_heap_push(datum/scheduler_record/rec, due, id)
	var/list/H = rec.timer_heap
	if(!H)
		rec.timer_heap = H = list()
	else if(length(H) / OM_TIMER_HEAP_STRIDE > 2 * (length(rec.timers) / OM_TIMER_STRIDE) + OM_TIMER_HEAP_SLACK)
		timer_heap_rebuild(rec)
		H = rec.timer_heap
	H += due
	H += id
	var/child = length(H) / OM_TIMER_HEAP_STRIDE
	while(child > 1)
		var/parent = round(child / 2)
		var/c = (child - 1) * OM_TIMER_HEAP_STRIDE + 1
		var/p = (parent - 1) * OM_TIMER_HEAP_STRIDE + 1
		if(H[c] > H[p] || (H[c] == H[p] && H[c + 1] > H[p + 1]))
			break
		var/due_c = H[c]
		var/id_c = H[c + 1]
		H[c] = H[p]
		H[c + 1] = H[p + 1]
		H[p] = due_c
		H[p + 1] = id_c
		child = parent

/// Removes the root of the heap (the earliest (due, id) pair).
/proc/timer_heap_pop(datum/scheduler_record/rec)
	var/list/H = rec.timer_heap
	var/count = length(H) / OM_TIMER_HEAP_STRIDE
	if(count <= 1)
		rec.timer_heap = null
		return
	var/last = (count - 1) * OM_TIMER_HEAP_STRIDE + 1
	H[1] = H[last]
	H[2] = H[last + 1]
	H.Cut(last, last + OM_TIMER_HEAP_STRIDE)
	count--
	var/parent = 1
	while(TRUE)
		var/left = parent * 2
		if(left > count)
			break
		var/best = left
		var/b = (best - 1) * OM_TIMER_HEAP_STRIDE + 1
		var/right = left + 1
		if(right <= count)
			var/r = (right - 1) * OM_TIMER_HEAP_STRIDE + 1
			if(H[r] < H[b] || (H[r] == H[b] && H[r + 1] < H[b + 1]))
				best = right
				b = r
		var/p = (parent - 1) * OM_TIMER_HEAP_STRIDE + 1
		if(H[p] < H[b] || (H[p] == H[b] && H[p + 1] < H[b + 1]))
			break
		var/due_p = H[p]
		var/id_p = H[p + 1]
		H[p] = H[b]
		H[p + 1] = H[b + 1]
		H[b] = due_p
		H[b + 1] = id_p
		parent = best

/// Drops stale entries (timers cancelled or fired since they were pushed) from the root until it names a live timer.
/proc/timer_heap_clean_top(datum/scheduler_record/rec)
	var/list/H = rec.timer_heap
	while(length(H))
		if(rec.timers && timer_index(rec, H[2]))
			return
		timer_heap_pop(rec)
		H = rec.timer_heap

/// Rebuilds the heap from the live timers (a heap that outgrew them through cancellations, or one lost to a bad write).
/proc/timer_heap_rebuild(datum/scheduler_record/rec)
	rec.timer_heap = null
	var/list/T = rec.timers
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		var/list/H = rec.timer_heap
		if(!H)
			rec.timer_heap = H = list()
		H += T[i + 1]
		H += T[i]
		var/child = length(H) / OM_TIMER_HEAP_STRIDE
		while(child > 1)
			var/parent = round(child / 2)
			var/c = (child - 1) * OM_TIMER_HEAP_STRIDE + 1
			var/p = (parent - 1) * OM_TIMER_HEAP_STRIDE + 1
			if(H[c] > H[p] || (H[c] == H[p] && H[c + 1] > H[p + 1]))
				break
			var/due_c = H[c]
			var/id_c = H[c + 1]
			H[c] = H[p]
			H[c + 1] = H[p + 1]
			H[p] = due_c
			H[p + 1] = id_c
			child = parent

/// Cancels timer `id` on E. Always safe: nothing is suspended inside a timer.
/proc/timer_cancel(datum/E, id)
	var/datum/owner = E || timer_global_owner()
	var/datum/scheduler_record/rec = owner.om_rec
	var/at = timer_index(rec, id)
	if(!at)
		return FALSE
	if(timer_remove_at(rec, at))
		timers_arm(rec)
	return TRUE

/// How many timer_schedule() timers E has pending.
/datum/time_scheduler/proc/timer_count(datum/E)
	return length(E?.om_rec?.timers) / OM_TIMER_STRIDE

/proc/timer_pending(datum/E, id)
	var/datum/owner = E || timer_global_owner()
	return timer_index(owner.om_rec, id) != 0

/// Deciseconds of E's timer clock left on timer `id`, or null.
/proc/timer_left(datum/E, id)
	var/datum/owner = E || timer_global_owner()
	var/datum/scheduler_record/rec = owner.om_rec
	var/at = timer_index(rec, id)
	if(!at)
		return null
	return max(rec.timers[at + 1] - timer_local(rec), 0)

/// The rate of E's timer clock: 0 while suspended, else its clock domain's rate.
/proc/timer_rate(datum/scheduler_record/rec)
	if(entity_suspended(rec))
		return 0
	var/clock_id = rec.owner?.timer_clock()
	if(!clock_id)
		return 1
	var/datum/clock_definition/C = definition_registry().clock_by_id[clock_id]
	return C ? contribution_clock_rate(rec, C.idx) : 1

/proc/timer_local(datum/scheduler_record/rec)
	var/list/K = rec.tclock
	if(!K)
		rec.tclock = K = list(0, rec.sched.now(), timer_rate(rec))
	return K[1] + (rec.sched.now() - K[2]) * K[3]

/// A clock effect or suspension changed on `rec`: fold elapsed time in at the old rate,
/// take the new one, and move the wheel deadline.
/proc/timers_rate_changed(datum/scheduler_record/rec)
	var/list/K = rec.tclock
	if(!K)
		return
	var/new_rate = timer_rate(rec)
	if(new_rate == K[3])
		return
	K[1] = timer_local(rec)
	K[2] = rec.sched.now()
	K[3] = new_rate
	timers_arm(rec)

/// Rescans rec.timers for the soonest due time and arms the wheel for it.
/proc/timers_reschedule(datum/scheduler_record/rec)
	timers_recompute_soonest(rec)
	timers_arm(rec)

/// Arms (or cancels) the owner's wheel deadline for the cached timer_soonest. O(1) in timers.
/proc/timers_arm(datum/scheduler_record/rec)
	if(rec.torn_down || !rec.owner)
		return
	var/datum/scheduled_behaviour/B = definition_registry().timer_behaviour
	var/soonest = rec.timer_soonest
	if(!rec.timers || isnull(soonest))
		deadline_cancel_after(rec.owner, B)
		return
	var/rate = rec.tclock[3]
	if(rate <= 0)
		deadline_cancel_after(rec.owner, B)
		return
	deadline_deadline(rec.owner, CEILING(max(soonest - timer_local(rec), 0) / rate, 1), B)

/// Calls a stored proc: a global proc with the arguments, or a type proc on `E`.
/// `is_global`: deferred_proc_is_global(proc_ref), when the caller recorded it; null decides here.
/proc/deferred_invoke(datum/E, proc_ref, list/call_args, is_global = null)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(E && GLOB.om_traced[E])
		GLOB.om_traced[E]++
#endif
	if(isnull(is_global))
		is_global = deferred_proc_is_global(proc_ref)
	if(is_global)
		return call(proc_ref)(arglist(call_args || list()))
	return call(E, proc_ref)(arglist(call_args || list()))

// ---------------------------------------------------------------- sleep guard

/datum/time_scheduler/var/callees_slept = 0
/// Test hook: while set, a sleeping callee is counted and logged but does not fail the test.
GLOBAL_VAR_INIT(om_expect_sleep, FALSE)

/// Runs a scheduler callback without letting it stall the scheduler. The call goes through
/// a waitfor = FALSE trampoline: if the callee sleeps, control comes back here at once, the
/// rest of the callee finishes on its own later, and the sleep is reported. Returns the
/// callee's return value, or OM_CALLEE_SLEPT. Runtimes re-throw as before.
/proc/deferred_guarded_call(datum/E, proc_ref, list/call_args, is_global = null)
	var/list/state = list(TRUE, null, null, FALSE) // running, result, exception, abandoned
	deferred_trampoline(state, E, proc_ref, call_args, is_global)
	if(state[3])
		throw state[3]
	if(!state[1])
		return state[2]
	// The callee slept: nobody reads state[3] any more, so a runtime it raises
	// later must be reported by the trampoline itself (see deferred_trampoline()).
	state[4] = TRUE
	var/datum/time_scheduler/sched = time_scheduler()
	sched.callees_slept++
	log_runtime("OM: SLEPT [proc_ref] on [E]")
#ifdef UNIT_TESTS
	if(!GLOB.om_expect_sleep && GLOB.current_test)
		var/datum/unit_test/test = GLOB.current_test
		test.Fail("OM: SLEPT [proc_ref] on [E]: scheduler callbacks must not sleep")
#endif
	return OM_CALLEE_SLEPT

/proc/deferred_trampoline(list/state, datum/E, proc_ref, list/call_args, is_global = null)
	set waitfor = FALSE // ALLOW(scheduler): OM sleep-guard trampoline (detects callees that sleep)
	try
		if(E)
			state[2] = deferred_invoke(E, proc_ref, call_args, is_global)
		else
			state[2] = call(proc_ref)(arglist(call_args || list()))
	catch(var/exception/e)
		// Still synchronous: deferred_guarded_call() rethrows it. After a sleep the
		// caller is gone and would never look, so report it here -- a silent
		// swallow here once hid a double-qdel CRASH and hung a test batch.
		if(state[4])
			dq_report_caught(e, "OM trampoline (after sleep) [proc_ref] on [E]")
		else
			state[3] = e
	state[1] = FALSE


/datum/scheduled_behaviour/internal/timers
	name = "om: timers"
	lane = LANE_URGENT

/datum/scheduled_behaviour/internal/timers/on_deadline(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec?.timers)
		return
	var/local = timer_local(rec) + 0.001
	// Due timers leave the list before they run, soonest first: a timer that cancels
	// another, or schedules a new one, sees a consistent list.
	while(rec.timers && !rec.torn_down)
		// The next due timer is the heap root: O(log n), not a scan of the owner's whole list per pop.
		timer_heap_clean_top(rec)
		var/list/H = rec.timer_heap
		if(!length(H))
			if(rec.timers) // timers with no heap: it was lost, so it is rebuilt once and the pass goes on
				timer_heap_rebuild(rec)
				H = rec.timer_heap
			if(!length(H))
				break
		if(H[1] > local)
			break
		var/list/T = rec.timers
		var/best = timer_index(rec, H[2])
		timer_heap_pop(rec)
		if(!best)
			continue
		var/proc_ref = T[best + 2]
		var/list/captured = T[best + 3]
		var/list/positions = T[best + 4]
		var/timer_flags = T[best + 5]
		var/is_global = !!(timer_flags & OM_TIMER_GLOBAL)
		T.Cut(best, best + OM_TIMER_STRIDE)
		if(!length(T))
			timers_clear(rec)
		var/saved_nulled = GLOB.om_resolve_nulled
		GLOB.om_resolve_nulled = 0
		var/resolved = FALSE
		try
			resolved = resolve_captured(captured, positions, !!(timer_flags & OM_TIMER_NULLS_FOR_GONE))
		catch(var/exception/resolve_fault)
			GLOB.om_resolve_nulled = saved_nulled
			throw resolve_fault
		var/nulled = GLOB.om_resolve_nulled
		GLOB.om_resolve_nulled = saved_nulled
		if(!resolved)
			rec.sched.timers_dropped++
			log_qdel("OM: dropped timer [proc_ref] on [E] ([E.type]): a captured argument was deleted before it fired (the default drop; keeps_dead = TRUE lets it run with null)")
			continue
		if(nulled)
			rec.sched.timers_nulled++
			log_qdel("OM: timer [proc_ref] on [E] ([E.type]) runs with [nulled] deleted argument(s) passed as null")
		if(timer_flags & OM_TIMER_OWNER_FIRST)
			captured = captured ? list(E) + captured : list(E)
		CHURN_COUNT(timers, "[E.type] [proc_ref]")
		try
			deferred_guarded_call(E, proc_ref, captured, is_global)
		catch(var/exception/e)
			dq_report_caught(e, "om timer [proc_ref] on [E]")
		// A timer is a dispatched call: its owner may have state_changed (dx_conventions.md §1). Its derived procs
		// re-run; no channel is raised (refresh_dispatched()).
		if(!istype(E, /datum/timer_owner))
			refresh_dispatched(E)
	timers_reschedule(rec)

// ---------------------------------------------------------------- keyed timers
//
// SStimer's TIMER_UNIQUE and TIMER_OVERRIDE, as the key they really were: the owner, the
// proc and its arguments. No extra state: the owner's timer list is the index. These live on
// the scheduler; call them through the
// om_after_unique() / om_after_replace() / om_cancel_calls() / om_timer_count() macros.

/// The position in rec.timers of a pending timer calling `proc_ref` with `call_args`, or 0.
/datum/time_scheduler/proc/timer_find(datum/scheduler_record/rec, proc_ref, list/call_args)
	var/list/T = rec?.timers
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		if(T[i + 2] != proc_ref)
			continue
		var/list/captured = T[i + 3]
		if(length(captured) != length(call_args))
			continue
		var/same = TRUE
		for(var/j in 1 to length(call_args))
			var/arg = call_args[j]
			if(captured[j] != arg && !captured_matches(captured[j], arg))
				same = FALSE
				break
		if(same)
			return i
	return 0

/// TRUE when a captured argument is what capturing `arg` now would give (datums as handles).
/proc/captured_matches(captured_value, arg)
	var/list/result = capture_value(arg, 0)
	if(!result)
		return FALSE
	var/now = result[1]
	if(!islist(now) || !islist(captured_value))
		return now == captured_value
	return json_encode(now) == json_encode(captured_value)

/// timer_schedule(), unless the same call (owner, proc, arguments) is already pending: then
/// nothing, and the pending timer's id is returned. (Was TIMER_UNIQUE.)
/datum/time_scheduler/proc/after_unique(datum/E, delay, proc_ref, ...)
	if(isnull(E))
		E = timer_global_owner()
	var/list/call_args = length(args) > 3 ? args.Copy(4) : list()
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	var/i = timer_find(rec, proc_ref, call_args)
	if(i)
		return rec.timers[i]
	return timer_schedule(arglist(list(E, delay, proc_ref) + call_args))

/// timer_schedule(), replacing the same call if it is pending: the delay restarts. (Was
/// TIMER_UNIQUE | TIMER_OVERRIDE.)
/datum/time_scheduler/proc/after_replace(datum/E, delay, proc_ref, ...)
	if(isnull(E))
		E = timer_global_owner()
	var/list/call_args = length(args) > 3 ? args.Copy(4) : list()
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	var/i = timer_find(rec, proc_ref, call_args)
	if(i)
		timer_cancel(E, rec.timers[i])
	return timer_schedule(arglist(list(E, delay, proc_ref) + call_args))

/// Cancels every pending timer on E that calls `proc_ref`, whatever its arguments.
/datum/time_scheduler/proc/cancel_calls(datum/E, proc_ref)
	var/datum/scheduler_record/rec = E?.om_rec
	var/list/T = rec?.timers
	. = 0
	for(var/i = length(T) - OM_TIMER_STRIDE + 1, i >= 1, i -= OM_TIMER_STRIDE)
		if(T[i + 2] == proc_ref)
			T.Cut(i, i + OM_TIMER_STRIDE)
			.++
	if(.)
		if(!length(T))
			timers_clear(rec)
		timers_reschedule(rec)

// ---------------------------------------------------------------- real time
//
// Client-facing delays (a flicked overlay, a UI fade) follow the wall clock, not game time,
// which slows under time dilation. They go on the global owner. The wheel runs in game
// time, so a real-time timer is due at a REALTIMEOFDAY, and re-arms for what is left when the
// wheel fires it early. (Was TIMER_CLIENT_TIME.)

/// Runs `proc` after `delay` deciseconds of real time, on the global owner. Arguments are
/// captured weakly, as timer_schedule() does. A global proc gets the arguments; a type proc runs on
/// the first argument and gets the rest.
/proc/timer_schedule_realtime(delay, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : list()
	return timer_schedule(arglist(list(null, delay, /proc/timer_realtime_fire, REALTIMEOFDAY + max(delay, 0), proc_ref) + call_args))

/proc/timer_realtime_fire(due, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : list()
	var/left = due - REALTIMEOFDAY
	if(left > 0)
		timer_schedule(arglist(list(null, left, /proc/timer_realtime_fire, due, proc_ref) + call_args))
		return
	if(deferred_proc_is_global(proc_ref))
		call(proc_ref)(arglist(call_args))
	else if(length(call_args))
		// A type proc: the first argument is the datum it runs on.
		var/target = call_args[1]
		if(target) // a client that has disconnected is null
			call(target, proc_ref)(arglist(call_args.Copy(2)))


/// The timer owner is extensible so downstream compatibility-owned relations survive.
/datum/time_scheduler/proc/make_timer_owner()
	return new /datum/timer_owner
