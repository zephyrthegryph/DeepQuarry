// Object-model core: one scheduler for deferred work (doc/rewrite/object_model_core.md §4.11).
//
// om_after(E, delay, proc, args...) is a one-shot call on the OM deadline wheel:
//   - owned by E: cancelled when E is deleted (om_teardown_rest drops rec.timers);
//   - on E's clock: E's timer clock (om_timer_clock(), bio for living mobs, machine for
//     machinery) scales it, and suspension or stasis pauses it;
//   - weak: every datum argument is captured as an OM handle and resolved when the timer
//     fires. A gone argument arrives as null and the call still runs (SStimer's semantics:
//     cleanup such as vend_ready = TRUE always happens; counted in sched.timers_nulled and
//     logged). after_if_alive() opts a pure effect out: its call is dropped instead (counted
//     in sched.timers_dropped).
// No datum per timer: a timer is five slots in the owner's record, and the owner has one
// deadline on the wheel (the soonest of its timers), as tasks do.
//
// The behaviour-keyed deadline underneath is om_deadline() (deadline.dm).
//
// OM handles: om_handle(D) -> "id:gen", om_resolve(h) -> D or null. The same model as the
// Rust core's handles: a slot table with a generation per slot, no per-target datum. A
// deleted datum's slot is freed and its generation bumped, so a stale handle never
// resolves to whatever reuses the id.

/// Stride of rec.timers: id, due (timer-clock ds), proc, args, handle positions, is-global-proc.
/// Ids only grow and entries are only appended or cut, so the list is sorted by id
/// (om_timer_index() binary-searches it).
#define OM_TIMER_STRIDE 6
/// Timer flags (the record's 6th field): the proc is a global proc.
#define OM_TIMER_GLOBAL (1<<0)
/// A deleted captured argument is passed as null (after()) instead of dropping the call.
#define OM_TIMER_NULLS_FOR_GONE (1<<1)
/// A global proc that takes the timer's owner as its first argument (the keyed after() trampoline): the owner is
/// prepended when it fires, so it is never captured (and resolved) as one of its own timer's arguments.
#define OM_TIMER_OWNER_FIRST (1<<2)

/datum/om/rec/var/list/timers
/// The soonest due time in rec.timers (timer-clock ds), or null with no timers. Kept in step by
/// every add/remove so arming the wheel never rescans the list.
/datum/om/rec/var/timer_soonest
/// Timer ids, per record.
/datum/om/rec/var/timer_seq = 0
/// The record's timer clock: list(local ds, settled at (sched ds), rate). Null until a timer.
/datum/om/rec/var/list/tclock

/// The clock domain (CLOCK_*) E's timers and task steps follow, or null for real time.
/datum/proc/om_timer_clock()
	return null

/mob/living/om_timer_clock()
	return CLOCK_BIO

// ---------------------------------------------------------------- global owner

/// The owner of timers that belong to no entity (round events, client real time). One per
/// scheduler, so tests get their own. Never deleted.
/datum/om/global_owner

/datum/om/scheduler/var/datum/om/global_owner/global_owner
/datum/om/scheduler/var/timers_dropped = 0
/// Timers that ran with at least one deleted argument passed as null (the default, om_after()/after()).
/datum/om/scheduler/var/timers_nulled = 0
/// Deleted arguments om_resolve_value() replaced with null during the current resolution.
GLOBAL_VAR_INIT(om_resolve_nulled, 0)

/proc/om_global_owner()
	RETURN_TYPE(/datum/om/global_owner)
	var/datum/om/scheduler/sched = om_scheduler()
	if(!sched.global_owner)
		sched.global_owner = new
		om_rec_of(sched.global_owner)
	return sched.global_owner

// ---------------------------------------------------------------- handles
//
// A slot table: slot id -> the datum's weak key (own_key(): not its ref text, because retained
// ref strings slow BYOND down), plus a generation per slot.
// The table holds text, never the datum, so a handle doesn't keep its target
// alive: a datum BYOND collects without qdel() (a dropped species, a stack
// canary) simply stops resolving, like one that was qdel()ed.

GLOBAL_LIST_EMPTY(om_handle_slots)
GLOBAL_LIST_EMPTY(om_handle_gens)
/// Per handle slot: the type of the datum it names (for the collected-without-qdel report).
GLOBAL_LIST_EMPTY(om_handle_types)
GLOBAL_LIST_EMPTY(om_handle_free)

/// The datum's handle slot, 0 until om_handle() is first called on it.
/datum/var/tmp/om_hid = 0

/// A handle to `D`: "id:gen". Null for a deleted datum or a non-datum.
/// A turf's handle is its ref text ("[0x...]"): turfs are never deleted and a turf's
/// ref is its position, so it survives ChangeTurf() (which resets the turf's vars).
/// A client's is "@ckey", resolved through GLOB.directory.
/proc/om_handle(datum/D)
	if(isturf(D))
		var/turf/T = D
		return "[REF(T)]#[om_z_generation(T.z)]"
	if(isclient(D))
		var/client/C = D
		return "@[C.ckey]" // a client is its ckey: it reads null while that player is disconnected
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
		slots[id] = own_key(D)
		var/list/types = GLOB.om_handle_types
		if(length(types) < id)
			types.len = id
		types[id] = D.type
		D.om_hid = id
	return "[id]:[gens[id]]"

/// The handle `D` already has, even while `D` is being deleted (until phase 5 releases it), or null
/// if it never had one. Never allocates. For taking a dying datum out of a handle-keyed list.
/proc/om_handle_of(datum/D)
	if(isturf(D) || isclient(D))
		return om_handle(D)
	if(!isdatum(D))
		return null
	var/id = D.om_hid
	return id ? "[id]:[GLOB.om_handle_gens[id]]" : null

/// TRUE if handle `h` names `D`, even while `D` is being deleted (until phase 5
/// releases its slot). A handle accessor (`owner()` = om_resolve(owner_handle))
/// reads null once its target is QDELETED, so `owner() == src` is FALSE inside
/// src's own teardown: compare with om_handle_is(owner_handle, src) there.
/proc/om_handle_is(h, datum/D)
	if(!h || !D)
		return FALSE
	return h == om_handle_of(D)

/// A handle slot parked for a thing that collapsed into latent data (containment.md sec 4.5): it
/// resolves to null until the entry re-materializes into the same slot (om_handle_unpark()).
#define OM_HANDLE_PARKED "\[latent]"

/// Collapse into latent data keeps the identity: `D`'s handle slot is parked (not freed, generation
/// unchanged) and every relation view naming D goes dormant under it (rel_go_dormant()). Returns the
/// slot id to keep on the latent entry, or 0 when D never had a handle.
/proc/om_handle_park(datum/D)
	var/id = D.om_hid
	if(!id)
		return 0
	rel_go_dormant(D)
	var/list/slots = GLOB.om_handle_slots
	if(id <= length(slots) && slots[id] == own_key(D))
		slots[id] = OM_HANDLE_PARKED
	D.om_hid = 0
	return id

/// The re-materialized `D` takes over parked slot `id`: every old handle to the collapsed thing
/// resolves to D again, and its dormant relation views re-link (rel_wake()).
/proc/om_handle_unpark(datum/D, id)
	var/list/slots = GLOB.om_handle_slots
	if(!id || id > length(slots) || slots[id] != OM_HANDLE_PARKED)
		return FALSE
	if(D.om_hid)
		om_handle_release(D)
	slots[id] = own_key(D)
	var/list/types = GLOB.om_handle_types
	if(length(types) >= id)
		types[id] = D.type
	D.om_hid = id
	rel_wake(D, id)
	return TRUE

/// A parked slot whose latent thing is gone for good (discarded, deleted as data): the slot is
/// freed and its generation bumped, and its dormant views are dropped.
/proc/om_handle_release_parked(id)
	var/list/slots = GLOB.om_handle_slots
	if(!id || id > length(slots) || slots[id] != OM_HANDLE_PARKED)
		return
	slots[id] = null
	GLOB.om_handle_gens[id]++
	GLOB.om_handle_free += id
	GLOB.rel_dormant -= "[id]"

/// The datum a handle names, or null if it has been deleted (whatever now uses its id).
/proc/om_resolve(h)
	if(!istext(h))
		return null
	switch(text2ascii(h))
		if(91) // "[": a turf's ref and its z-level's generation (om_handle())
			var/hash = findtext(h, "#")
			var/turf/T = locate(hash ? copytext(h, 1, hash) : h)
			if(!isturf(T))
				return null
			// A released and recycled z-level bumps its generation: an old turf handle stops
			// resolving instead of naming a turf of whatever site reuses the level.
			if(hash && text2num(copytext(h, hash + 1)) != om_z_generation(T.z))
				return null
			return T
		if(64) // "@": a client's ckey
			return GLOB.directory[copytext(h, 2)]
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
	if(!ref || ref == OM_HANDLE_PARKED)
		return null
	var/datum/D = own_locate(ref)
	if(!isdatum(D) || D.om_hid != id)
		// Collected without qdel(); a new datum may even have the ref now. Free the slot.
		// A handle is not a reference: when it was the only thing naming its
		// target, BYOND freed the target at once (a nullspace holder turned into
		// a handle by the LC-refs sweep). That var owns what it names.
		var/list/types = GLOB.om_handle_types
		om_handle_collected_report(id <= length(types) ? types[id] : null)
		slots[id] = null
		GLOB.om_handle_gens[id]++
		GLOB.om_handle_free += id
		return null
	if(QDELETED(D))
		return null
	return D

/// Lifecycle phase 5: frees `D`'s handle slot. Every handle to it stops resolving.
/// A handle's target was freed by BYOND without going through qdel() (a
/// qdel'd datum releases its slot in phase 5, so it never gets here): the var
/// holding the handle was its only owner. Reported once per type, with a stack
/// trace naming the reader; a runtime, so a test run fails.
/proc/om_handle_collected_report(target_type)
	dq_lifecycle_report("HANDLE TARGET COLLECTED WITHOUT QDEL: a handle to [target_type || "an unknown type"] outlived its target, which was freed without qdel() -- the var holding it must be DECLARE_REF(..., OWNED)/DECLARE_REF(..., HELD), not a handle (see the stack for the reader)")

/proc/om_handle_release(datum/D)
	var/id = D.om_hid
	if(!id)
		return
	D.om_hid = 0
	var/list/slots = GLOB.om_handle_slots
	if(id > length(slots) || slots[id] != own_key(D))
		return
	slots[id] = null
	GLOB.om_handle_gens[id]++
	GLOB.om_handle_free += id

/// TRUE if `h` is text shaped like an OM handle ("id:gen"). Says nothing about
/// whether it still resolves.
/proc/om_is_handle(h)
	var/static/regex/shape = regex(@"^(\d+:\d+|\[0x[0-9a-fA-F]+\](#\d+)?|@\w+)$")
	return istext(h) && shape.Find(h)

/// qdel()s whatever handle `h` names, if it still exists (QDEL_IN's deferred form).
/proc/qdel_handle(h)
	var/datum/D = om_resolve(h)
	if(D)
		spent(D)

// ---------------------------------------------------------------- timers

/// Runs `proc` after `delay` deciseconds of E's timer clock. A
/// global proc (/proc/x) gets `call_args`; a type proc is called on E. Returns the timer id
/// (for om_cancel_timer()), or 0 if E or an argument is already gone. E null: the global owner.
/proc/om_after(datum/E, delay, proc_ref, ...)
	return rx_after(E, delay, proc_ref, null, CLOCK_OWN, length(args) > 3 ? args.Copy(4) : null, TRUE)

/// om_after()'s body. nulls_for_gone (the default for om_after()/after()): a captured datum argument
/// deleted before the timer fires, or already deleted when it is scheduled, is passed as null and the
/// call runs. FALSE (after_if_alive()): the call is dropped, and an already-deleted argument is
/// refused up front (returns 0).
/proc/om_after_list(datum/E, delay, proc_ref, list/call_args, nulls_for_gone = TRUE, owner_first = FALSE)
	if(isnull(E))
		E = om_global_owner()
	if(!own_guard(E, null, "a timer ([proc_ref])")) // the one teardown guard (guard.dm)
		return 0
	var/datum/om/rec/rec = om_rec_of(E)
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
	var/local = om_timer_local(rec)
	var/id = ++rec.timer_seq
	var/due = local + max(delay, 0)
	LAZYADD(rec.timers, list(id, due, proc_ref, captured, positions, (om_proc_is_global(proc_ref) ? OM_TIMER_GLOBAL : 0) | (nulls_for_gone ? OM_TIMER_NULLS_FOR_GONE : 0) | (owner_first ? OM_TIMER_OWNER_FIRST : 0)))
	if(isnull(rec.timer_soonest) || due < rec.timer_soonest)
		rec.timer_soonest = due
		om_timers_arm(rec)
	return id

// ---------------------------------------------------------------- timer slots (legacy)
//
// LEGACY wrappers over the keyed after() (code/datums/capabilities/timed.dm): a slot is an after() key on the
// owner, a TIMER relation, so fire, cancel and owner teardown leave it empty by construction and scheduling into
// an occupied slot replaces the pending timer. Nothing declares a slot (OWN_TIMER is gone).
//	after_slot(E, "name", d, proc, args...)   ->  after(E, d, proc, key = "name", with = list(args...))
//	om_timer_slot_pending(E, "name")           ->  after_pending(E, "name")
//	om_cancel_timer_slot(E, "name")            ->  cancel_after(E, "name")
//	om_timer_slot_left(E, "name")              ->  after_left(E, "name")

/// Schedules `proc_ref` after `delay` into E's slot `slot` (an after() key), replacing any timer pending there.
/// Returns TRUE if scheduled. E null: the global owner.
/proc/after_slot(datum/E, slot, delay, proc_ref, ...)
	return !!rx_after(E, delay, proc_ref, slot, CLOCK_OWN, length(args) > 4 ? args.Copy(5) : null, TRUE)

/// Cancels whatever is pending in E's slot `slot`. Returns TRUE if a timer was pending.
/proc/om_cancel_timer_slot(datum/E, slot)
	return cancel_after(E, slot)

/// TRUE while a timer is pending in E's slot `slot`.
/proc/om_timer_slot_pending(datum/E, slot)
	return after_pending(E, slot)

/// Deciseconds of E's timer clock left on the timer in slot `slot`, or null when none is pending.
/proc/om_timer_slot_left(datum/E, slot)
	if(!after_pending(E, slot))
		return null
	return after_left(E, slot)

/// TRUE when `proc_ref` is a global proc (/proc/x), FALSE for a type proc. Decided once, when a
/// deferred call is recorded, so firing never stringifies the proc.
/proc/om_proc_is_global(proc_ref)
	// Memoized per proc ref: stringifying a proc path costs microseconds, and reaction delivery (rx_call) asks on
	// every call. The set of proc refs is the code's, so the table is bounded.
	var/static/list/answers = list()
	if(isnull(proc_ref))
		return FALSE
	. = answers[proc_ref]
	if(isnull(.))
		. = answers[proc_ref] = (copytext("[proc_ref]", 1, 7) == "/proc/")

/// The position in rec.timers of timer `id`, or 0. Binary search: the list is sorted by id.
/proc/om_timer_index(datum/om/rec/rec, id)
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
/proc/om_timer_remove_at(datum/om/rec/rec, at)
	var/list/T = rec.timers
	var/due = T[at + 1]
	T.Cut(at, at + OM_TIMER_STRIDE)
	if(!length(T))
		rec.timers = null
		rec.timer_soonest = null
		return TRUE
	if(due <= rec.timer_soonest)
		om_timers_recompute_soonest(rec)
		return TRUE
	return FALSE

/proc/om_timers_recompute_soonest(datum/om/rec/rec)
	var/list/T = rec.timers
	var/soonest = null
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		if(isnull(soonest) || T[i + 1] < soonest)
			soonest = T[i + 1]
	rec.timer_soonest = soonest

/// Cancels timer `id` on E. Always safe: nothing is suspended inside a timer.
/proc/om_cancel_timer(datum/E, id)
	var/datum/owner = E || om_global_owner()
	var/datum/om/rec/rec = owner.om_rec
	var/at = om_timer_index(rec, id)
	if(!at)
		return FALSE
	if(om_timer_remove_at(rec, at))
		om_timers_arm(rec)
	return TRUE

/// How many om_after() timers E has pending.
/datum/om/scheduler/proc/timer_count(datum/E)
	return length(E?.om_rec?.timers) / OM_TIMER_STRIDE

/proc/om_timer_pending(datum/E, id)
	var/datum/owner = E || om_global_owner()
	return om_timer_index(owner.om_rec, id) != 0

/// Deciseconds of E's timer clock left on timer `id`, or null.
/proc/om_timer_left(datum/E, id)
	var/datum/owner = E || om_global_owner()
	var/datum/om/rec/rec = owner.om_rec
	var/at = om_timer_index(rec, id)
	if(!at)
		return null
	return max(rec.timers[at + 1] - om_timer_local(rec), 0)

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
	om_timers_arm(rec)

/// Rescans rec.timers for the soonest due time and arms the wheel for it.
/proc/om_timers_reschedule(datum/om/rec/rec)
	om_timers_recompute_soonest(rec)
	om_timers_arm(rec)

/// Arms (or cancels) the owner's wheel deadline for the cached timer_soonest. O(1) in timers.
/proc/om_timers_arm(datum/om/rec/rec)
	if(rec.torn_down || !rec.owner)
		return
	var/datum/om/behaviour/B = om_registry().timer_behaviour
	var/soonest = rec.timer_soonest
	if(!rec.timers || isnull(soonest))
		om_cancel_after(rec.owner, B)
		return
	var/rate = rec.tclock[3]
	if(rate <= 0)
		om_cancel_after(rec.owner, B)
		return
	om_deadline(rec.owner, CEILING(max(soonest - om_timer_local(rec), 0) / rate, 1), B)

/// Calls a stored proc: a global proc with the arguments, or a type proc on `E`.
/// `is_global`: om_proc_is_global(proc_ref), when the caller recorded it; null decides here.
/proc/om_invoke(datum/E, proc_ref, list/call_args, is_global = null)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(E && GLOB.om_traced[E])
		GLOB.om_traced[E]++
#endif
	if(isnull(is_global))
		is_global = om_proc_is_global(proc_ref)
	if(is_global)
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
/proc/om_guarded_call(datum/E, proc_ref, list/call_args, is_global = null)
	var/list/state = list(TRUE, null, null, FALSE) // running, result, exception, abandoned
	om_trampoline(state, E, proc_ref, call_args, is_global)
	if(state[3])
		throw state[3]
	if(!state[1])
		return state[2]
	// The callee slept: nobody reads state[3] any more, so a runtime it raises
	// later must be reported by the trampoline itself (see om_trampoline()).
	state[4] = TRUE
	var/datum/om/scheduler/sched = om_scheduler()
	sched.callees_slept++
	log_runtime("OM: SLEPT [proc_ref] on [E]")
#ifdef UNIT_TESTS
	if(!GLOB.om_expect_sleep && GLOB.current_test)
		var/datum/unit_test/test = GLOB.current_test
		test.Fail("OM: SLEPT [proc_ref] on [E]: scheduler callbacks must not sleep")
#endif
	return OM_CALLEE_SLEPT

/proc/om_trampoline(list/state, datum/E, proc_ref, list/call_args, is_global = null)
	set waitfor = FALSE // ALLOW(scheduler): OM sleep-guard trampoline (detects callees that sleep)
	try
		if(E)
			state[2] = om_invoke(E, proc_ref, call_args, is_global)
		else
			state[2] = call(proc_ref)(arglist(call_args || list()))
	catch(var/exception/e)
		// Still synchronous: om_guarded_call() rethrows it. After a sleep the
		// caller is gone and would never look, so report it here -- a silent
		// swallow here once hid a double-qdel CRASH and hung a test batch.
		if(state[4])
			dq_report_caught(e, "OM trampoline (after sleep) [proc_ref] on [E]")
		else
			state[3] = e
	state[1] = FALSE


// ---------------------------------------------------------------- weak arguments
//
// Every deferred record in the OM (timers and their keyed/real-time forms, I/O
// callbacks, timed actions) holds its datum arguments as OM handles, never as
// references: a record can outlive what it names without keeping it alive (a
// strong ref in a pending timer was a hard delete). capture_args() converts
// at record time, resolve_captured() at fire time; a deleted argument drops
// the call with a log_qdel() line. Synchronous paths never capture.
//
// Captured deeply: every datum anywhere in the arguments -- an argument, a list member, an assoc
// value, at any depth -- becomes a handle marker, list(OM_CAPTURED_MARK, handle), in a copy of the
// list that held it. A datum used as an assoc *key* can't be re-keyed without losing its value,
// so capture refuses it (reported): pass the pair as a value instead. A list holding no datum is
// kept as is (not copied).

#define OM_CAPTURED_MARK "\[om-handle]"
#define OM_CAPTURE_MAX_DEPTH 8

/// Captures `call_args`' datums as handles, deeply. Returns list(captured, positions): positions
/// are the argument indexes holding a handle or a list with handles in it. Null when an argument
/// is already deleted or can't be captured (a datum assoc key).
/proc/capture_args(list/call_args, nulls_for_gone = FALSE)
	var/list/captured = call_args ? call_args.Copy() : null
	var/list/positions = null
	for(var/i in 1 to length(captured))
		var/list/result = om_capture_value(captured[i], 0, nulls_for_gone)
		if(!result)
			return null
		if(result[2])
			captured[i] = result[1]
			LAZYADD(positions, i)
	return list(captured, positions)

/// list(captured value, changed) for one value, or null when it can't be captured.
/proc/om_capture_value(value, depth, nulls_for_gone = FALSE)
	if(isdatum(value))
		var/h = om_handle(value)
		if(isnull(h))
			if(nulls_for_gone)
				return list(null, FALSE) // already deleted: passed as null, like one deleted later
			return null
		return list(list(OM_CAPTURED_MARK, h), TRUE)
	if(!islist(value))
		return list(value, FALSE)
	if(depth >= OM_CAPTURE_MAX_DEPTH)
		OWN_REPORT("om_capture_args: an argument nests lists deeper than [OM_CAPTURE_MAX_DEPTH]")
		return null
	var/list/L = value
	var/list/copy = null
	for(var/j in 1 to length(L))
		var/key = L[j]
		if(isdatum(key) && !isnull(L[key]))
			var/datum/K = key
			OWN_REPORT("om_capture_args: a deferred call's argument uses [K.type] as an assoc key; pass it as a value")
			return null
		var/list/key_result = om_capture_value(key, depth + 1, nulls_for_gone)
		if(!key_result)
			return null
		var/assoc = (istext(key) || isdatum(key)) ? L[key] : null
		var/list/value_result = isnull(assoc) ? null : om_capture_value(assoc, depth + 1, nulls_for_gone)
		if(!isnull(assoc) && !value_result)
			return null
		if(key_result[2] || value_result?[2])
			if(!copy)
				copy = L.Copy()
			if(key_result[2])
				copy[j] = key_result[1]
			else if(value_result?[2])
				copy[key] = value_result[1]
	if(copy)
		return list(copy, TRUE)
	return list(L, FALSE)

/// A deferred call as data: the callee and every datum argument held as handles (deeply), so a
/// stored call never keeps what it names alive -- the replacement for CALLBACK / /datum/callback,
/// whose strong references were invisible to ownership. Returns list(callee handle or null for a
/// global proc, proc ref, captured args, positions), or null when an argument is already gone.
/// Store it in any var; run it with om_run().
/proc/om_callable(datum/target, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : null
	var/list/capture = call_args ? capture_args(call_args) : list(null, null)
	if(!capture)
		return null
	var/callee_handle = null
	if(target)
		callee_handle = om_handle(target)
		if(isnull(callee_handle))
			return null
	return list(callee_handle, proc_ref, capture[1], capture[2])

/// Runs an om_callable() spec with its stored arguments followed by `...`. Returns what the proc
/// returned, or null when the target or a captured argument no longer exists (the call is dropped).
/proc/om_run(list/spec, ...)
	if(!islist(spec) || length(spec) != 4)
		return null
	var/datum/target = null
	if(spec[1])
		target = om_resolve(spec[1])
		if(!target)
			return null
	var/list/stored = spec[3]
	var/list/call_args = stored ? stored.Copy() : list()
	if(spec[4] && !resolve_captured(call_args, spec[4]))
		return null
	if(length(args) > 1)
		call_args += args.Copy(2)
	if(target)
		return call(target, spec[2])(arglist(call_args))
	return call(spec[2])(arglist(call_args))

/// om_run() without waiting: the call runs in its own stack (INVOKE_ASYNC for a stored spec).
/proc/om_run_async(list/spec, ...)
	set waitfor = FALSE // ALLOW(scheduler): the async half of a stored call spec, as /datum/callback/InvokeAsync() was
	return om_run(arglist(args))

/// Resolves captured handles in place. FALSE if any is gone (or, with `nulls_for_gone`, passes
/// null for it instead: cleanup that must still run). The record keeps its own copy.
/proc/resolve_captured(list/captured, list/positions, nulls_for_gone = FALSE)
	for(var/i in positions)
		var/list/result = om_resolve_value(captured[i], nulls_for_gone)
		if(!result)
			return FALSE
		captured[i] = result[1]
	return TRUE

/// list(resolved value) for one captured value, or null when a handle no longer resolves.
/proc/om_resolve_value(value, nulls_for_gone)
	if(!islist(value))
		return list(value)
	var/list/L = value
	if(length(L) == 2 && L[1] == OM_CAPTURED_MARK)
		var/datum/D = om_resolve(L[2])
		if(!D)
			if(!nulls_for_gone)
				return null
			GLOB.om_resolve_nulled++
		return list(D)
	var/list/out = L.Copy()
	for(var/j in 1 to length(out))
		var/key = out[j]
		var/assoc = istext(key) ? out[key] : null
		if(islist(key))
			var/list/key_result = om_resolve_value(key, nulls_for_gone)
			if(!key_result)
				return null
			out[j] = key_result[1]
		else if(islist(assoc))
			var/list/value_result = om_resolve_value(assoc, nulls_for_gone)
			if(!value_result)
				return null
			out[key] = value_result[1]
	return list(out)

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
		var/timer_flags = T[best + 5]
		var/is_global = !!(timer_flags & OM_TIMER_GLOBAL)
		T.Cut(best, best + OM_TIMER_STRIDE)
		if(!length(T))
			rec.timers = null
		GLOB.om_resolve_nulled = 0
		if(!resolve_captured(captured, positions, !!(timer_flags & OM_TIMER_NULLS_FOR_GONE)))
			rec.sched.timers_dropped++
			log_qdel("OM: dropped timer [proc_ref] on [E] ([E.type]): a captured argument was deleted before it fired (after_if_alive)")
			continue
		if(GLOB.om_resolve_nulled)
			rec.sched.timers_nulled++
			log_qdel("OM: timer [proc_ref] on [E] ([E.type]) runs with [GLOB.om_resolve_nulled] deleted argument(s) passed as null")
		if(timer_flags & OM_TIMER_OWNER_FIRST)
			captured = captured ? list(E) + captured : list(E)
		CHURN_COUNT(timers, "[E.type] [proc_ref]")
		try
			om_guarded_call(E, proc_ref, captured, is_global)
		catch(var/exception/e)
			dq_report_caught(e, "om timer [proc_ref] on [E]")
		// A timer is a dispatched call: its owner may have changed (dx_conventions.md §1). Its derived procs
		// re-run; no channel is raised (refresh_dispatched()).
		if(!istype(E, /datum/om/global_owner))
			refresh_dispatched(E)
	om_timers_reschedule(rec)

// ---------------------------------------------------------------- keyed timers
//
// SStimer's TIMER_UNIQUE and TIMER_OVERRIDE, as the key they really were: the owner, the
// proc and its arguments. No extra state: the owner's timer list is the index. These live on
// the scheduler; call them through the
// om_after_unique() / om_after_replace() / om_cancel_calls() / om_timer_count() macros.

/// The position in rec.timers of a pending timer calling `proc_ref` with `call_args`, or 0.
/datum/om/scheduler/proc/timer_find(datum/om/rec/rec, proc_ref, list/call_args)
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
			if(captured[j] != arg && !om_captured_matches(captured[j], arg))
				same = FALSE
				break
		if(same)
			return i
	return 0

/// TRUE when a captured argument is what capturing `arg` now would give (datums as handles).
/proc/om_captured_matches(captured_value, arg)
	var/list/result = om_capture_value(arg, 0)
	if(!result)
		return FALSE
	var/now = result[1]
	if(!islist(now) || !islist(captured_value))
		return now == captured_value
	return json_encode(now) == json_encode(captured_value)

/// om_after(), unless the same call (owner, proc, arguments) is already pending: then
/// nothing, and the pending timer's id is returned. (Was TIMER_UNIQUE.)
/datum/om/scheduler/proc/after_unique(datum/E, delay, proc_ref, ...)
	if(isnull(E))
		E = om_global_owner()
	var/list/call_args = length(args) > 3 ? args.Copy(4) : list()
	var/datum/om/rec/rec = om_rec_of(E)
	var/i = timer_find(rec, proc_ref, call_args)
	if(i)
		return rec.timers[i]
	return om_after(arglist(list(E, delay, proc_ref) + call_args))

/// om_after(), replacing the same call if it is pending: the delay restarts. (Was
/// TIMER_UNIQUE | TIMER_OVERRIDE.)
/datum/om/scheduler/proc/after_replace(datum/E, delay, proc_ref, ...)
	if(isnull(E))
		E = om_global_owner()
	var/list/call_args = length(args) > 3 ? args.Copy(4) : list()
	var/datum/om/rec/rec = om_rec_of(E)
	var/i = timer_find(rec, proc_ref, call_args)
	if(i)
		om_cancel_timer(E, rec.timers[i])
	return om_after(arglist(list(E, delay, proc_ref) + call_args))

/// Cancels every pending timer on E that calls `proc_ref`, whatever its arguments.
/datum/om/scheduler/proc/cancel_calls(datum/E, proc_ref)
	var/datum/om/rec/rec = E?.om_rec
	var/list/T = rec?.timers
	. = 0
	for(var/i = length(T) - OM_TIMER_STRIDE + 1, i >= 1, i -= OM_TIMER_STRIDE)
		if(T[i + 2] == proc_ref)
			T.Cut(i, i + OM_TIMER_STRIDE)
			.++
	if(.)
		if(!length(T))
			rec.timers = null
		om_timers_reschedule(rec)

// ---------------------------------------------------------------- real time
//
// Client-facing delays (a flicked overlay, a UI fade) follow the wall clock, not game time,
// which slows under time dilation. They go on the global owner. The wheel runs in game
// time, so a real-time timer is due at a REALTIMEOFDAY, and re-arms for what is left when the
// wheel fires it early. (Was TIMER_CLIENT_TIME.)

/// Runs `proc` after `delay` deciseconds of real time, on the global owner. Arguments are
/// captured weakly, as om_after() does. A global proc gets the arguments; a type proc runs on
/// the first argument and gets the rest.
/proc/om_after_realtime(delay, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : list()
	return om_after(arglist(list(null, delay, /proc/om_realtime_fire, REALTIMEOFDAY + max(delay, 0), proc_ref) + call_args))

/proc/om_realtime_fire(due, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : list()
	var/left = due - REALTIMEOFDAY
	if(left > 0)
		om_after(arglist(list(null, left, /proc/om_realtime_fire, due, proc_ref) + call_args))
		return
	if(om_proc_is_global(proc_ref))
		call(proc_ref)(arglist(call_args))
	else if(length(call_args))
		// A type proc: the first argument is the datum it runs on.
		var/target = call_args[1]
		if(target) // a client that has disconnected is null
			call(target, proc_ref)(arglist(call_args.Copy(2)))
