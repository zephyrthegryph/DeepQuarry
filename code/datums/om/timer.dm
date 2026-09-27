// Object-model core: one scheduler for deferred work (doc/rewrite/object_model_core.md §4.11).
//
// om_after(E, delay, proc, args...) is a one-shot call on the OM deadline wheel:
//   - owned by E: cancelled when E is deleted (om_teardown_rest drops rec.timers);
//   - on E's clock: E's timer clock (om_timer_clock(), bio for living mobs, machine for
//     machinery) scales it, and suspension or stasis pauses it;
//   - weak: every datum argument is captured as an OM handle and resolved when the timer
//     fires. If any is gone the call is dropped (counted in sched.timers_dropped).
// No datum per timer: a timer is five slots in the owner's record, and the owner has one
// deadline on the wheel (the soonest of its timers), as tasks and rates do.
//
// The behaviour-keyed deadline underneath is om_deadline() (deadline.dm).
//
// OM handles: om_handle(D) -> "id:gen", om_resolve(h) -> D or null. The same model as the
// Rust core's handles: a slot table with a generation per slot, no per-target datum. A
// deleted datum's slot is freed and its generation bumped, so a stale handle never
// resolves to whatever reuses the id.

/// Stride of rec.timers: id, due (timer-clock ds), proc, args, handle positions.
#define OM_TIMER_STRIDE 5

/datum/om/rec/var/list/timers
/// Timer ids, per record.
/datum/om/rec/var/timer_seq = 0
/// The record's timer clock: list(local ds, settled at (sched ds), rate). Null until a timer.
/datum/om/rec/var/list/tclock

/// The clock domain (CLOCK_*) E's timers and task steps follow, or null for real time.
/datum/proc/om_timer_clock()
	return null

/mob/living/om_timer_clock()
	return CLOCK_BIO

/obj/machinery/om_timer_clock()
	return CLOCK_MACHINE

// ---------------------------------------------------------------- global owner

/// The owner of timers that belong to no entity (round events, client real time). One per
/// scheduler, so tests get their own. Never deleted.
/datum/om/global_owner

/datum/om/scheduler/var/datum/om/global_owner/global_owner
/datum/om/scheduler/var/timers_dropped = 0

/proc/om_global_owner()
	RETURN_TYPE(/datum/om/global_owner)
	var/datum/om/scheduler/sched = om_scheduler()
	if(!sched.global_owner)
		sched.global_owner = new
		om_rec_of(sched.global_owner)
	return sched.global_owner

// ---------------------------------------------------------------- handles
//
// A slot table: slot id -> the datum's \ref text, plus a generation per slot.
// The table holds text, never the datum, so a handle doesn't keep its target
// alive: a datum BYOND collects without qdel() (a dropped species, a stack
// canary) simply stops resolving, like one that was qdel()ed.

GLOBAL_LIST_EMPTY(om_handle_slots)
GLOBAL_LIST_EMPTY(om_handle_gens)
GLOBAL_LIST_EMPTY(om_handle_free)

/// The datum's handle slot, 0 until om_handle() is first called on it.
/datum/var/tmp/om_hid = 0

/// A handle to `D`: "id:gen". Null for a deleted datum or a non-datum.
/proc/om_handle(datum/D)
	if(!isdatum(D) || QDELETED(D))
		return null
	var/list/slots = GLOB.om_handle_slots
	var/list/gens = GLOB.om_handle_gens
	var/id = D.om_hid
	if(!id)
		var/list/free = GLOB.om_handle_free
		if(length(free))
			id = free[length(free)]
			free.len--
		else
			slots.len++
			gens.len++
			id = length(slots)
			gens[id] = 0
		slots[id] = REF(D)
		D.om_hid = id
	return "[id]:[gens[id]]"

/// The datum a handle names, or null if it has been deleted (whatever now uses its id).
/proc/om_resolve(h)
	if(!istext(h))
		return null
	var/sep = findtext(h, ":")
	if(!sep)
		return null
	var/id = text2num(copytext(h, 1, sep))
	var/list/slots = GLOB.om_handle_slots
	if(!id || id > length(slots))
		return null
	if(GLOB.om_handle_gens[id] != text2num(copytext(h, sep + 1)))
		return null
	var/ref = slots[id]
	if(!ref)
		return null
	var/datum/D = locate(ref)
	if(!isdatum(D) || D.om_hid != id)
		// Collected without qdel(); a new datum may even have the ref now. Free the slot.
		slots[id] = null
		GLOB.om_handle_gens[id]++
		GLOB.om_handle_free += id
		return null
	if(QDELETED(D))
		return null
	return D

/// Lifecycle phase 5: frees `D`'s handle slot. Every handle to it stops resolving.
/proc/om_handle_release(datum/D)
	var/id = D.om_hid
	if(!id)
		return
	D.om_hid = 0
	var/list/slots = GLOB.om_handle_slots
	if(id > length(slots) || slots[id] != REF(D))
		return
	slots[id] = null
	GLOB.om_handle_gens[id]++
	GLOB.om_handle_free += id

/// TRUE if `h` is text shaped like an OM handle ("id:gen"). Says nothing about
/// whether it still resolves.
/proc/om_is_handle(h)
	var/static/regex/shape = regex(@"^\d+:\d+$")
	return istext(h) && shape.Find(h)

/// qdel()s whatever handle `h` names, if it still exists (QDEL_IN's deferred form).
/proc/qdel_handle(h)
	var/datum/D = om_resolve(h)
	if(D)
		qdel(D)

// ---------------------------------------------------------------- timers

/// Runs `proc` after `delay` deciseconds of E's timer clock. A
/// global proc (/proc/x) gets `call_args`; a type proc is called on E. Returns the timer id
/// (for om_cancel_timer()), or 0 if E or an argument is already gone. E null: the global owner.
/proc/om_after(datum/E, delay, proc_ref, ...)
	var/list/call_args = length(args) > 3 ? args.Copy(4) : null
	if(isnull(E))
		E = om_global_owner()
	var/datum/om/rec/rec = om_rec_of(E)
	if(!rec || rec.torn_down)
		return 0
	var/list/captured = call_args ? call_args.Copy() : null
	var/list/positions = null
	for(var/i in 1 to length(captured))
		var/datum/D = captured[i]
		if(!isdatum(D))
			continue
		var/h = om_handle(D)
		if(isnull(h))
			return 0
		captured[i] = h
		LAZYADD(positions, i)
	var/local = om_timer_local(rec)
	var/id = ++rec.timer_seq
	LAZYADD(rec.timers, list(id, local + max(delay, 0), proc_ref, captured, positions))
	om_timers_reschedule(rec)
	return id

/// Cancels timer `id` on E. Always safe: nothing is suspended inside a timer.
/proc/om_cancel_timer(datum/E, id)
	var/datum/om/rec/rec = (E || om_global_owner()).om_rec
	var/list/T = rec?.timers
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		if(T[i] == id)
			T.Cut(i, i + OM_TIMER_STRIDE)
			if(!length(T))
				rec.timers = null
			om_timers_reschedule(rec)
			return TRUE
	return FALSE

/proc/om_timer_pending(datum/E, id)
	var/list/T = (E || om_global_owner()).om_rec?.timers
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		if(T[i] == id)
			return TRUE
	return FALSE

/// Deciseconds of E's timer clock left on timer `id`, or null.
/proc/om_timer_left(datum/E, id)
	var/datum/om/rec/rec = (E || om_global_owner()).om_rec
	var/list/T = rec?.timers
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		if(T[i] == id)
			return max(T[i + 1] - om_timer_local(rec), 0)
	return null

/// The rate of E's timer clock: 0 while suspended, else its clock domain's rate.
/proc/om_timer_rate(datum/om/rec/rec)
	if(om_suspended(rec))
		return 0
	var/clock_id = rec.owner?.om_timer_clock()
	if(!clock_id)
		return 1
	var/datum/om/clock_def/C = om_registry().clock_by_id[clock_id]
	return C ? om_clock_rate(rec, C.idx) : 1

/proc/om_timer_local(datum/om/rec/rec)
	var/list/K = rec.tclock
	if(!K)
		rec.tclock = K = list(0, rec.sched.now(), om_timer_rate(rec))
	return K[1] + (rec.sched.now() - K[2]) * K[3]

/// A clock effect or suspension changed on `rec`: fold elapsed time in at the old rate,
/// take the new one, and move the wheel deadline.
/proc/om_timers_rate_changed(datum/om/rec/rec)
	var/list/K = rec.tclock
	if(!K)
		return
	var/new_rate = om_timer_rate(rec)
	if(new_rate == K[3])
		return
	K[1] = om_timer_local(rec)
	K[2] = rec.sched.now()
	K[3] = new_rate
	om_timers_reschedule(rec)

/proc/om_timers_reschedule(datum/om/rec/rec)
	if(rec.torn_down || !rec.owner)
		return
	var/datum/om/behaviour/B = om_registry().timer_behaviour
	var/list/T = rec.timers
	if(!T)
		om_cancel_after(rec.owner, B)
		return
	var/soonest = null
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		if(isnull(soonest) || T[i + 1] < soonest)
			soonest = T[i + 1]
	var/rate = rec.tclock[3]
	if(rate <= 0)
		om_cancel_after(rec.owner, B)
		return
	om_deadline(rec.owner, CEILING(max(soonest - om_timer_local(rec), 0) / rate, 1), B)

/// Calls a stored proc: a global proc with the arguments, or a type proc on `E`.
/proc/om_invoke(datum/E, proc_ref, list/call_args)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(E && GLOB.om_traced[E])
		GLOB.om_traced[E]++
#endif
	if(copytext("[proc_ref]", 1, 7) == "/proc/")
		return call(proc_ref)(arglist(call_args || list()))
	return call(E, proc_ref)(arglist(call_args || list()))

// ---------------------------------------------------------------- sleep guard

/datum/om/scheduler/var/callees_slept = 0
/// Test hook: while set, a sleeping callee is counted and logged but does not fail the test.
GLOBAL_VAR_INIT(om_expect_sleep, FALSE)

/// Runs a scheduler callback without letting it stall the scheduler. The call goes through
/// a waitfor = FALSE trampoline: if the callee sleeps, control comes back here at once, the
/// rest of the callee finishes on its own later, and the sleep is reported. Returns the
/// callee's return value, or OM_CALLEE_SLEPT. Runtimes re-throw as before.
/proc/om_guarded_call(datum/E, proc_ref, list/call_args)
	var/list/state = list(TRUE, null, null) // running, result, exception
	om_trampoline(state, E, proc_ref, call_args)
	if(state[3])
		throw state[3]
	if(!state[1])
		return state[2]
	var/datum/om/scheduler/sched = om_scheduler()
	sched.callees_slept++
	log_runtime("OM: SLEPT [proc_ref] on [E]")
#ifdef UNIT_TESTS
	if(!GLOB.om_expect_sleep && GLOB.current_test)
		var/datum/unit_test/test = GLOB.current_test
		test.Fail("OM: SLEPT [proc_ref] on [E]: scheduler callbacks must not sleep")
#endif
	return OM_CALLEE_SLEPT

/proc/om_trampoline(list/state, datum/E, proc_ref, list/call_args)
	set waitfor = FALSE
	try
		if(E)
			state[2] = om_invoke(E, proc_ref, call_args)
		else
			state[2] = call(proc_ref)(arglist(call_args || list()))
	catch(var/exception/e)
		state[3] = e
	state[1] = FALSE

/// Resolves captured handles in place. FALSE if any is gone.
/proc/om_resolve_captured(list/captured, list/positions)
	for(var/i in positions)
		var/datum/D = om_resolve(captured[i])
		if(!D)
			return FALSE
		captured[i] = D
	return TRUE

/datum/om/behaviour/internal/timers
	name = "om: timers"
	lane = LANE_URGENT

/datum/om/behaviour/internal/timers/on_deadline(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec?.timers)
		return
	var/local = om_timer_local(rec) + 0.001
	// Due timers leave the list before they run, soonest first: a timer that cancels
	// another, or schedules a new one, sees a consistent list.
	while(rec.timers && !rec.torn_down)
		var/list/T = rec.timers
		var/best = 0
		for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
			if(T[i + 1] <= local && (!best || T[i + 1] < T[best + 1]))
				best = i
		if(!best)
			break
		var/proc_ref = T[best + 2]
		var/list/captured = T[best + 3]
		var/list/positions = T[best + 4]
		T.Cut(best, best + OM_TIMER_STRIDE)
		if(!length(T))
			rec.timers = null
		if(!om_resolve_captured(captured, positions))
			rec.sched.timers_dropped++
			continue
		try
			om_guarded_call(E, proc_ref, captured)
		catch(var/exception/e)
			stack_trace("om timer [proc_ref] on [E]: [e]")
	om_timers_reschedule(rec)
