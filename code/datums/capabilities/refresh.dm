// changed() and the refresh engine (doc/rewrite/dx_conventions.md §1, §3, §4).
//
// Derived things are plain procs: draw(look), should_run(), hidden_verbs(), tgui_data(),
// push_to_rust(), on_state_changed(). changed(E) queues E, and everything that owns it up the owner
// chain, for one refresh at the end of the frame (the presentation lane). Dispatchers call changed()
// for you after every handler, timer, periodic step, prompt answer and ownership transfer; TRACKED
// setters call it with the var they wrote; a write outside all of those calls it by hand.
//
// What a queued entity re-derives is a bitmask in refresh_queued (DEP_*): a plain changed(E) marks
// everything, a tracked write on a type that declares its dependencies (derived.dm) marks only the
// outputs that read the var. The drain runs each marked output at most once per entity per frame.
//
// A background sweep re-checks entities with derived procs on a per-tick budget: production corrects
// a missed mark within seconds, test builds fail the run and name the type and, when it can, the
// likely undeclared read (REFRESH DRIFT).

/datum
	/// The outputs queued for a refresh this frame (DEP_* bits), 0 when not queued.
	var/tmp/refresh_queued = 0
	/// The channels raised since the last refresh (on_state_changed() reads them).
	var/tmp/refresh_bits = 0

/atom
	/// The key of the look last applied (draw()), or null when the type draws nothing.
	var/tmp/look_key
	/// The overlays the last applied look added (swapped out on the next change).
	var/tmp/list/look_overlays
	/// The verbs hidden by the last refresh.
	var/tmp/list/refresh_hidden_verbs
	/// The verbs granted_verbs() gave by the last refresh.
	var/tmp/list/refresh_granted_verbs // ALLOW(base_vars): the refresh pass's memo of what it granted, beside refresh_hidden_verbs; its gate and drift check read it on every atom refresh

/// The periodic pipeline should_run() gates, or null for no periodic work. A type var.
/datum/var/periodic_cadence = null
/// A custom interval (deciseconds) for periodic_step() instead of a shared cadence (the old
/// DECLARE_REPEAT delay): runs every interval while should_run() holds. A type var.
/datum/var/periodic_interval = null

/// Starts or stops D's custom-interval step to match should_run().
/proc/periodic_interval_update(datum/D)
	DERIVED_EVAL_BEGIN
	var/want = !!D.should_run()
	DERIVED_EVAL_END
	var/pending = after_pending(D, "periodic_interval")
	if(want && !pending)
		after(D, D.periodic_interval, GLOBAL_PROC_REF(periodic_interval_fire), key = "periodic_interval", with = list(D))
	else if(!want && pending)
		cancel_after(D, "periodic_interval")

/// One custom-interval step; re-arms while should_run() holds (the framework's timer, not game code).
/proc/periodic_interval_fire(datum/D)
	if(QDELETED(D) || !D.periodic_interval)
		return
	if(D.periodic_step(D.periodic_interval) == PROCESS_KILL || !D.should_run())
		return
	after(D, D.periodic_interval, GLOBAL_PROC_REF(periodic_interval_fire), key = "periodic_interval", with = list(D))

/// Marks E changed: queues its refresh (and its owners', up the chain) and raises `channel` for OM
/// observers. The rare direct write outside a dispatched call or a TRACKED setter calls this.
/// `var_name` is the tracked var that changed (TRACKED setters, timed_set and the ownership accessors
/// pass it): a type that declares its dependencies (derived()) re-derives only the outputs that read
/// it, and marks the entities that hop to it; any other type, and a call without it, re-derives
/// everything.
/proc/changed(datum/E, channel = CHANGE_EXPLICIT, var_name)
	if(!E || QDELING(E))
		return
	OP_PURE_GUARD("[E.type][var_name ? ".[var_name]" : ""] was written")
	op_changed(E) // a cached menu or reach read of the op engine is stale now
	// The stat layer: a var some stat reads recomputes it before this write's next line (code/engine/stats/recompute.dm).
	if(var_name && GLOB.stat_input_keys?[var_name] && var_name != GLOB.stat_writing)
		stat_inputs_changed(E, var_name)
	// OM observers only: om_raise_change()'s own refresh hook would mark every output, undoing the mask below.
	if(E.om_listen & channel)
		om_dispatch_change(E, channel)
	// The look applying itself (set_light, vis_contents) is presentation, not a state change.
	if(E == GLOB.refresh_applying)
		return
#if defined(UNIT_TESTS)
	// H5: a refresh that marks its own entity again is a feedback loop (a reactive proc wrote state).
	if(E == GLOB.refresh_running && !GLOB.ledger_adopting)
		var/msg = "REFRESH SELF-MARK: [E.type] marked itself changed during its own refresh"
		GLOB.refresh_self_marks += msg
		if(!GLOB.refresh_self_mark_expected)
			stack_trace(msg)
	// Outputs must not write state: a tracked write while should_run, draw, hidden_verbs, tgui_data or a
	// derive_<var> runs is reported.
	if(var_name && GLOB.derived_evaluating)
		var/write_msg = "OUTPUT WROTE STATE: [E.type].[var_name] was written while an output (should_run, draw, hidden_verbs, tgui_data, derive_<var>) was running"
		GLOB.derived_write_violations += write_msg
		if(!GLOB.derived_write_expected)
			stack_trace(write_msg)
#endif
	// Demand-gated: a var nobody reads (no reaction, generated read, derived() entry or observer) publishes nothing.
	if(var_name && READERS(E, var_name))
		publish_change(E, var_name)
	refresh_trace_note(E, channel)
	// Sources watching E through a relation view (rel_one/rel_many(watch = ...)) re-derive too. Only on
	// E's first mark this frame, so two entities watching each other stop after one round.
	if(E.rel_watchers && !E.refresh_queued)
		rel_notify_watchers(E)
	var/mask = DEP_ALL
	if(var_name)
		mask = derived_mask(E, var_name)
		if(!mask)
			return
	if(!refresh_wanted(E))
		refresh_mark_owner(E, mask, channel)
		return
	refresh_mark(E, mask, channel)

/// A legacy declared field (OM_FIELD, OM_FLAG_FIELD: a machine's `stat` bits, `on`, `locked`) was written through its generated setter, which
/// raises its channel without naming the var: the stat layer still hears it, so a contribution that reads the field (STAT_OPERABLE's
/// stat_bits_allow(), powered()) recomputes before the writer's next line, as it does for a TRACKED var.
/proc/om_field_written(datum/E, field)
	if(GLOB.stat_input_keys?[field] && field != GLOB.stat_writing)
		stat_inputs_changed(E, field)

/// FALSE when a refresh of E could not do anything: an atom (not a mob, which its species and traits can grant verbs)
/// whose type is known to derive nothing (no look, verbs, capabilities, type verbs or declared dependencies), with no
/// periodic work and no open window. The same rule om_raise_change() applies, so a setter on such an atom costs no
/// queue entry and no refresh.
/proc/refresh_wanted(datum/E)
	if(!isatom(E) || ismob(E) || E.refresh_queued || E.periodic_cadence || E.periodic_interval || LAZYLEN(E.open_tguis))
		return TRUE
	return GLOB.type_derives_cache[E.type] != 0

/// refresh_wanted() for an entity already in the queue (its refresh_queued is set, so it is not a reason to run).
/proc/refresh_wanted_queued(datum/E)
	if(!isatom(E) || ismob(E) || E.periodic_cadence || E.periodic_interval || LAZYLEN(E.open_tguis))
		return TRUE
	return GLOB.type_derives_cache[E.type] != 0

/// E itself has nothing to refresh, but an owner whose capability draws it still redraws (refresh_mark()'s owner rule).
/proc/refresh_mark_owner(datum/E, mask, channel)
	if(mask != DEP_ALL && !(mask & DEP_DRAW))
		return
	var/datum/owner = owner_of(E)
	if(!owner || QDELING(owner) || !isatom(owner) || !owner_draws_child(owner, E))
		return
	refresh_mark(owner, mask == DEP_ALL ? DEP_ALL : DEP_DRAW, channel)

/// A dispatched call on E finished (a timer, a periodic step): its derived procs re-run, as changed(E) does, but
/// no OM channel is raised. Nothing a dispatch can change is unannounced: what it writes through setters raises
/// its own channels. A blanket CHANGE_EXPLICIT here woke every pipeline that wakes on it (each life frame of a mob
/// and each machine frame) once per timer, for nothing it reads.
/proc/refresh_dispatched(datum/E)
	if(!E || QDELING(E) || E == GLOB.refresh_applying)
		return
	refresh_trace_note(E, CHANGE_EXPLICIT)
	if(E.rel_watchers && !E.refresh_queued)
		rel_notify_watchers(E)
	if(!refresh_wanted(E))
		refresh_mark_owner(E, DEP_ALL, CHANGE_EXPLICIT)
		return
	refresh_mark(E, DEP_ALL, CHANGE_EXPLICIT)

/// Queues E for the outputs in `mask`, and its owner up the chain for its look when one of the owner's
/// capabilities draws E. `channel` reaches on_state_changed() (refresh_bits) with a plain mark.
/proc/refresh_mark(datum/E, mask, channel = 0)
	var/datum/D = E
	for(var/depth in 1 to 8)
		if(mask & DEP_LEGACY)
			D.refresh_bits |= channel
		if(!D.refresh_queued)
			GLOB.refresh_queue += D
		D.refresh_queued |= mask
		// A selective mark reaches an owner only through the look (an owner never reads a child's should_run).
		if(mask != DEP_ALL && !(mask & DEP_DRAW))
			break
		// H2: the owner is marked only when one of its capabilities draws this child (a slot with
		// draws_var naming the var that holds it). Anything else stays local.
		var/datum/owner = owner_of(D)
		if(!owner || QDELING(owner) || !isatom(owner) || !owner_draws_child(owner, D))
			break
		D = owner
		if(mask != DEP_ALL)
			mask = DEP_DRAW

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
		// ALLOW(sys_dx_reactive_write): the derive probe notes the override; it runs only while GLOB.derive_probing
		GLOB.derive_probe_found |= TYPE_DERIVES_LOOK
	for(var/datum/capability/C as anything in caps_ordered(src, CAP_ORDER_DRAW))
		C.draw(src, look)
	look_layers_draw(src, look)
	present_draw(src, look) // the layers and draws the engine's capabilities declare (code/engine/present/outputs.dm)

/// TRUE while periodic_step(dt) should run on `periodic_cadence`. Re-evaluated on change.
/datum/proc/should_run()
	SHOULD_NOT_SLEEP(TRUE)
	return FALSE

/// The verbs to hide right now. Call ..() (capabilities hide theirs). Re-evaluated on change.
/atom/proc/hidden_verbs()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	if(GLOB.derive_probing && derive_called_by_override(callee.caller, "hidden_verbs"))
		// ALLOW(sys_dx_reactive_write): the derive probe notes the override; it runs only while GLOB.derive_probing
		GLOB.derive_probe_found |= TYPE_DERIVES_VERBS
	return caps_hidden_verbs(src)

/**
 * The verbs this atom has because of what it currently HAS (its capabilities, and for a mob its species
 * and traits), as opposed to type_verbs() (per type, static) and hidden_verbs() (hide by state).
 * Per instance and derived: re-evaluated on change and applied through the verb store; hidden_verbs()
 * still wins. Call ..() first (capabilities add their verbs()). Pure: read state, write nothing.
 *	/mob/living/carbon/human/granted_verbs()
 *		. = ..()
 *		if(dexterous_trait)
 *			. += /mob/living/proc/toggle_pass_table
 */
/atom/proc/granted_verbs()
	RETURN_TYPE(/list)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	if(GLOB.derive_probing && derive_called_by_override(callee.caller, "granted_verbs"))
		GLOB.derive_probe_found |= TYPE_DERIVES_VERBS
	. = list()
	for(var/datum/capability/C as anything in caps_all(src))
		var/list/native = C.verbs()
		if(native)
			. |= native

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
	if(GLOB.derive_side_probing && !derive_called_by_override(callee.caller, "on_state_changed"))
		// The derive probe notes the base was reached directly; it runs only while probing
		GLOB.derive_side_base_reached = TRUE
	return

/// Set while a type's first refresh probes whether it overrides push_to_rust() / on_state_changed().
GLOBAL_VAR_INIT(derive_side_probing, FALSE)
/// Set by the base push_to_rust() / on_state_changed() when the engine reached it directly (no override in between).
GLOBAL_VAR_INIT(derive_side_base_reached, FALSE)

// ---- the drain ----

/// Runs queued refreshes within the lane budget. TRUE when the queue is empty.
/proc/refresh_drain(datum/om/scheduler/sched)
	rx_drain() // change reactions (on_change / on_cross / observe) run before the outputs
	var/list/Q = GLOB.refresh_queue
	// review 2 M4: each entity refreshes at most once per drain; one re-queued by its own refresh (or
	// by a chain that comes back to it) waits for the next frame instead of spinning here.
	var/list/done = list()
	var/list/deferred
	var/i = 0
	while(i < length(Q))
		i++
		var/datum/D = Q[i]
		if(isnull(D))
			continue // a hard-deleted queued entity leaves a null entry
		if(done[D])
			LAZYADD(deferred, D)
			continue
		var/pending = D.refresh_queued
		D.refresh_queued = 0
		if(QDELETED(D))
			D.refresh_bits = 0
			continue
		if(!pending)
			continue // a stale duplicate: an earlier entry already ran its outputs
		if(!refresh_wanted_queued(D))
			// Every atom's first refresh is queued at init (caps_init()) before its type's verdict is in: the first
			// instance probes the type, and the rest, queued behind it, skip here once it is known to derive nothing.
			D.refresh_bits = 0
			continue
		done[D] = TRUE
		CHURN_COUNT(draws, D.type)
		var/bits = D.refresh_bits
		D.refresh_bits = 0
		GLOB.refresh_bench_drained++
		try
			refresh_one(D, bits, pending)
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

/// Every queued refresh now, ignoring the budget (tests, admin tools), then the UI pushes they queued. A
/// self-re-marking entity is refreshed a bounded number of times, then reported.
/proc/refresh_flush()
	var/passes = 0
	while(length(GLOB.refresh_queue))
		refresh_drain(null)
		if(++passes > 20)
			stack_trace("refresh_flush: still queued after 20 passes (a reactive proc re-marks its entity?): [jointext(GLOB.refresh_queue, ", ")]")
			for(var/datum/D as anything in GLOB.refresh_queue)
				D.refresh_queued = 0
				D.refresh_bits = 0
			GLOB.refresh_queue.Cut()
			break
	ui_push_flush()

/// One entity's refresh of the outputs in `mask` (DEP_*; everything by default): derive values, periodic
/// gate, look and hidden verbs, open windows, the Rust push, then on_state_changed.
/proc/refresh_one(datum/D, bits, mask = DEP_ALL)
	var/datum/outer = GLOB.refresh_running
	GLOB.refresh_running = D
	try
		refresh_one_inner(D, bits, mask)
	catch(var/exception/e)
		// Restore before the drain reports it: a stale refresh_running would flag every later mark of
		// D as a self-mark.
		GLOB.refresh_running = outer
		GLOB.derived_evaluating = 0
		GLOB.derive_probing = FALSE
		GLOB.derive_side_probing = FALSE
		throw e
	GLOB.refresh_running = outer
	if(!outer && length(GLOB.look_effects_due))
		look_effects_run()
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	// A full pass re-derived everything: the ignored changes it may have hidden are answered for.
	if(mask == DEP_ALL && length(GLOB.derived_ignored))
		GLOB.derived_ignored -= REF(D)
#endif

/proc/refresh_one_inner(datum/D, bits, mask)
	var/probing = FALSE
	var/probe_found = 0
	if(mask & DEP_VALUES)
		var/datum/derived_table/T = derived_table_of(D)
		if(T?.derived_vars)
			mask = derived_recompute(D, T, mask)
	if(mask & DEP_RUN)
		refresh_periodic(D)
	if(isatom(D) && (mask & DEP_DRAW))
		var/atom/A = D
		// A type known to draw nothing and hide nothing skips both (review 2 H3): capabilities can
		// draw and hide, and a type not seen yet is tried once and recorded.
		var/flags = type_derive_flags(A)
		var/may_draw = flags & (TYPE_DERIVES_LOOK | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING) || !isnull(A.look_key)
		// A mob may be granted verbs by its species and traits, which no type flag can know.
		var/may_hide = flags & (TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING) || A.refresh_hidden_verbs || A.refresh_granted_verbs || ismob(A)
		probing = flags & TYPE_DERIVES_PENDING
		if(probing)
			GLOB.derive_probing = TRUE
			GLOB.derive_probe_found = 0
		if(may_draw)
			refresh_look(A)
		if(may_hide)
			refresh_verbs(A)
			refresh_granted_verbs(A)
		if(probing)
			GLOB.derive_probing = FALSE
			probe_found = GLOB.derive_probe_found
		refresh_sweep_track(A)
	if(mask & DEP_UI)
		refresh_ui(D)
	// The side effects. While the type is probed, the base procs report whether the engine reached them directly: a type
	// that overrides either (with or without ..()) is recorded TYPE_DERIVES_SIDE, as is one whose probe skipped them.
	var/side = FALSE
	if(mask & DEP_PUSH)
		if(probing)
			GLOB.derive_side_probing = TRUE
			GLOB.derive_side_base_reached = FALSE
		DERIVED_EVAL_BEGIN
		D.push_to_rust()
		DERIVED_EVAL_END
		if(probing)
			side = side || !GLOB.derive_side_base_reached
	else
		side = TRUE
	if(mask & DEP_LEGACY)
		if(probing)
			GLOB.derive_side_probing = TRUE
			GLOB.derive_side_base_reached = FALSE
		D.on_state_changed(bits)
		if(probing)
			side = side || !GLOB.derive_side_base_reached
	else
		side = TRUE
	if(probing)
		GLOB.derive_side_probing = FALSE
		// Type-pure: the type overrides draw()/hidden_verbs()/granted_verbs()/the side effects or it doesn't, whatever
		// this instance's state drew or hid (review: never record a negative from one result).
		type_derive_record(D, probe_found & TYPE_DERIVES_LOOK, probe_found & TYPE_DERIVES_VERBS, side)

/// Queues a push of D's open tgui windows: at most one per window per tick, delivered in the kernel's phase R
/// (code/modules/tgui/ui_push.dm; tgui_data() runs inside the push, as an output).
/proc/refresh_ui(datum/D)
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	if(derived_is_exact(D))
		GLOB.derived_ui_flushes[REF(D)] += 1
#endif
	if(!LAZYLEN(D.open_tguis))
		return
	ui_push_mark(D)

/proc/refresh_periodic(datum/D)
	if(D.periodic_interval)
		periodic_interval_update(D)
		return
	if(!D.periodic_cadence)
		return
	DERIVED_EVAL_BEGIN
	var/want = !!D.should_run()
	DERIVED_EVAL_END
	var/running = om_task_periodic_running(D)
	if(want && !running)
		om_task_periodic(D, D.periodic_cadence)
	else if(!want && running)
		om_task_periodic_stop(D)

/// Builds A's look and applies it when its key changed. Returns the key.
/proc/refresh_look(atom/A, apply = TRUE)
	var/datum/look/L = GLOB.look_builder
	L.reset()
	DERIVED_EVAL_BEGIN
	A.draw(L)
	DERIVED_EVAL_END
	// Transient flashes (look_flash()) sit on top of whatever draw() described.
	var/datum/cap_engine_state/engine = A.cap_data?[/datum/cap_engine_state] // inline cap_engine_state_of(): every look refresh passes here
	if(engine)
		if(engine.look_flash_state)
			L.state(engine.look_flash_state)
		for(var/state in engine.look_flashes)
			L.overlay(state)
	if(!L.touched)
		if(apply && !isnull(A.look_key))
			// It drew before and draws nothing now: applying the empty look takes back everything the
			// last look set (overlays, filters, vis_contents, base properties).
			L.apply_to(A)
			A.look_key = null
		if(apply && A.cap_data?[/datum/cap_engine_state])
			look_watch_sync(A, null)
		return null
	var/key = L.change_key()
	if(apply)
		// What the draw read of other entities: a change on any of them redraws A (kept in line with every draw, applied or not).
		if(L.watched || A.cap_data?[/datum/cap_engine_state])
			look_watch_sync(A, L.watched)
		if(key != A.look_key)
			var/atom/outer = GLOB.refresh_applying
			GLOB.refresh_applying = A
			L.apply_to(A)
			GLOB.refresh_applying = outer
			A.look_key = key
			// The effects the draw named run once the refresh is over (look_effects_run()): they may write state.
			if(L.effects)
				GLOB.look_effects_due += list(list(A, L.effects))
	return key

/// Brings A's derived verb hides in line with hidden_verbs(). The verb store stays the only writer of a
/// verbs list: a hidden verb is one more reason verb_store_wants() says no, and only the keys whose
/// hidden state flipped are re-synced.
/proc/refresh_verbs(atom/A, apply = TRUE)
	DERIVED_EVAL_BEGIN
	var/list/hidden = A.hidden_verbs() || list()
	DERIVED_EVAL_END
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

/// Brings A's derived granted verbs in line with granted_verbs(); only the flipped keys are re-synced
/// through the verb store (which keeps hidden_verbs() winning).
/proc/refresh_granted_verbs(atom/A, apply = TRUE)
	var/list/granted = A.granted_verbs() || list()
	if(!length(granted) && !length(A.refresh_granted_verbs))
		return granted
	if(!apply)
		return granted
	var/list/was = A.refresh_granted_verbs || list()
	var/list/flipped = (was - granted) + (granted - was)
	A.refresh_granted_verbs = length(granted) ? granted : null
	if(length(flipped))
		verb_store_refresh(A, flipped)
	return granted

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
	if(isnull(A.look_key) && !A.refresh_hidden_verbs && !A.refresh_granted_verbs && !A.periodic_cadence && !derived_is_exact(A))
		return
	A.refresh_swept = TRUE
	GLOB.refresh_sweep_list[REF(A)] = TRUE

/// Re-checks up to `budget` swept atoms: a derived result that differs from what is applied means a
/// change was never marked. Production applies it; test builds report REFRESH DRIFT and fail.
/proc/refresh_sweep_step(budget = 50)
	// H3 / review 2 M3: test builds sweep everything strictly (drift fails the run). Production checks
	// only atoms a player can see or has open, at a small budget; skipping a far atom costs a scan,
	// not a check, so a full cycle over the near atoms takes seconds. A benchmark build (which also
	// defines UNIT_TESTS) measures the production audit, not the test sweep.
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
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
#if !defined(UNIT_TESTS) || defined(BENCHMARK)
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
	DERIVED_EVAL_BEGIN
	var/list/hidden = A.hidden_verbs() || list()
	DERIVED_EVAL_END
	var/list/was = A.refresh_hidden_verbs || list()
	if(length(hidden ^ was))
		drift += "hidden_verbs()"
	var/list/granted = A.granted_verbs() || list()
	var/list/was_granted = A.refresh_granted_verbs || list()
	if(length(granted ^ was_granted))
		drift += "granted_verbs()"
	if(A.periodic_cadence)
		DERIVED_EVAL_BEGIN
		var/wants = !!A.should_run()
		DERIVED_EVAL_END
		if(wants != om_task_periodic_running(A))
			drift += "should_run()"
	// A derive() value that no longer matches what its reads give.
	var/datum/derived_table/T = derived_table_of(A)
	for(var/datum/derived_var/V as anything in T?.derived_vars)
		DERIVED_EVAL_BEGIN
		var/value = call(A, V.proc_name)()
		DERIVED_EVAL_END
		if(value != A.vars[V.name])
			drift += "derive([V.name])"
	if(!length(drift))
		return FALSE
	var/msg = "REFRESH DRIFT: [A.type] [jointext(drift, ", ")] changed with no changed() mark[derived_drift_hint(A)]"
	GLOB.refresh_drift += msg
#if defined(UNIT_TESTS)
	if(!GLOB.refresh_drift_expected)
		stack_trace(msg)
#endif
	refresh_one(A, 0)
	return TRUE

GLOBAL_VAR_INIT(refresh_drift_expected, FALSE)


// ---- what a look does besides drawing: effects, watches and legacy redraws (doc/rewrite/final_api.html section 13) ----

/// Effects named by applied looks that have not run yet: list(atom, list(list(proc_ref, args...), ...)).
GLOBAL_LIST_EMPTY(look_effects_due)
/// Effects run so far (the draw framework tests read it).
GLOBAL_VAR_INIT(look_effects_ran, 0)

/// Runs the effects applied looks named (look.effect()), each as `proc_ref(args...)` on the holder, outside any output: they may write
/// state, start a sound loop or call another entity, and what they write raises its own marks (a redraw waits for the next pass).
/proc/look_effects_run()
	var/list/due = GLOB.look_effects_due
	GLOB.look_effects_due = list()
	for(var/list/entry in due)
		var/atom/holder = entry[1]
		if(QDELETED(holder))
			continue
		for(var/list/effect in entry[2])
			var/list/call_args = effect.Copy(2)
			GLOB.look_effects_ran++
			try
				call(holder, effect[1])(arglist(call_args))
			catch(var/exception/e)
				stack_trace("look effect [effect[1]] of [holder.type]: [e] ([e.file]:[e.line])")

/// Brings `A`'s subscriptions to other entities in line with what its draw reads now (`keys`: own keys, null for none). The record is kept
/// in the atom's engine state, which only an atom that has watched something (or kept a cooldown or a flash) owns.
/proc/look_watch_sync(atom/A, list/keys)
	var/datum/cap_engine_state/engine = keys ? cap_engine_state_make(A) : cap_engine_state_of(A)
	if(!engine)
		return
	var/list/was = engine.look_watching
	for(var/key in was)
		if(!(key in keys))
			var/datum/gone = own_locate(key)
			if(gone)
				rel_unobserve(gone, A)
	for(var/key in keys)
		if(!(key in was))
			var/datum/seen = own_locate(key)
			if(seen)
				rel_observe(seen, A)
	engine.look_watching = keys

/// Atoms whose type draws through update_icon() (a declared appearance or an override), by type: 1 yes, 0 no; unknown until its first redraw.
GLOBAL_LIST_EMPTY(type_legacy_draw)
/// Set while the first redraw of a type runs, to see whether the base update_icon() was reached by an override.
GLOBAL_VAR_INIT(update_icon_probing, FALSE)
GLOBAL_DATUM(update_icon_probe_target, /atom)
/// What the probe saw of the target's base update_icon(): reached with no override in between, or through an override's ..().
GLOBAL_VAR_INIT(update_icon_base_direct, FALSE)
GLOBAL_VAR_INIT(update_icon_base_via_override, FALSE)
/// The atom whose update_icon() runs on the presentation lane now: a redraw request it raises meanwhile is its own.
GLOBAL_DATUM(legacy_redrawing, /atom)

/**
 * A redraw request from code that does not know whether the type draws: `redraw(A)` is the spelling of `A.update_icon()` for every atom. A drawn
 * type is redrawn by the look refresh the request marks; a type that still draws through update_icon() (a declared appearance or an
 * override) also gets its update_icon() on the spot, as the call it replaces; a type that draws nothing costs a list read after its first
 * request. changed(A) is a state mark: it never runs a legacy update_icon() (the declared appearance watches do).
 */
/proc/redraw(atom/A)
	if(!A || QDELETED(A))
		return
	var/known = GLOB.type_legacy_draw[A.type]
	if((isnull(known) || known) && A != GLOB.legacy_redrawing) // null == 0 in DM: an unprobed type must not be taken for a probed one
		legacy_redraw(A)
	// The look only: no OM channel is raised, so the machine pipelines that wake on CHANGE_EXPLICIT stay asleep, as they did for update_icon().
	if(refresh_wanted(A))
		refresh_mark(A, DEP_DRAW)
	else
		refresh_mark_owner(A, DEP_DRAW, 0)

/// update_icon() of one atom through redraw(): the first of a type also learns whether it draws that way (the base update_icon() reached
/// directly, with no declared appearance, means it never did).
/proc/legacy_redraw(atom/A)
	var/atom/outer = GLOB.legacy_redrawing
	GLOB.legacy_redrawing = A
	var/probe = isnull(GLOB.type_legacy_draw[A.type])
	if(probe)
		GLOB.update_icon_probing = TRUE
		GLOB.update_icon_probe_target = A
		GLOB.update_icon_base_direct = FALSE
		GLOB.update_icon_base_via_override = FALSE
	try
		A.update_icon()
	catch(var/exception/e)
		GLOB.update_icon_probing = FALSE
		GLOB.update_icon_probe_target = null
		GLOB.legacy_redrawing = outer
		throw e
	if(probe)
		GLOB.update_icon_probing = FALSE
		GLOB.update_icon_probe_target = null
		var/datum/lifecycle_decls/decls = lifecycle_decls_of(A)
		// An override (its ..() reached the base, or the base was never reached) or a declared appearance: update_icon() draws.
		GLOB.type_legacy_draw[A.type] = (GLOB.update_icon_base_via_override || !GLOB.update_icon_base_direct || decls?.appearance_draws) ? 1 : 0
	GLOB.legacy_redrawing = outer

/// The base update_icon() was reached while a type is probed: directly (not through an override's ..()) means the type has no override.
/proc/legacy_probe_note(atom/who, callee/caller)
	if(who != GLOB.update_icon_probe_target)
		return // another atom's update_icon() reached from the target's
	if(derive_called_by_override(caller, "update_icon"))
		GLOB.update_icon_base_via_override = TRUE
	else
		GLOB.update_icon_base_direct = TRUE
