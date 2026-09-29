// changed() and the refresh engine (doc/rewrite/dx_conventions.md §1, §3, §4).
//
// Derived things are plain procs: draw(look), should_run(), hidden_verbs(), tgui_data(),
// on_state_changed(). changed(E) queues E, and everything that owns it up the owner chain, for one
// refresh at the end of the frame (the presentation lane). Dispatchers call changed() for you after
// every handler, timer, periodic step, prompt answer and ownership transfer; TRACKED setters call
// it; a write outside all of those calls it by hand. A background sweep re-checks entities with
// derived procs on a per-tick budget: production corrects a missed mark within seconds, test builds
// fail the run and name the type (REFRESH DRIFT).

/datum
	/// Queued for a refresh this frame.
	var/tmp/refresh_queued = FALSE
	/// The channels raised since the last refresh (on_state_changed() reads them).
	var/tmp/refresh_bits = 0

/atom
	/// The key of the look last applied (draw()), or null when the type draws nothing.
	var/tmp/look_key
	/// The overlays the last applied look added (swapped out on the next change).
	var/tmp/list/look_overlays
	/// The verbs hidden by the last refresh.
	var/tmp/list/refresh_hidden_verbs

/// The periodic pipeline should_run() gates, or null for no periodic work. A type var.
/datum/var/periodic_cadence = null
/// A custom interval (deciseconds) for periodic_step() instead of a shared cadence (the old
/// DECLARE_REPEAT delay): runs every interval while should_run() holds. A type var.
/datum/var/periodic_interval = null

OWN_TIMER(/datum, periodic_interval)

/// Starts or stops D's custom-interval step to match should_run().
/proc/periodic_interval_update(datum/D)
	var/want = !!D.should_run()
	var/pending = om_timer_slot_pending(D, "periodic_interval")
	if(want && !pending)
		after_slot(D, "periodic_interval", D.periodic_interval, GLOBAL_PROC_REF(periodic_interval_fire), D)
	else if(!want && pending)
		om_cancel_timer_slot(D, "periodic_interval")

/// One custom-interval step; re-arms while should_run() holds (the framework's timer, not game code).
/proc/periodic_interval_fire(datum/D)
	if(QDELETED(D) || !D.periodic_interval)
		return
	if(D.periodic_step(D.periodic_interval) == PROCESS_KILL || !D.should_run())
		return
	after_slot(D, "periodic_interval", D.periodic_interval, GLOBAL_PROC_REF(periodic_interval_fire), D)

/// Marks E changed: queues its refresh (and its owners', up the chain) and raises `channel` for OM
/// observers. The rare direct write outside a dispatched call or a TRACKED setter calls this.
/proc/changed(datum/E, channel = CHANGE_EXPLICIT)
	if(!E || QDELING(E))
		return
	om_changed(E, channel)
	refresh_mark(E, channel)

/// Queues E's refresh (and its drawing owners', H2). changed() and om_changed() both come here.
/proc/refresh_mark(datum/E, channel)
	if(!E || QDELING(E))
		return
	// The look applying itself (set_light, vis_contents) is presentation, not a state change.
	if(E == GLOB.refresh_applying)
		return
#if defined(UNIT_TESTS)
	// H5: a refresh that marks its own entity again is a feedback loop (a reactive proc wrote state).
	if(E == GLOB.refresh_running)
		var/msg = "REFRESH SELF-MARK: [E.type] marked itself changed during its own refresh"
		GLOB.refresh_self_marks += msg
		if(!GLOB.refresh_self_mark_expected)
			stack_trace(msg)
#endif
	refresh_trace_note(E, channel)
	// Sources watching E through a relation view (rel_one/rel_many(watch = ...)) re-derive too. Only on
	// E's first mark this frame, so two entities watching each other stop after one round.
	if(E.rel_watchers && !E.refresh_queued)
		E.refresh_queued = TRUE
		GLOB.refresh_queue += E
		rel_notify_watchers(E)
	var/datum/D = E
	for(var/depth in 1 to 8)
		D.refresh_bits |= channel
		if(!D.refresh_queued)
			D.refresh_queued = TRUE
			GLOB.refresh_queue += D
		// H2: the owner is marked only when one of its capabilities draws this child (a slot with
		// draws_var naming the var that holds it). Anything else stays local.
		var/datum/owner = owner_of(D)
		if(!owner || QDELING(owner) || !isatom(owner) || !owner_draws_child(owner, D))
			break
		D = owner

GLOBAL_LIST_EMPTY(refresh_queue)
/// Refreshes run so far (the dx_refresh benchmark reads it).
GLOBAL_VAR_INIT(refresh_bench_drained, 0)
/// The entity whose refresh is running now (the self-mark detector reads it).
GLOBAL_DATUM(refresh_running, /datum)
GLOBAL_VAR_INIT(refresh_self_mark_expected, FALSE)
/// The atom whose look is being applied now: marks it raises meanwhile are its own presentation.
GLOBAL_DATUM(refresh_applying, /atom)
/// Self-mark reports this round (the detector test reads them).
GLOBAL_LIST_EMPTY(refresh_self_marks)

/// Whether one of owner's capabilities draws `child` (its draws_var holds it).
/proc/owner_draws_child(atom/owner, datum/child)
	for(var/datum/capability/C as anything in caps_all(owner))
		if(!C.draws_var)
			continue
		var/held = owner.vars[C.draws_var]
		if(held == child || (islist(held) && (child in held)))
			return TRUE
	return FALSE

// ---- "why did this redraw?" (M10): the last marks of each entity, with where they came from ----

/// Ref text of entities whose marks are being traced (the admin verb turns one on); refs, so a
/// forgotten trace keeps nothing alive. Empty: tracing costs one check.
GLOBAL_LIST_EMPTY(refresh_traced)

/proc/refresh_trace_note(datum/E, channel)
	if(!length(GLOB.refresh_traced))
		return
	var/ref_text = REF(E)
	if(!(ref_text in GLOB.refresh_traced))
		return
	var/list/lines = GLOB.refresh_traced[ref_text]
	if(!islist(lines))
		lines = GLOB.refresh_traced[ref_text] = list()
	var/callee/source = callee?.caller?.caller
	lines += "[world.time]: channel [channel] from [source ? "[source.proc]" : "?"]"
	if(length(lines) > 20)
		lines.Cut(1, 2)

// ---- the derived procs (plain overrides) ----

/// The look: call ..() first (capabilities draw their layers), then look.state()/overlay()/gauge()/
/// glow(). A type that never sets anything keeps its mapped icon_state.
/atom/proc/draw(datum/look/look)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	if(GLOB.derive_probing && derive_called_by_override(callee.caller, "draw"))
		GLOB.derive_probe_found |= TYPE_DERIVES_LOOK
	for(var/datum/capability/C as anything in caps_ordered(src, CAP_ORDER_DRAW))
		C.draw(src, look)

/// TRUE while periodic_step(dt) should run on `periodic_cadence`. Re-evaluated on change.
/datum/proc/should_run()
	SHOULD_NOT_SLEEP(TRUE)
	return FALSE

/// The verbs to hide right now. Call ..() (capabilities hide theirs). Re-evaluated on change.
/atom/proc/hidden_verbs()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	if(GLOB.derive_probing && derive_called_by_override(callee.caller, "hidden_verbs"))
		GLOB.derive_probe_found |= TYPE_DERIVES_VERBS
	return caps_hidden_verbs()

// ---- what a type derives, decided by its declared overrides (never by one instance's result) ----

/// Set while a type's first refresh probes which derived procs it overrides.
GLOBAL_VAR_INIT(derive_probing, FALSE)
/// TYPE_DERIVES_* found by the probe: the base proc was reached through a type's override.
GLOBAL_VAR_INIT(derive_probe_found, 0)

/// Whether `caller` (the proc that called a base derived proc) is an override of `name`: the base was
/// reached through a type's own draw()/hidden_verbs() calling ..(), not directly by the engine.
/proc/derive_called_by_override(callee/caller, name)
	if(!caller)
		return FALSE
	var/path = "[caller.proc]"
	return copytext(path, -(length(name) + 1)) == "/[name]"

/// Side effects of a state change (a Rust device sync, a network rebuild), coalesced to once per
/// frame. `bits` are the channels raised since the last refresh. Never call it by hand.
/datum/proc/on_state_changed(bits)
	SHOULD_NOT_SLEEP(TRUE)
	return

// ---- the drain ----

/// Runs queued refreshes within the lane budget. TRUE when the queue is empty.
/proc/refresh_drain(datum/om/scheduler/sched)
	var/list/Q = GLOB.refresh_queue
	// review 2 M4: each entity refreshes at most once per drain; one re-queued by its own refresh (or
	// by a chain that comes back to it) waits for the next frame instead of spinning here.
	var/list/done = list()
	var/list/deferred
	var/i = 0
	while(i < length(Q))
		i++
		var/datum/D = Q[i]
		if(done[D])
			LAZYADD(deferred, D)
			continue
		D.refresh_queued = FALSE
		if(QDELETED(D))
			D.refresh_bits = 0
			continue
		done[D] = TRUE
		var/bits = D.refresh_bits
		D.refresh_bits = 0
		GLOB.refresh_bench_drained++
		try
			refresh_one(D, bits)
		catch(var/exception/e)
			if(sched)
				sched.report_caught(e, "refresh of [D.type]: [e] ([e.file]:[e.line])")
			else
				stack_trace("refresh of [D.type]: [e] ([e.file]:[e.line])")
		if(sched?.out_of_budget() && i < length(Q))
			Q.Cut(1, i + 1)
			if(deferred)
				Q += deferred
			return FALSE
	Q.Cut()
	if(deferred)
		Q += deferred
		return FALSE
	return TRUE

/// Every queued refresh now, ignoring the budget (tests, admin tools). A self-re-marking entity is
/// refreshed a bounded number of times, then reported.
/proc/refresh_flush()
	var/passes = 0
	while(length(GLOB.refresh_queue))
		refresh_drain(null)
		if(++passes > 20)
			stack_trace("refresh_flush: still queued after 20 passes (a reactive proc re-marks its entity?): [jointext(GLOB.refresh_queue, ", ")]")
			for(var/datum/D as anything in GLOB.refresh_queue)
				D.refresh_queued = FALSE
				D.refresh_bits = 0
			GLOB.refresh_queue.Cut()
			return

/// One entity's refresh: periodic gate, look, hidden verbs, open windows, then on_state_changed.
/proc/refresh_one(datum/D, bits)
	var/datum/outer = GLOB.refresh_running
	GLOB.refresh_running = D
	try
		refresh_one_inner(D, bits)
	catch(var/exception/e)
		// Restore before the drain reports it: a stale refresh_running would flag every later mark of
		// D as a self-mark.
		GLOB.refresh_running = outer
		throw e
	GLOB.refresh_running = outer

/proc/refresh_one_inner(datum/D, bits)
	refresh_periodic(D)
	if(isatom(D))
		var/atom/A = D
		// A type known to draw nothing and hide nothing skips both (review 2 H3): capabilities can
		// draw and hide, and a type not seen yet is tried once and recorded.
		var/flags = type_derive_flags(A)
		var/may_draw = flags & (TYPE_DERIVES_LOOK | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING) || !isnull(A.look_key)
		var/may_hide = flags & (TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING) || A.refresh_hidden_verbs
		var/probing = flags & TYPE_DERIVES_PENDING
		if(probing)
			GLOB.derive_probing = TRUE
			GLOB.derive_probe_found = 0
		if(may_draw)
			refresh_look(A)
		if(may_hide)
			refresh_verbs(A)
		if(probing)
			GLOB.derive_probing = FALSE
			// Type-pure: the type overrides draw()/hidden_verbs() or it doesn't, whatever this
			// instance's state drew or hid (review: never record a negative from one result).
			type_derive_record(A, GLOB.derive_probe_found & TYPE_DERIVES_LOOK, GLOB.derive_probe_found & TYPE_DERIVES_VERBS)
		refresh_sweep_track(A)
	if(LAZYLEN(D.open_tguis))
		SStgui.update_uis(D)
	D.on_state_changed(bits)

/proc/refresh_periodic(datum/D)
	if(D.periodic_interval)
		periodic_interval_update(D)
		return
	if(!D.periodic_cadence)
		return
	var/want = !!D.should_run()
	var/running = om_task_periodic_running(D)
	if(want && !running)
		om_task_periodic(D, D.periodic_cadence)
	else if(!want && running)
		om_task_periodic_stop(D)

/// Builds A's look and applies it when its key changed. Returns the key.
/proc/refresh_look(atom/A, apply = TRUE)
	var/datum/look/L = GLOB.look_builder
	L.reset()
	A.draw(L)
	// Transient flashes (look_flash()) sit on top of whatever draw() described.
	if(A.look_flash_state)
		L.state(A.look_flash_state)
	for(var/state in A.look_flashes)
		L.overlay(state)
	if(!L.touched)
		if(apply && !isnull(A.look_key))
			// It drew before and draws nothing now: applying the empty look takes back everything the
			// last look set (overlays, filters, vis_contents, base properties).
			L.apply_to(A)
			A.look_key = null
		return null
	var/key = L.change_key()
	if(apply && key != A.look_key)
		var/atom/outer = GLOB.refresh_applying
		GLOB.refresh_applying = A
		L.apply_to(A)
		GLOB.refresh_applying = outer
		A.look_key = key
	return key

/// Brings A's derived verb hides in line with hidden_verbs(). The verb store stays the only writer of a
/// verbs list: a hidden verb is one more reason verb_store_wants() says no, and only the keys whose
/// hidden state flipped are re-synced.
/proc/refresh_verbs(atom/A, apply = TRUE)
	var/list/hidden = A.hidden_verbs() || list()
	if(!length(hidden) && !length(A.refresh_hidden_verbs))
		return hidden
	if(!apply)
		return hidden
	var/list/was = A.refresh_hidden_verbs || list()
	var/list/flipped = (was - hidden) + (hidden - was)
	A.refresh_hidden_verbs = length(hidden) ? hidden : null
	if(length(flipped))
		verb_store_refresh(A, flipped)
	return hidden

// ---- the background sweep ----

/// Atoms with something derived (a look, hidden verbs, periodic work), as ref text -> TRUE. Refs,
/// not the atoms: the sweep list never keeps a deleted atom alive (it would hard-delete every drawn
/// atom); a ref that no longer names a swept atom is dropped when the sweep reaches it.
GLOBAL_LIST_EMPTY(refresh_sweep_list)
GLOBAL_VAR_INIT(refresh_sweep_index, 1)
/// Drift reports this round (the drift test reads them).
GLOBAL_LIST_EMPTY(refresh_drift)

/atom/var/tmp/refresh_swept = FALSE

/proc/refresh_sweep_track(atom/A)
	if(A.refresh_swept)
		return
	if(isnull(A.look_key) && !A.refresh_hidden_verbs && !A.periodic_cadence)
		return
	A.refresh_swept = TRUE
	GLOB.refresh_sweep_list[REF(A)] = TRUE

/// Re-checks up to `budget` swept atoms: a derived result that differs from what is applied means a
/// change was never marked. Production applies it; test builds report REFRESH DRIFT and fail.
/proc/refresh_sweep_step(budget = 50)
	// H3 / review 2 M3: test builds sweep everything strictly (drift fails the run). Production checks
	// only atoms a player can see or has open, at a small budget; skipping a far atom costs a scan,
	// not a check, so a full cycle over the near atoms takes seconds.
#if defined(UNIT_TESTS)
	var/scan_budget = budget
#else
	budget = min(budget, 10)
	var/scan_budget = 400
	var/list/client_turfs = refresh_client_turfs()
	if(!length(client_turfs))
		return
#endif
	var/list/L = GLOB.refresh_sweep_list
	var/checked = 0
	var/scanned = 0
	while(checked < budget && scanned < scan_budget && length(L))
		if(GLOB.refresh_sweep_index > length(L))
			GLOB.refresh_sweep_index = 1
		var/atom/A = locate(L[GLOB.refresh_sweep_index])
		if(!isatom(A) || QDELETED(A) || !A.refresh_swept)
			L.Cut(GLOB.refresh_sweep_index, GLOB.refresh_sweep_index + 1)
			continue
		GLOB.refresh_sweep_index++
		scanned++
		// Queued here, or by a declared appearance watch (a stat or density change) whose
		// update_icon() on this same lane marks it: its refresh is pending, not missed.
		if(A.refresh_queued || A.appearance_queued)
			continue
#if !defined(UNIT_TESTS)
		if(!LAZYLEN(A.open_tguis) && !refresh_near(A, client_turfs))
			continue
#endif
		checked++
		refresh_check_drift(A)

/// The turfs of every client's mob, once per sweep step.
/proc/refresh_client_turfs()
	. = list()
	for(var/client/C as anything in GLOB.clients)
		var/turf/where = get_turf(C?.mob)
		if(where)
			. += where

/// Whether A is on a client's z-level within a screen of them.
/proc/refresh_near(atom/A, list/client_turfs)
	var/turf/T = get_turf(A)
	if(!T)
		return FALSE
	for(var/turf/where as anything in client_turfs)
		if(where.z == T.z && get_dist(where, T) <= world.view + 2)
			return TRUE
	return FALSE

/proc/refresh_check_drift(atom/A)
	var/list/drift = list()
	var/key = refresh_look(A, apply = FALSE)
	if(key != A.look_key)
		drift += "draw()"
	var/list/hidden = A.hidden_verbs() || list()
	var/list/was = A.refresh_hidden_verbs || list()
	if(length(hidden ^ was))
		drift += "hidden_verbs()"
	if(A.periodic_cadence && (!!A.should_run() != om_task_periodic_running(A)))
		drift += "should_run()"
	if(!length(drift))
		return FALSE
	var/msg = "REFRESH DRIFT: [A.type] [jointext(drift, ", ")] changed with no changed() mark"
	GLOB.refresh_drift += msg
#if defined(UNIT_TESTS)
	if(!GLOB.refresh_drift_expected)
		stack_trace(msg)
#endif
	refresh_one(A, 0)
	return TRUE

GLOBAL_VAR_INIT(refresh_drift_expected, FALSE)
