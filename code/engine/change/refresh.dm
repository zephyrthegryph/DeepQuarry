// state_changed() and the refresh engine (doc/rewrite/dx_conventions.md §1, §3, §4).
//
// Derived things are plain procs: draw(look), hidden_verbs(), tgui_data(),
// push_to_rust(), on_state_changed(). state_changed(E) queues E, and everything that owns it up the owner
// chain, for one refresh at the end of the frame (the presentation lane). Dispatchers call state_changed()
// for you after every handler, timer, periodic step, prompt answer and ownership transfer; TRACKED
// setters call it with the var they wrote; a write outside all of those calls it by hand.
//
// What a queued entity re-derives is a bitmask in refresh_queued (DEP_*): a plain state_changed(E) marks
// everything, a tracked write on a type that declares its dependencies (derived.dm) marks only the
// outputs that read the var. The drain runs each marked output at most once per entity per frame.
//
// A background sweep re-checks entities with derived procs on a per-tick budget, in debug and test builds only (DQ_LOOK_AUDIT): a debug build
// corrects a missed mark within seconds and logs it, test builds fail the run and name the type and, when it can, the
// likely undeclared read (REFRESH DRIFT). A production build runs no audit and repairs nothing, so a missed mark or first draw stays visible
// as a stale look instead of being masked. In a test build the audit is always on: the strict staleness
// checker (staleness.dm) runs it on every entity it checks (everything that appeared during a test, every
// served draw and a rotating slice of the rest), so a test that makes a thing whose hidden verbs, granted
// verbs or derive() values follow state nothing published fails at its end.

/datum
	/// The outputs queued for a refresh this frame (DEP_* bits), 0 when not queued.
	var/tmp/refresh_queued = 0
	/// The channels raised since the last refresh (on_state_changed() reads them).
	var/tmp/refresh_bits = 0
	/// The refresh_drain() pass that last ran this entity's outputs (GLOB.refresh_drain_pass): an entity runs at most once per pass, and a mark that lands
	/// during its own run waits for the next pass.
	var/tmp/refresh_pass = 0

/// The atom whose Initialize() is running: state_changed() treats its writes as a not-yet-initialized atom's.
GLOBAL_DATUM(atom_initializing, /atom)
/// The atoms partway through their own Initialize() while a child's init (atom_initializing) runs inside it, outermost first. An outer atom's flags say it is
/// initialized from the head of its Initialize(), so without this list a write the child's init makes to it would enrol observers and queue refreshes early.
GLOBAL_LIST_EMPTY(atoms_init_outer)

/// Marks E changed: queues its refresh (and its owners', up the chain) and raises `channel` for OM
/// observers. The rare direct write outside a dispatched call or a TRACKED setter calls this.
/// `var_name` is the tracked var that state_changed (TRACKED setters, timed_set and the ownership accessors
/// pass it): a type that declares its dependencies (derived()) re-derives only the outputs that read
/// it, and marks the entities that hop to it; any other type, and a call without it, re-derives
/// everything.
/proc/state_changed(datum/E, channel = CHANGE_EXPLICIT, var_name)
	if(!E || QDELING(E))
		return
	OP_PURE_GUARD("[E.type][var_name ? ".[var_name]" : ""] was written")
	if(GLOB.census_on)
		census_state_note(E, var_name, caller)
	if(GLOB.state_batch_depth)
		state_batch_queue(E, channel, var_name)
		return
	// An atom that is not initialized yet (a map load holds every init until the Atoms system runs): its init queues its first full
	// refresh and attaches its derived values (caps_init()), and no observer, reaction or relation is enrolled on it before then. Its
	// writes publish nothing but the stat layer's recompute and a draw hop to an initialized holder: map load made 884 k of these calls
	// (server_bench_20261027.md, boot).
	if(isatom(E))
		var/atom/pending = E
		if(!(pending.flags & ATOM_INITIALIZED) || pending == GLOB.atom_initializing || (length(GLOB.atoms_init_outer) && (pending in GLOB.atoms_init_outer)))
			if(var_name && (GLOB.stat_input_keys?[var_name] || IS_LOOKUP_READ_KEY(var_name)) && var_name != GLOB.stat_writing)
				stat_inputs_changed(E, var_name)
			if(var_name && draw_hop_reads_var(var_name))
				draw_hop_published(E, var_name)
			GLOB.state_changed_preinit_skipped++
			return
	// Silent construction (E3): an atom between its Initialize() and its birth (its setup() rows, its starting occupants writing it) keeps the stat layer
	// and the draw hop live, makes sure its first refresh is queued, and notes the var for its birth (construction_birth()), which publishes it once.
	if(isatom(E) && (E.datum_flags & DF_CONSTRUCTING) && GLOB.silent_construction)
		if(var_name && (GLOB.stat_input_keys?[var_name] || IS_LOOKUP_READ_KEY(var_name)) && var_name != GLOB.stat_writing)
			stat_inputs_changed(E, var_name)
		if(var_name && draw_hop_reads_var(var_name))
			draw_hop_published(E, var_name)
		construction_note(E, var_name)
		return
	// What an atom under construction holds (its rx state, its reagents, its misc state, a vending product): nothing outside it can read the record
	// before the atom is born, so the write is noted on the atom and published once at its birth (construction_birth()), as the atom's own are.
	if(!isatom(E) && GLOB.silent_construction && (E.own_holder_ref || istype(E, /datum/rx_state)) && !E.change_listen && !E.rx?.observed)
		var/atom/builder = construction_owner(E)
		if(builder)
			if(var_name && (GLOB.stat_input_keys?[var_name] || IS_LOOKUP_READ_KEY(var_name)) && var_name != GLOB.stat_writing)
				stat_inputs_changed(E, var_name)
			if(var_name && draw_hop_reads_var(var_name))
				draw_hop_published(E, var_name)
			construction_note_held(builder, E, var_name)
			return
	if(GLOB.construction_census && var_name && isatom(E) && (E.datum_flags & DF_CONSTRUCTING))
		construction_census_write(E, var_name)
	if(GLOB.published_write_census && var_name)
		GLOB.published_write_rows["[E.type].[var_name]"]++ // the writes the startup counter (plan_reader_probes) counts, by type and var
	op_changed(E) // a cached menu or reach read of the op engine is stale now
	if(var_name)
		var/datum/rx_state/menu_state = E.rx
		if(menu_state?.menu_keys && !isnull(menu_state.menu_keys[var_name]))
			menu_state.menu_keys[var_name]++ // a cached Menu row read this key (op_menu_record_reads())
	// The stat layer: a var some stat reads recomputes it before this write's next line (code/engine/stats/recompute.dm).
	if(var_name && (GLOB.stat_input_keys?[var_name] || IS_LOOKUP_READ_KEY(var_name)) && var_name != GLOB.stat_writing)
		stat_inputs_changed(E, var_name)
	// observers only: entity_raise_change()'s own refresh hook would mark every output, undoing the mask below.
	if(E.change_listen & channel)
		entity_dispatch_change(E, channel)
	// The look applying itself (set_light, vis_contents) is presentation, not a state change.
	if(E == GLOB.refresh_applying)
		return
#if defined(UNIT_TESTS)
	// H5: a refresh that marks its own entity again is a feedback loop (a reactive proc wrote state).
	if(E == GLOB.refresh_running && !GLOB.ledger_adopting)
		// The writer's frames, innermost first: the runtime is caught by the drain, which keeps only its message.
		var/chain = ""
		for(var/callee/frame = caller; frame && length(chain) < 400; frame = frame.caller)
			chain += " <- [frame.proc]"
		var/msg = "REFRESH SELF-MARK: [E.type][var_name ? ".[var_name]" : ""] marked itself changed during its own refresh[chain]"
		GLOB.refresh_self_marks += msg
		if(!GLOB.refresh_self_mark_expected)
			stack_trace(msg)
	// Outputs must not write state: a tracked write while draw, hidden_verbs, tgui_data or a
	// derive_<var> runs is reported.
	if(var_name && GLOB.derived_evaluating)
		var/write_msg = "OUTPUT WROTE STATE: [E.type].[var_name] was written while an output (draw, hidden_verbs, tgui_data, derive_<var>) was running"
		GLOB.derived_write_violations += write_msg
		if(!GLOB.derived_write_expected)
			stack_trace(write_msg)
#endif
	// Demand-gated: a var nobody reads (no reaction, generated read, derived() entry or observer) publishes nothing.
	// The reader plan (plan.dm) names the classes of static readers that may read the var; the tables of the others are not probed.
	if(var_name)
		var/reader_bits = plan_reader_bits(var_name, E.type)
		GLOB.plan_reader_probes++
		if(rx_readers(E, var_name, reader_bits))
			publish_change(E, var_name, reader_bits)
	// A draw one container, turf or area hop away reads it (an item drawing its holder's state): it redraws (refs/hops.dm).
	if(var_name && draw_hop_reads_var(var_name))
		draw_hop_published(E, var_name)
	refresh_trace_note(E, channel)
	// Sources watching E through a relation view (rel_one/rel_many(watch = ...)) re-derive too. Only on
	// E's first mark this frame, and after E is marked itself (the mark is what makes the second mark a "not first"),
	// so two entities watching each other (two railings that draw each other) stop after one round.
	var/first_mark = E.rel_watchers && REFRESH_IDLE(E)
	var/mask = DEP_ALL
	if(var_name)
		mask = derived_mask(E, var_name)
		// A type that declares nothing still has generated plans: a var neither its draw nor its verb outputs read redraws nothing (plan.dm).
		if(mask == DEP_ALL && plan_spares_draw(E, var_name))
			mask &= ~DEP_DRAW
			GLOB.plan_spared_writes++
	// The staleness checker: the graph says no draw reads this var, so the applied look is served as it is (checked at the next presentation drain).
	if(var_name && GLOB.staleness_on && !(mask & DEP_DRAW))
		staleness_note_served(E, var_name)
	if(mask)
		if(!refresh_wanted(E))
			refresh_mark_owner(E, mask, channel)
		else
			refresh_mark(E, mask, channel)
	if(first_mark)
		rel_notify_watchers(E)

/// FALSE when a refresh of E could not do anything: an atom (not a mob, which its species and traits can grant verbs)
/// whose type is known to derive nothing (no look, verbs, capabilities, type verbs or declared dependencies), with
/// no open window. The same rule entity_raise_change() applies, so a setter on such an atom costs no
/// queue entry and no refresh.
/proc/refresh_wanted(datum/E)
	if(E.refresh_queued || LAZYLEN(E.open_tguis))
		return TRUE
	if(!isatom(E))
		return datum_refresh_wanted(E)
	if(ismob(E))
		return TRUE
	return GLOB.type_derives_cache[E.type] != 0

/// refresh_wanted() for an entity already in the queue (its refresh_queued is set, so it is not a reason to run).
/proc/refresh_wanted_queued(datum/E)
	if(LAZYLEN(E.open_tguis))
		return TRUE
	if(!isatom(E))
		return datum_refresh_wanted(E)
	if(ismob(E))
		return TRUE
	return GLOB.type_derives_cache[E.type] != 0

/// A refresh of a datum that is not an atom has no look and no verbs: it re-derives its derived() values (TYPE_DERIVES_DEPS) and runs the side
/// effects (push_to_rust(), on_state_changed()) a type overrides (TYPE_DERIVES_SIDE), and its windows, which refresh_wanted()
/// checks per instance. A type with none of them (a kernel histogram counting every tick, a system's bookkeeping, an rx_state, a vending product row)
/// has no live output: it costs no queue entry and no refresh for its tracked writes (doc/rewrite/proposals/demand_driven_refresh.md 2.1).
/proc/datum_refresh_wanted(datum/D)
	return !!(datum_derive_flags(D) & (TYPE_DERIVES_DEPS | TYPE_DERIVES_SIDE))

/// The TYPE_DERIVES_* of a datum's (not an atom's) type, in the same per-type memo as the atoms' (type_derive_flags()). Decided at first sight from
/// declarations (a derived() table, an override of push_to_rust()/on_state_changed() found by `analyze gen plans`), never by running a refresh:
/// instances written before any drain has run (a map load, 45 k datums at boot) used to wait in the queue for a probe to give the verdict.
/proc/datum_derive_flags(datum/D)
	var/known = GLOB.type_derives_cache[D.type]
	if(!isnull(known))
		return known
	. = 0
	if(derived_table_of(D))
		. |= TYPE_DERIVES_DEPS
	var/side = type_overrides_side_effects(D.type)
	if(isnull(side))
		return . | TYPE_DERIVES_SIDE // the generated tables are not built yet (very early boot): refresh it, and decide again later
	if(side)
		. |= TYPE_DERIVES_SIDE
	GLOB.type_derives_cache[D.type] = .

/// Whether `path` or an ancestor defines push_to_rust() or on_state_changed() (the generated list of such types). Null while the generated table is not built.
/proc/type_overrides_side_effects(path)
	return type_in_generated_owners(path, "generated_side_overrides")

/// The outputs of D that would do anything now (DEP_* bits): what its type derives and what the instance has open. A queued mask is judged as
/// `pending & refresh_live_outputs(D)`; refresh_wanted() is `live != 0` (doc/rewrite/proposals/demand_driven_refresh.md 2.1).
/proc/refresh_live_outputs(datum/D)
	. = 0
	if(LAZYLEN(D.open_tguis))
		. |= DEP_UI | DEP_UI_STATIC
	if(isatom(D))
		var/atom/A = D
		if(ismob(A))
			return . | DEP_ALL // a mob's species and traits grant verbs no type flag knows
		var/flags = type_derive_flags(A)
		if(flags & (TYPE_DERIVES_LOOK | TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING))
			. |= DEP_DRAW
		if(flags & (TYPE_DERIVES_DEPS | TYPE_DERIVES_PENDING))
			. |= DEP_VALUES
		if(flags & (TYPE_DERIVES_SIDE | TYPE_DERIVES_PENDING))
			. |= DEP_PUSH | DEP_LEGACY
		return
	var/flags = datum_derive_flags(D)
	if(flags & TYPE_DERIVES_DEPS)
		. |= DEP_VALUES
	if(flags & TYPE_DERIVES_SIDE)
		. |= DEP_PUSH | DEP_LEGACY

/// E itself has nothing to refresh, but an owner whose capability draws it still redraws (refresh_mark()'s owner rule).
/proc/refresh_mark_owner(datum/E, mask, channel)
	if(mask != DEP_ALL && !(mask & DEP_DRAW))
		return
	var/datum/owner = owner_of(E)
	if(!owner || QDELING(owner) || !isatom(owner) || !owner_draws_child(owner, E))
		return
	refresh_mark(owner, mask == DEP_ALL ? DEP_ALL : DEP_DRAW, channel)

/// A dispatched call on E finished (a timer, a periodic step): its derived procs re-run, as state_changed(E) does, but
/// no channel is raised. Nothing a dispatch can change is unannounced: what it writes through setters raises
/// its own channels. A blanket CHANGE_EXPLICIT here woke every pipeline that wakes on it (each life frame of a mob
/// and each machine frame) once per timer, for nothing it reads.
///
/// `spare_draw` (a timer's fire): the look and verbs of an atom (not a mob) are not re-run. Every var a draw or a verb output reads is
/// TRACKED (declared, or added by read-driven tracking, auto_tracked.dm), and a timer that wrote one already marked exactly that through
/// its setter; a plain var the call wrote is read by no draw. A redraw after every fire repainted turrets, power monitors and sensors
/// on each interval at idle (doc/rewrite/server_bench_20261027.md). The other outputs (values, windows, the Rust push,
/// on_state_changed) still re-run.
/proc/refresh_dispatched(datum/E, spare_draw = FALSE)
	if(!E || QDELING(E) || E == GLOB.refresh_applying)
		return
	refresh_trace_note(E, CHANGE_EXPLICIT)
	if(E.rel_watchers && REFRESH_IDLE(E))
		rel_notify_watchers(E)
	var/mask = DEP_ALL
	if(spare_draw && isatom(E))
		mask = DEP_ALL & ~DEP_DRAW
		GLOB.refresh_dispatched_draws_spared++
	if(!refresh_wanted(E))
		refresh_mark_owner(E, mask, CHANGE_EXPLICIT)
		return
	refresh_mark(E, mask, CHANGE_EXPLICIT)

/// Marks raised over all time; the MOVE_COST trace (code/domains/world_model/atom/move_cost.dm) diffs it over a step.
GLOBAL_VAR_INIT(refresh_marks_raised, 0)

/// Queues E for the outputs in `mask`, and its owner up the chain for its look when one of the owner's
/// capabilities draws E. `channel` reaches on_state_changed() (refresh_bits) with a plain mark.
/// An atom whose pending outputs are its look alone is filed in the draw queue, by the chunk it stands in (draw_queue.dm); any other entity is in the
/// refresh queue, which runs every output. A fresh atom of the boot map load waits in the boot hold (DF_BOOT_HELD) and is marked by the settle.
/proc/refresh_mark(datum/E, mask, channel = 0)
	GLOB.refresh_marks_raised++ // the MOVE_COST trace diffs it over a step
	if(GLOB.refresh_mark_probe_type && istype(E, GLOB.refresh_mark_probe_type))
		refresh_mark_probe_note(mask)
	var/datum/D = E
	for(var/depth in 1 to 8)
		if(D.datum_flags & DF_BOOT_HELD)
			GLOB.boot_held_marks++ // it owes its whole first draw: the settle makes it, once, from what the atom is then
			break
		if(mask & DEP_LEGACY)
			D.refresh_bits |= channel
		var/idle = !D.refresh_queued
		// A real mark: no longer the type's default state. Not one the atom's own construction makes: its setup() hooks and a map-loaded atom's
		// after_init() entries run in an init frame (DF_INIT_OPEN) and write the state its first draw reads, as Initialize() does. That first
		// draw is already queued (DEP_CREATED), so such a write is part of it, and the type can still be sampled and stamped at boot (look_stamp.dm).
		var/construction = (D.refresh_queued & DEP_CREATED) && (D.datum_flags & DF_INIT_OPEN)
		D.refresh_queued = (D.refresh_queued & ~(construction ? 0 : DEP_CREATED)) | mask
		if(idle)
			GLOB.draw_n["dirtied"]++
		if(refresh_eager(D))
			refresh_queue_push(D) // one entry however often it is marked
		else if(idle)
			draw_file(D)
		// A selective Rust push (a rust_push read changed, native_resync() after a bind) also waits in the push queue, which phase S drains
		// before the native step: the presentation lane's drain runs after it, so the frame would step on the old settings.
		// Only a type that defines push_to_rust() or on_state_changed() (the generated list) has a push to run early: for any other type the entry would be
		// a queue slot for nothing, and every new item that sets a trait in its setup() would take one.
		if((mask & DEP_PUSH) && mask != DEP_ALL && refresh_pushes(D))
			GLOB.refresh_push_queue[D] = TRUE // keyed: one entry however often it is marked, whatever else it has pending
		// A selective mark reaches an owner only through the look (an owner never reads a child's window data).
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

/// Whether what `D` owes is run by the refresh queue (every output, now) rather than filed in the draw queue (its look alone, nearest a viewer first): a
/// datum that is no atom, a mob, an atom with any live output besides its look, and everything before the boot settle (it samples the queue by type).
/proc/refresh_eager(datum/D)
	if(!isatom(D) || !GLOB.boot_created_settled)
		return TRUE
	var/beside_look = D.refresh_queued & ~(DEP_DRAW | DEP_CREATED)
	return beside_look && (beside_look & refresh_live_outputs(D))

/// Marks of held atoms the boot hold took (the boot log reads it).
GLOBAL_VAR_INIT(boot_held_marks, 0)

GLOBAL_LIST_EMPTY(refresh_queue)
/// A queued datum's slot -> its absolute place in the queue (refresh_queue_base + its index when it was appended). The entry of a deleted datum is found in one step
/// and nulled (refresh_forget()), and the drain takes a key out when it consumes the entry. The base grows by what the drain cuts off the front, so the
/// places of the entries left do not move; the queue itself stays one flat list.
GLOBAL_ALIST_EMPTY(refresh_queue_at)
GLOBAL_VAR_INIT(refresh_queue_base, 0)

/// Appends D to the refresh queue and records where.
/proc/refresh_queue_push(datum/D)
	if(D.destroy_phase >= LIFECYCLE_PHASE_SLOTS_RELEASED)
		return // its destroy transaction is over: nothing is left to refresh, and a slot made for it now would hold it for good
	var/list/Q = GLOB.refresh_queue
	var/id = slot_of(D) // keyed by slot: an index keyed by the datum would be a second reference to it, which would be a second holder of it
	if(id)
		var/at = GLOB.refresh_queue_at[id]
		if(!isnull(at))
			var/pos = at - GLOB.refresh_queue_base
			if(pos >= 1 && pos <= length(Q) && Q[pos] == D)
				return // its entry is still ahead of the drain: a second one would be a duplicate refresh_queue_drop() never finds, pinning D after it dies
	Q += D
	if(id)
		GLOB.refresh_queue_at[id] = GLOB.refresh_queue_base + length(Q)

/// Takes D's entry out of the queue (nulled; the drain skips a null) and forgets where it was. Returns TRUE when it had one.
/proc/refresh_queue_drop(datum/D)
	var/slot = slot_known(D)
	var/id = slot ? GLOB.refresh_queue_at[slot] : null
	if(isnull(id))
		return FALSE
	GLOB.refresh_queue_at -= slot
	var/list/Q = GLOB.refresh_queue
	var/pos = id - GLOB.refresh_queue_base
	GLOB.refresh_forget_scans++
	var/steps = 1
	if(pos < 1 || pos > length(Q) || Q[pos] != D)
		// The queue was changed from outside (a test replaced it, an entry was removed): the place is stale, so look for the entry.
		pos = Q.Find(D)
		steps += length(Q)
	if(pos)
		Q[pos] = null
	GLOB.refresh_forget_scan_steps += steps
	GLOB.refresh_forget_scan_max = max(GLOB.refresh_forget_scan_max, steps)
	return TRUE

/// Replaces the queue contents with `kept` (the boot settle and park drop entries), recording every place again.
/proc/refresh_queue_replace(list/kept)
	var/list/Q = GLOB.refresh_queue
	Q.Cut()
	GLOB.refresh_queue_at = alist()
	GLOB.refresh_queue_base = 0
	for(var/datum/D as anything in kept)
		refresh_queue_push(D)
/// The entities marked for a Rust push (DEP_PUSH) since the last phase S: refresh_drain_pushes() runs them before the native step.
GLOBAL_LIST_EMPTY(refresh_push_queue)

/// The queue entries dropped for a deleted or drawn datum (refresh_queue_drop()): how many, the steps they took in all, and the most one took. One step each
/// unless the queue was changed from outside; a mass delete (an explosion, a z-level unload) that turned it into a scan would show here (an unbounded scan of the
/// boot backlog took 995,428 steps for 25 deletes, the longest 200,171).
GLOBAL_VAR_INIT(refresh_forget_scans, 0)
GLOBAL_VAR_INIT(refresh_forget_scan_steps, 0)
GLOBAL_VAR_INIT(refresh_forget_scan_max, 0)

/// Whether D's type has a push to run (it defines push_to_rust() or on_state_changed()); true while the generated table is not built yet.
/proc/refresh_pushes(datum/D)
	var/side = type_overrides_side_effects(D.type)
	return isnull(side) || side

/// engine_forget(): a dying datum leaves the refresh queues, which hold it by reference: the push queue is keyed by it, and the main queue's entry is found by
/// the place recorded when it was appended and nulled (the drain skips a null). Idempotent.
/proc/refresh_forget(datum/D)
	if(isnull(GLOB.refresh_queue_at) || isnull(GLOB.refresh_push_queue)) // a datum deleted while the globals are still being made (a screen object, the uplink's abstract items) meets no queue yet
		return
	GLOB.refresh_push_queue -= D
	refresh_queue_drop(D)
	if(D.datum_flags & DF_BOOT_HELD)
		boot_created_forget(D)
	if(D.refresh_queued)
		draw_unfile(D)
	D.refresh_queued = 0
	D.refresh_bits = 0
/// Pushes refresh_drain_pushes() has run (tests, the tick meter's census).
GLOBAL_VAR_INIT(refresh_pushes_drained, 0)

/// Phase S (kernel.dm): every pending Rust push now, so this tick's native step reads the settings DM wrote since the last frame. The push leaves
/// the entity's other pending outputs (look, UI) queued for the presentation lane; a push already run by a refresh is skipped (its bit is clear).
/proc/refresh_drain_pushes()
	var/list/Q = GLOB.refresh_push_queue
	if(!length(Q))
		return
	GLOB.refresh_push_queue = list()
	for(var/datum/D as anything in Q)
		if(isnull(D) || !(D.refresh_queued & DEP_PUSH))
			continue
		D.refresh_queued &= ~DEP_PUSH
		if(QDELETED(D))
			continue
		GLOB.refresh_pushes_drained++
		try
			refresh_one(D, 0, DEP_PUSH)
		catch(var/exception/e)
			dq_report_caught(e, "push of [D.type]")

/// Timer fires whose owner's look was not re-run (refresh_dispatched(spare_draw)).
GLOBAL_VAR_INIT(refresh_dispatched_draws_spared, 0)
/// state_changed() calls on atoms still waiting for their init during a map load, answered without publishing (the boot bench reads it).
GLOBAL_VAR_INIT(state_changed_preinit_skipped, 0)
/// The number of the last refresh_drain() pass (the stamp of datum/refresh_pass).
GLOBAL_VAR_INIT(refresh_drain_pass, 0)
/// A type whose marks are counted by where they came from (the draw-queue test's re-queue census, or an admin's question); null: off.
GLOBAL_VAR_INIT(refresh_mark_probe_type, null)
/// "caller <- caller's caller" -> marks.
GLOBAL_LIST_EMPTY(refresh_mark_probe_sources)

/proc/refresh_mark_probe_note(mask)
	var/chain = (mask & DEP_DRAW) ? "DRAW: " : ""
	var/n = 0
	for(var/callee/frame = caller?.caller; frame && n < 4; frame = frame.caller)
		chain += "[n ? " <- " : ""][frame.proc]"
		n++
	GLOB.refresh_mark_probe_sources[chain] += 1
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

/// Handles (handle_of()) of entities whose marks are being traced (the admin verb turns one on), so a
/// forgotten trace keeps nothing alive. Empty: tracing costs one check.
GLOBAL_ALIST_EMPTY(refresh_traced)

/proc/refresh_trace_note(datum/E, channel)
	if(!length(GLOB.refresh_traced))
		return
	var/ref_text = handle_of(E)
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
	for(var/datum/capability/C as anything in caps_ordered(src, CAP_ORDER_DRAW))
		C.draw(src, look)
	look_layers_draw(src, look)
	present_draw(src, look) // the layers and draws the engine's capabilities declare (code/engine/present/outputs.dm)

/// The verbs to hide right now. Call ..() (capabilities hide theirs). Re-evaluated on change.
/atom/proc/hidden_verbs()
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
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
	. = list()
	for(var/datum/capability/C as anything in caps_all(src))
		var/list/native = C.verbs()
		if(native)
			. |= native

/// Side effects of a state change (a Rust device sync, a network rebuild), coalesced to once per
/// frame. `bits` are the channels raised since the last refresh. Never call it by hand.
/datum/proc/on_state_changed(bits)
	SHOULD_NOT_SLEEP(TRUE)
	return

// ---- the drain ----

/// Runs queued refreshes within the lane budget. TRUE when the queue is empty.
/proc/refresh_drain(datum/time_scheduler/sched)
	rx_drain() // change reactions (on_change / on_cross / observe) run before the outputs
	var/list/Q = GLOB.refresh_queue
	var/datum/km_attr/attr = (sched?.meter || km_meter()).attr
	// review 2 M4: each entity refreshes at most once per drain; one re-queued by its own refresh (or
	// by a chain that comes back to it) waits for the next frame instead of spinning here. The pass stamp (refresh_pass) replaces a per-drain
	// list of the entities already run: a nested drain takes its own pass number, as it had its own list.
	var/pass = ++GLOB.refresh_drain_pass
	var/list/deferred
	var/i = 0
	if(sched && length(Q) && sched.over_tick_limit() && GLOB.draw_n["starved"] < DRAW_STARVED_MAX)
		// One refresh cannot be split: a pass that finds the tick already spent starts none (draw_drain() has the same rule and the same starvation guard).
		GLOB.draw_n["starved"]++
		GLOB.draw_n["budget_skips"]++
		return FALSE
	if(length(Q))
		GLOB.draw_n["starved"] = 0
	while(i < length(Q))
		i++
		var/datum/D = Q[i]
		if(isnull(D))
			continue // a hard-deleted queued entity leaves a null entry
		var/queued_slot = slot_known(D)
		if(queued_slot && GLOB.refresh_queue_at[queued_slot] == GLOB.refresh_queue_base + i)
			GLOB.refresh_queue_at -= queued_slot // this entry is consumed (an older duplicate of it leaves the newer one's place alone)
		if(D.refresh_pass == pass)
			LAZYADD(deferred, D)
			continue
		refresh_run(D, pass, sched, attr)
		if(sched?.out_of_budget() && i < length(Q))
			Q.Cut(1, i + 1)
			GLOB.refresh_queue_base += i
			for(var/datum/later as anything in deferred)
				refresh_queue_push(later)
			return FALSE
	Q.Cut()
	GLOB.refresh_queue_base = 0 // every place was given back as its entry was consumed
	for(var/datum/later as anything in deferred)
		refresh_queue_push(later)
	if(deferred)
		return FALSE
	return TRUE

/// Runs the outputs `D` has pending, now (its entry in a queue is consumed by the caller): the refresh queue's entries and the draw queue's. An entry whose
/// atom has nothing pending any more (it was run since, by the other queue) is skipped. The first refresh of a fresh atom of a stamped type (look_stamp.dm)
/// does nothing; the first one of a type nobody sampled records its verdict.
/proc/refresh_run(datum/D, pass, datum/time_scheduler/sched, datum/km_attr/attr)
	var/pending = D.refresh_queued
	D.refresh_queued = 0
	if(QDELETED(D))
		D.refresh_bits = 0
		return
	if(!pending)
		return // a stale duplicate: an earlier entry already ran its outputs
	var/fresh = pending & DEP_CREATED
	pending &= ~DEP_CREATED
	if(fresh && type_look_stamped(D))
		// Queued at creation before its type's verdict was in, and the type's default look is empty: nothing to draw (look_stamp.dm).
		D.refresh_bits = 0
		GLOB.type_look_stamp_skipped++
		return
	if(!refresh_wanted_queued(D))
		// Every atom's first refresh is queued at init (caps_init()) before its type's verdict is in: the first
		// instance probes the type, and the rest, queued behind it, skip here once it is known to derive nothing.
		D.refresh_bits = 0
		return
	D.refresh_pass = pass
	CHURN_COUNT(draws, D.type)
	var/bits = D.refresh_bits
	D.refresh_bits = 0
	GLOB.refresh_bench_drained++
	var/attr_start = TICK_USAGE
	var/draw_ledger = km_ledger_enter(KM_CAT_DRAW, D.type, km_attr_reason(pending | fresh))
	try
		refresh_one(D, bits, pending)
		if(fresh)
			type_look_stamp_record(D)
	catch(var/exception/e)
		if(sched)
			sched.report_caught(e, "refresh of [D.type]: [e] ([e.file]:[e.line])")
		else
			dq_report_caught(e, "refresh of [D.type]")
	km_ledger_leave(draw_ledger)
	attr.note(KA_KIND_DRAW, KM_SYS_APPEARANCE, D.type, km_attr_reason(pending | fresh), TICK_USAGE_TO_MS(attr_start))

/// Every queued refresh and every filed draw now, ignoring the budget (tests, admin tools), then the UI pushes they queued. A
/// self-re-marking entity is refreshed a bounded number of times, then reported.
/proc/refresh_flush()
	var/passes = 0
	while(length(GLOB.refresh_queue) || length(GLOB.draw_buckets))
		refresh_drain(null)
		draw_drain(null)
		if(++passes > 20)
			stack_trace("refresh_flush: still queued after 20 passes (a reactive proc re-marks its entity?): [jointext(GLOB.refresh_queue, ", ")] and [draw_depth()] filed")
			for(var/datum/D as anything in GLOB.refresh_queue)
				D.refresh_queued = 0
				D.refresh_bits = 0
			refresh_queue_replace(null)
			for(var/key in GLOB.draw_buckets)
				for(var/atom/A as anything in GLOB.draw_buckets[key])
					if(A)
						A.refresh_queued = 0
						A.refresh_bits = 0
			GLOB.draw_buckets = alist()
			GLOB.draw_filed = alist()
			break
	world.presentation_flush()

/// Draws A's look now, then applies the overlay update. A draw normally waits for the next frame; a caller that builds a mob and
/// reads its icon in the same call (a preview mannequin, a hologram dummy, a job icon) draws before it reads.
/proc/draw_now(atom/A)
	if(!QDELETED(A))
		refresh_one(A, 0, DEP_DRAW)
		A.ImmediateOverlayUpdate()

/// One entity's refresh of the outputs in `mask` (DEP_*; everything by default): derive values,
/// look and hidden verbs, open windows, the Rust push, then on_state_changed.
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
	if(mask & DEP_VALUES)
		var/datum/derived_table/T = derived_table_of(D)
		if(T?.derived_vars)
			mask = derived_recompute(D, T, mask)
	if(isatom(D) && (mask & DEP_DRAW))
		var/atom/A = D
		// A type known to draw nothing and hide nothing skips both (review 2 H3): capabilities can draw and hide; what the type
		// itself overrides is a generated fact (type_derive_flags()), pending only before the generated tables exist.
		var/flags = type_derive_flags(A)
		var/may_draw = flags & (TYPE_DERIVES_LOOK | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING) || !isnull(A.rx?.look_key)
		// A mob may be granted verbs by its species and traits, which no type flag can know.
		var/may_hide = flags & (TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING) || A.rx?.refresh_hidden_verbs || A.rx?.refresh_granted_verbs || ismob(A)
		if(may_draw)
			refresh_look(A)
		if(may_hide)
			refresh_verbs(A)
			refresh_granted_verbs(A)
		refresh_sweep_track(A)
	if(mask & DEP_UI_STATIC)
		refresh_ui_static(D) // a full update carries the data too
	else if(mask & DEP_UI)
		refresh_ui(D)
	if(mask & DEP_PUSH)
		call_output(D, "push_to_rust", TYPE_PROC_REF(/datum, push_to_rust))
	if(mask & DEP_LEGACY)
		D.on_state_changed(bits)

/// Queues a push of D's open tgui windows: at most one per window per tick, delivered in the kernel's phase R
/// (code/library/ui/tgui/ui_push.dm; tgui_data() runs inside the push, as an output).
/proc/refresh_ui(datum/D)
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	if(derived_is_exact(D))
		GLOB.derived_ui_flushes[REF(D)] += 1
#endif
	if(!LAZYLEN(D.open_tguis))
		return
	D.presentation_refresh_windows()

/// Resends D's open windows their static data (ui_static_data()) with their data: something ui_static_data() reads changed.
/proc/refresh_ui_static(datum/D)
	if(!LAZYLEN(D.open_tguis))
		return
	D.presentation_refresh_static()


/// Builds A's look and applies it when its key changed. Returns the key. An atom whose inputs a finished look was built from is served that look
/// (look_cache.dm): its draw does not run. Every draw's cost is noted by type (look_cost_note()).
/proc/refresh_look(atom/A, apply = TRUE)
	var/started = TICK_USAGE_REAL
	var/cache_key = apply ? look_cache_key(A) : null
	if(cache_key)
		var/datum/look/hit = GLOB.look_cache[cache_key]
		if(hit)
			. = look_cache_serve(A, hit)
			look_cost_note(A.type, TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), TRUE)
#if defined(UNIT_TESTS)
			look_cache_verify(A, hit)
#endif
			return .
	. = refresh_look_draw(A, apply, cache_key)
	look_cost_note(A.type, TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), FALSE)

/// refresh_look()'s draw: builds the look, applies it when its key changed (`apply`), and holds it in the cache under `cache_key` when it may be. Returns the key.
/proc/refresh_look_draw(atom/A, apply, cache_key)
	var/datum/look/L = GLOB.look_builder
	L.reset()
	GLOB.look_builds++
	call_output(A, "draw", TYPE_PROC_REF(/atom, draw), L)
	// Transient flashes (look_flash()) sit on top of whatever draw() described.
	var/datum/cap_engine_state/engine = capability_data(A)?[/datum/cap_engine_state] // inline cap_engine_state_of(): every look refresh passes here
	if(engine)
		if(engine.look_flash_state)
			L.state(engine.look_flash_state)
		for(var/state in engine.look_flashes)
			L.overlay(state)
	if(!L.touched)
		if(apply && !isnull(A.rx?.look_key))
			// It drew before and draws nothing now: applying the empty look takes back everything the
			// last look set (overlays, filters, vis_contents, base properties, its light). Taking them back is presentation too.
			var/atom/outer_empty = GLOB.refresh_applying
			GLOB.refresh_applying = A
			L.apply_to(A)
			GLOB.refresh_applying = outer_empty
			rx_of(A).look_key = null
			if(engine?.look_watchers)
				look_published(A, engine)
		// A draw that shows nothing yet may still have read other entities (look.watch()): their changes are what bring its layers in.
		if(apply && (L.watched || L.watched_looks || capability_data(A)?[/datum/cap_engine_state]))
			look_watch_sync(A, L.watched, L.neighbour_types, L.watched_looks, L.watched_worn)
		return null
	var/key = L.change_key()
	if(cache_key)
		if(!engine && look_cache_storable(L))
			look_cache_store(cache_key, L, key)
			GLOB.look_cache_misses++
		else
			GLOB.look_cache_bypassed++
	if(apply)
		// What the draw read of other entities: a change on any of them redraws A (kept in line with every draw, applied or not).
		if(L.watched || L.watched_looks || capability_data(A)?[/datum/cap_engine_state])
			look_watch_sync(A, L.watched, L.neighbour_types, L.watched_looks, L.watched_worn)
		if(key != A.rx?.look_key)
			refresh_look_count(A, isnull(A.rx?.look_key) ? "first" : "changed")
			var/atom/outer = GLOB.refresh_applying
			GLOB.refresh_applying = A
			L.apply_to(A)
			GLOB.refresh_applying = outer
			rx_of(A).look_key = key
			// The effects the draw named run once the refresh is over (look_effects_run()): they may write state.
			if(L.effects)
				GLOB.look_effects_due += list(list(A, L.effects))
			// The atoms whose draw composes this one's look hear that it changed (look.watch_look()).
			if(engine?.look_watchers)
				look_published(A, engine)
		else
			refresh_look_count(A, "same")
	return key

/// Brings A's derived verb hides in line with hidden_verbs(). The verb store stays the only writer of a
/// verbs list: a hidden verb is one more reason verb_store_wants() says no, and only the keys whose
/// hidden state flipped are re-synced.
/proc/refresh_verbs(atom/A, apply = TRUE)
	var/list/hidden = call_output(A, "hidden_verbs", TYPE_PROC_REF(/atom, hidden_verbs)) || list()
	if(!length(hidden) && !length(A.rx?.refresh_hidden_verbs))
		return hidden
	if(!apply)
		return hidden
	var/list/was = A.rx?.refresh_hidden_verbs || list()
	var/list/flipped = (was - hidden) + (hidden - was)
	rx_of(A).refresh_hidden_verbs = length(hidden) ? hidden : null
	if(length(flipped))
		verb_store_refresh(A, flipped)
	return hidden

/// Brings A's derived granted verbs in line with granted_verbs(); only the flipped keys are re-synced
/// through the verb store (which keeps hidden_verbs() winning).
/proc/refresh_granted_verbs(atom/A, apply = TRUE)
	var/list/granted = call_output(A, "granted_verbs", TYPE_PROC_REF(/atom, granted_verbs)) || list()
	if(!length(granted) && !length(A.rx?.refresh_granted_verbs))
		return granted
	if(!apply)
		return granted
	var/list/was = A.rx?.refresh_granted_verbs || list()
	var/list/flipped = (was - granted) + (granted - was)
	rx_of(A).refresh_granted_verbs = length(granted) ? granted : null
	if(length(flipped))
		verb_store_refresh(A, flipped)
	return granted

// ---- the background sweep ----

/// Atoms with something derived (a look, hidden verbs), as ref text -> TRUE. Refs,
/// not the atoms: the sweep list never keeps a deleted atom alive (it would hard-delete every drawn
/// atom); a ref that no longer names a swept atom is dropped when the sweep reaches it.
GLOBAL_LIST_EMPTY(refresh_sweep_list)
GLOBAL_VAR_INIT(refresh_sweep_index, 1)
/// The audit runs one step per this much world time: a step is up to ten dry draws, and one per presentation drain (every tick) was a third of an idle server's kernel time.
#define REFRESH_SWEEP_INTERVAL (0.5 SECONDS)
GLOBAL_VAR_INIT(refresh_sweep_next, 0)
/// Audit steps that ran, and the ones the interval skipped (a periodic log line and the idle-tolerance test read them).
GLOBAL_VAR_INIT(refresh_sweep_ran, 0)
GLOBAL_VAR_INIT(refresh_sweep_skipped, 0)
/// Applied looks by what they did: "first" (the atom's first draw), "changed" (a new key), "same" (drawn again to the same key: wasted work). Keyed "kind" and "kind [type]".
GLOBAL_LIST_EMPTY(refresh_look_stats)
GLOBAL_VAR_INIT(refresh_look_log_next, 0)

/// Logs the applied-look counters every five minutes (REFRESH LOOKS). Every build does: it is the record of first draws, changed looks and wasted redraws.
/proc/refresh_look_log_step()
	if(COOLDOWN_FINISHED(GLOB, refresh_look_log_next))
		COOLDOWN_START(GLOB, refresh_look_log_next, 5 MINUTES)
		log_world("REFRESH LOOKS: [refresh_look_stats_text()]")

#ifdef DQ_LOOK_AUDIT
/// TRUE when the audit may take a step now (and starts the wait for the next one).
/proc/refresh_sweep_due()
	if(!COOLDOWN_FINISHED(GLOB, refresh_sweep_next))
		GLOB.refresh_sweep_skipped++
		return FALSE
	COOLDOWN_START(GLOB, refresh_sweep_next, REFRESH_SWEEP_INTERVAL)
	GLOB.refresh_sweep_ran++
	refresh_look_log_step()
	return TRUE
#endif

/// Counts one applied look: by kind, and by kind and type.
/proc/refresh_look_count(atom/A, kind)
	var/list/stats = GLOB.refresh_look_stats
	stats[kind] = (stats[kind] || 0) + 1
	var/typed = "[kind] [A.type]"
	stats[typed] = (stats[typed] || 0) + 1

/// The look counters as text: the totals and the `top` busiest kind-and-type rows.
/proc/refresh_look_stats_text(top = 8)
	var/list/stats = GLOB.refresh_look_stats
	var/list/rows = list()
	for(var/key in stats)
		if(findtext(key, " "))
			rows += key
	rows = sortTim(rows, GLOBAL_PROC_REF(cmp_refresh_look_rows), FALSE)
	var/text = "first [stats["first"] || 0], changed [stats["changed"] || 0], same [stats["same"] || 0]; audit steps [GLOB.refresh_sweep_ran] ran, [GLOB.refresh_sweep_skipped] skipped; [draw_rates_text()]; [draw_stats_text()]; queue forget scans [GLOB.refresh_forget_scans] ([GLOB.refresh_forget_scan_steps] steps, longest [GLOB.refresh_forget_scan_max]); [look_cache_text()]; [look_cost_text(5)]"
	for(var/i in 1 to min(top, length(rows)))
		text += "; [rows[i]] x[stats[rows[i]]]"
	return text

/proc/cmp_refresh_look_rows(a, b)
	return GLOB.refresh_look_stats[b] - GLOB.refresh_look_stats[a]
/// Drift reports this round (the drift test reads them).
GLOBAL_LIST_EMPTY(refresh_drift)


/proc/refresh_sweep_track(atom/A)
	if(A.rx?.refresh_swept)
		return
	if(isnull(A.rx?.look_key) && !A.rx?.refresh_hidden_verbs && !A.rx?.refresh_granted_verbs && !derived_is_exact(A))
		return
	rx_of(A).refresh_swept = TRUE
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
	// Test builds sweep every swept atom strictly, so they keep the index. Production audits only what a client can see and finds those atoms by
	// walking the range of the clients' tiles (refresh_sweep_collect()): registering each of a hundred thousand atoms here cost one REF() apiece
	// (about half a second of the first minutes after boot) for an audit nobody was in range of.
	GLOB.refresh_sweep_list[REF(A)] = TRUE
#endif
	staleness_track(A)

/// Re-checks up to `budget` swept atoms: a derived result that differs from what is applied means a
/// change was never marked. A debug build repairs it and logs REFRESH DRIFT; test builds report it and fail. Production has no audit.
/proc/refresh_sweep_step(budget = 50)
#if defined(DQ_LOOK_AUDIT) && !defined(BENCHMARK)
	// H3 / review 2 M3: test builds sweep everything strictly (drift fails the run). Production checks
	// only atoms a player can see or has open, at a small budget; skipping a far atom costs a scan,
	// not a check, so a full cycle over the near atoms takes seconds (a debug build outside the tests).
#if defined(UNIT_TESTS)
	var/scan_budget = budget
	var/list/L = GLOB.refresh_sweep_list
	var/checked = 0
	var/scanned = 0
	while(checked < budget && scanned < scan_budget && length(L))
		if(GLOB.refresh_sweep_index > length(L))
			GLOB.refresh_sweep_index = 1
		var/atom/A = locate(L[GLOB.refresh_sweep_index])
		if(!isatom(A) || QDELETED(A) || !A.rx?.refresh_swept)
			L.Cut(GLOB.refresh_sweep_index, GLOB.refresh_sweep_index + 1)
			continue
		GLOB.refresh_sweep_index++
		scanned++
		// Queued here: its refresh is pending, not missed.
		if(A.refresh_queued)
			continue
		checked++
		refresh_check_drift(A)
#else
	if(!refresh_sweep_due())
		return
	// A debug build samples nothing: the drain draws everything that changed, and the strict staleness checker (staleness.dm) is the test builds' audit.
#endif
#else
	// Production (and a benchmark build) audits nothing and repairs nothing; only the look counters are logged.
	refresh_look_log_step()
#endif

#ifdef DQ_LOOK_AUDIT
/// Whether A's applied outputs still match what its derived procs give now. `check_draw` FALSE leaves the look to the caller (the strict staleness
/// checker draws it dry and compares it itself, with the culprit var named).
/proc/refresh_check_drift(atom/A, check_draw = TRUE)
	var/list/drift = list()
	if(check_draw)
		var/key = refresh_look(A, apply = FALSE)
		if(key != A.rx?.look_key)
			drift += "draw() [refresh_key_difference(A.rx?.look_key, key)]"
	var/list/hidden = call_output(A, "hidden_verbs", TYPE_PROC_REF(/atom, hidden_verbs)) || list()
	var/list/was = A.rx?.refresh_hidden_verbs || list()
	if(length(hidden ^ was))
		drift += "hidden_verbs()"
	var/list/granted = call_output(A, "granted_verbs", TYPE_PROC_REF(/atom, granted_verbs)) || list()
	var/list/was_granted = A.rx?.refresh_granted_verbs || list()
	if(length(granted ^ was_granted))
		drift += "granted_verbs()"
	// A derive() value that no longer matches what its reads give.
	var/datum/derived_table/T = derived_table_of(A)
	for(var/datum/derived_var/V as anything in T?.derived_vars)
		var/value = call_output(A, "derive", V.proc_name)
		if(value != A.vars[V.name])
			drift += "derive([V.name])"
	if(!length(drift))
		return FALSE
	var/msg = "REFRESH DRIFT: [A.type] [jointext(drift, ", ")] changed with no state_changed() mark[derived_drift_hint(A)]"
	GLOB.refresh_drift += msg
	// A debug build logs the report too (a look the audit had to repair is a mark somebody forgot): the first few per type, with the running total.
	var/static/list/drift_logged = list()
	drift_logged["[A.type]"]++
	if(drift_logged["[A.type]"] <= 3)
		log_world("[msg] (#[drift_logged["[A.type]"]] of this type)")
#if defined(UNIT_TESTS)
	if(!GLOB.refresh_drift_expected && !GLOB.staleness_expected)
		stack_trace(msg)
#endif
	refresh_one(A, 0)
	return TRUE
#endif

GLOBAL_VAR_INIT(refresh_drift_expected, FALSE)

/// Presentation transport boundary: coalescing and concrete windows live downstream.
/world/proc/presentation_flush()
	return 0

/datum/proc/presentation_refresh_windows()
	return 0

/// Resends the open windows' static data with their data (library: code/library/present/ui_transport.dm).
/datum/proc/presentation_refresh_static()
	return 0


// ---- what a look does besides drawing: effects and watches (doc/rewrite/final_api.html section 13) ----

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
				dq_report_caught(e, "look effect [effect[1]] of [holder.type]")

/// Brings `A`'s subscriptions to other entities in line with what its draw reads now (`keys`: slots, null for none). The record is kept
/// in the atom's engine state, which only an atom that has watched something (or kept a cooldown or a flash) owns.
/proc/look_watch_sync(atom/A, list/keys, list/neighbour_types, alist/look_keys, list/worn_keys)
	var/datum/cap_engine_state/engine = (keys || look_keys) ? cap_engine_state_make(A) : cap_engine_state_of(A)
	if(!engine)
		return
	var/list/was = engine.look_watching
	for(var/key in was)
		if(!(key in keys))
			var/datum/gone = slot_datum(key)
			if(gone)
				rel_unobserve(gone, A)
	for(var/key in keys)
		if(!(key in was))
			var/datum/seen = slot_datum(key)
			if(seen)
				rel_observe(seen, A)
	engine.look_watching = keys
	engine.look_neighbour_types = neighbour_types
	// look.watch_worn(): what the draw shows worn or held is read whole while it does (rx_readers()).
	var/list/worn_was = engine.look_watching_worn
	for(var/key in worn_was)
		if(!(key in worn_keys))
			var/datum/worn_gone = slot_datum(key)
			if(worn_gone?.rx?.worn_watched)
				worn_gone.rx.worn_watched--
	for(var/key in worn_keys)
		if(!(key in worn_was))
			var/datum/worn_seen = slot_datum(key)
			if(worn_seen)
				rx_of(worn_seen).worn_watched++
	engine.look_watching_worn = worn_keys
	// look.watch_look(): the atoms whose look this draw composes. Only their look_published() reaches A, never their other changes.
	var/list/was_looks = engine.look_watching_looks
	for(var/key in was_looks)
		if(!(key in look_keys))
			var/atom/gone_look = slot_datum(key)
			if(isatom(gone_look))
				look_unsubscribe(gone_look, A)
	for(var/key in look_keys)
		if(!(key in was_looks))
			var/atom/seen_look = slot_datum(key)
			if(isatom(seen_look))
				look_subscribe(seen_look, A)
	engine.look_watching_looks = look_keys

/// The atom's look is gone (it is being deleted): what it showed worn or held is no longer read whole on its account.
/proc/look_worn_release(atom/A)
	var/list/shown = cap_engine_state_of(A)?.look_watching_worn
	if(!length(shown))
		return
	for(var/key in shown)
		var/datum/worn_gone = slot_datum(key)
		if(worn_gone?.rx?.worn_watched)
			worn_gone.rx.worn_watched--
	cap_engine_state_of(A).look_watching_worn = null

/// `watcher`'s draw composes `target`'s look: look_published(target) marks it. One call, one count; look_unsubscribe() takes it back.
/proc/look_subscribe(atom/target, atom/watcher)
	var/datum/cap_engine_state/theirs = cap_engine_state_make(target)
	var/key = SLOT(watcher)
	if(!theirs.look_watchers)
		theirs.look_watchers = alist()
	theirs.look_watchers[key] = (theirs.look_watchers[key] || 0) + 1

/// TRUE while `composer`'s draw composes `target`'s look (look.watch_look(target)). A draw that shows the atom wearing or holding it asks this, so two
/// atoms that compose each other (a human holding the doll that shows them) do not chase each other's looks round and round.
/proc/look_composes(atom/composer, atom/target)
	READS_FROM()
	var/list/watching = cap_engine_state_of(composer)?.look_watching_looks
	return !!(watching && (SLOT(target) in watching))

/proc/look_unsubscribe(atom/target, atom/watcher)
	var/datum/cap_engine_state/theirs = cap_engine_state_of(target)
	if(!theirs?.look_watchers)
		return
	var/key = SLOT(watcher)
	var/count = theirs.look_watchers[key]
	if(count > 1)
		theirs.look_watchers[key] = count - 1
	else
		theirs.look_watchers -= key
		UNSETEMPTY(theirs.look_watchers)

/**
 * `A` shows a different look now (refresh_look applied one, or a mob's worn layers changed): the atoms whose draw composes it (look.watch_look())
 * are marked, and nobody else. A watcher that is gone is dropped from the record here. `engine` is A's engine record when the caller has it.
 */
/proc/look_published(atom/A, datum/cap_engine_state/engine)
	engine = engine || cap_engine_state_of(A)
	if(!engine?.look_watchers)
		return
	engine.look_serial++
	var/list/gone
	for(var/key in engine.look_watchers)
		var/atom/watcher = slot_datum(key)
		if(!isatom(watcher) || QDELING(watcher))
			LAZYADD(gone, key)
			continue
		// Its draw is queued and nothing else: a state_changed() would also reach whatever watches the watcher through a relation, which for two atoms that
		// compose each other (a human holding the doll that shows them) marks the one whose look was just published, during its own refresh.
		refresh_mark(watcher, DEP_DRAW)
	if(gone)
		engine.look_watchers -= gone
		UNSETEMPTY(engine.look_watchers)

/// A mover entered or left an atom some draw watches through look.neighbours() (a turf): the watchers that look for a type the mover is redraw.
/proc/look_neighbour_moved(atom/T, atom/movable/mover)
	for(var/key in T.rel_watchers)
		var/atom/watcher = slot_datum(key)
		if(!isatom(watcher) || QDELING(watcher))
			continue
		var/list/types = cap_engine_state_of(watcher)?.look_neighbour_types
		var/seen = FALSE // a watcher that asked for no neighbours (look.watch(container)) is not told of every mover
		for(var/type in types)
			if(istype(mover, type))
				seen = TRUE
				break
		if(seen)
			state_changed(watcher)

/// Where two look keys part (drift reports): the text around the first difference, so the part that moved is named.
/proc/refresh_key_difference(was, now)
	was = "[was]"
	now = "[now]"
	var/at = 1
	var/shortest = min(length(was), length(now))
	while(at <= shortest && text2ascii(was, at) == text2ascii(now, at))
		at++
	var/from = max(1, at - 40)
	return "(drawn: ...[copytext(was, from, at + 60)]... now: ...[copytext(now, from, at + 60)]...)"

// ---- silent construction (doc/rewrite/proposals/init_plan.md, E3) ----

/// TRUE: an atom's writes between its Initialize() and its birth are noted, not published (state_changed()). The parity test runs both ways.
GLOBAL_VAR_INIT(silent_construction, TRUE)
/// Writes noted under construction, and the vars their births published (the boot bench reads both).
GLOBAL_VAR_INIT(construction_writes_noted, 0)
GLOBAL_VAR_INIT(construction_writes_published, 0)

/// state_changed() of an atom under construction: its first refresh is queued if it is not, and a var some reader may follow is noted once for the birth.
/proc/construction_note(atom/A, var_name)
	GLOB.construction_writes_noted++
	if(!A.refresh_queued)
		refresh_mark(A, DEP_ALL)
	if(!var_name || !plan_reader_bits(var_name, A.type))
		return
	A.datum_flags |= DF_CONSTRUCT_NOTED
	// On the atom's own rx state (key "self"): nothing is keyed by a handle, so construction gives the atom no slot.
	var/datum/rx_state/S = rx_of(A)
	if(!S.construction_held)
		S.construction_held = list()
	var/list/vars_of = S.construction_held["self"]
	if(!vars_of)
		vars_of = list()
		S.construction_held["self"] = vars_of
	vars_of[var_name] = TRUE

/// The atom under construction that holds E, or null: the atom whose Initialize() is running (or one an inner init interrupted) for its rx state; the
/// owner its stamp names for a record it owns directly in a var of its own. Nothing here makes a slot: a record a holder drops without a qdel must
/// not be kept alive by the slot table, and a fresh holder keeps no slot until something names it.
/proc/construction_owner(datum/E)
	if(istype(E, /datum/rx_state))
		var/atom/A = GLOB.atom_initializing
		if(A?.rx == E && (A.datum_flags & DF_CONSTRUCTING))
			return A
		for(var/atom/outer as anything in GLOB.atoms_init_outer)
			if(outer.rx == E && (outer.datum_flags & DF_CONSTRUCTING))
				return outer
		return null
	var/datum/H = slot_datum(E.own_holder_ref) // the owner already has its slot: the stamp is one
	if(!isatom(H))
		return null
	var/atom/holder = H
	if(!(holder.datum_flags & DF_CONSTRUCTING) || !(E.own_slot in holder.vars) || holder.vars[E.own_slot] != E)
		return null // a member of an owned list, or a stale stamp: published as any write is
	return holder

/// The key of E among the records atom A holds: "rx" for its rx state, else the var of A that holds it.
#define CONSTRUCTION_HELD_KEY(E) (istype(E, /datum/rx_state) ? "rx" : E.own_slot)

/// Notes var_name of E, a record atom A holds, for A's birth: on A's own rx state (held key -> var names), so nothing is keyed by a handle.
/proc/construction_note_held(atom/A, datum/E, var_name)
	GLOB.construction_writes_noted++
	if(!var_name || !plan_reader_bits(var_name, E.type))
		return
	A.datum_flags |= DF_CONSTRUCT_NOTED
	var/datum/rx_state/S = rx_of(A)
	if(!S.construction_held)
		S.construction_held = list()
	var/key = CONSTRUCTION_HELD_KEY(E)
	var/list/vars_of = S.construction_held[key]
	if(!vars_of)
		vars_of = list()
		S.construction_held[key] = vars_of
	vars_of[var_name] = TRUE

/// Publishes once each var of a record A holds that was written under A's construction and that a reader follows.
/proc/construction_birth_held(atom/A)
	var/datum/rx_state/S = A.rx
	var/list/held = S?.construction_held
	if(!held)
		return
	S.construction_held = null
	if(QDELETED(A))
		return
	for(var/key in held)
		var/datum/E
		if(key == "self")
			E = A
		else if(key == "rx")
			E = A.rx
		else if(key in A.vars)
			E = A.vars[key]
		if(!isdatum(E) || QDELETED(E))
			continue
		var/list/names = held[key]
		for(var/var_name in names)
			var/bits = plan_reader_bits(var_name, E.type)
			if(rx_readers(E, var_name, bits))
				publish_change(E, var_name, bits)
				GLOB.construction_writes_published++

/// InitAtom(), after the setup() rows: the atom is born. Each var it wrote under construction that a reader follows is published once (reactions,
/// lifecycle forms, operations waiting on it, and the on_change hooks that read it, against the baseline taken at init: the hook census found 31
/// (type, hook) pairs whose content relies on firing for what setup wrote (an alarm's election, a meter's needle, lights, SMES levels, grass edges).
/proc/construction_birth(atom/A)
	if(!(A.datum_flags & DF_CONSTRUCT_NOTED))
		A.datum_flags &= ~DF_CONSTRUCTING
		return
	A.datum_flags &= ~(DF_CONSTRUCTING | DF_CONSTRUCT_NOTED)
	construction_birth_held(A) // its own writes ("self") and those of the records it holds, each published once

// ---- init frames ----

/// An atom's init frame past Initialize() is one bit of its own datum_flags (DF_INIT_OPEN): its setup() hooks running (setup_run()), or a map-loaded
/// atom's after_init() entries waiting for the load frame to close and then running (after_init_flush()). A write inside the frame is the atom's own
/// construction, not a change (refresh_mark() keeps the creation mark). On the atom itself, so it holds nothing and needs no slot: one deleted inside
/// its own frame takes the bit with it (init_open_forget() clears it as well). The engine never opens a second frame inside the first; one that does
/// (a test, a hook that re-enters) is counted here by slot until the outer frame ends. A real global: atoms initialize while the globals are still being made.
GLOBAL_REAL(init_open, /alist)

/// `A` enters an init frame that runs its own code after Initialize() returned.
/proc/init_open_begin(atom/A)
	if(!(A.datum_flags & DF_INIT_OPEN))
		A.datum_flags |= DF_INIT_OPEN
		return
	var/slot = slot_of(A)
	if(!slot)
		return
	if(!init_open)
		init_open = alist()
	init_open[slot] = (init_open[slot] || 0) + 1

/// The frame ends. An atom deleted inside its frame has lost the bit already.
/proc/init_open_end(atom/A)
	if(!(A.datum_flags & DF_INIT_OPEN))
		return
	var/slot = A.handle_slot
	var/nested = slot && init_open?[slot]
	if(nested)
		if(nested > 1)
			init_open[slot] = nested - 1
		else
			init_open -= slot
		return
	A.datum_flags &= ~DF_INIT_OPEN

/// engine_forget(): a datum is being destroyed, its slot still valid. Its open init frame (an atom deleted inside its own setup) is dropped, so it is not
/// taken for one still setting up, and neither is the slot's next holder. Idempotent: a second call finds nothing.
/proc/init_open_forget(datum/D)
	D.datum_flags &= ~DF_INIT_OPEN
	if(init_open && D.handle_slot)
		init_open -= D.handle_slot

// ---- the hook-firing census of construction writes (debug tracing; -params bench_construction_census=1 with silent_construction off) ----

/// TRUE records which on_change hooks fire for a value an atom's own construction wrote (construction_census_fire()). Off unless the world asks.
GLOBAL_VAR_INIT(construction_census, FALSE)
/// atom handle -> var names its construction wrote (published, silent construction off).
GLOBAL_ALIST_EMPTY(construction_census_writes)
/// "type hook-signature" -> how many times it fired for such a value.
GLOBAL_LIST_EMPTY(construction_census_fires)

/proc/construction_census_write(atom/A, var_name)
	var/handle = handle_of(A)
	var/list/vars_of = GLOB.construction_census_writes[handle]
	if(!vars_of)
		vars_of = list()
		GLOB.construction_census_writes[handle] = vars_of
	vars_of[var_name] = TRUE

/// A hook fires on E: when it reads a var E's construction wrote, it is counted (once per atom and hook) and the var is forgotten for that hook.
/proc/construction_census_fire(datum/E, datum/hook/H)
	var/handle = handle_of(E)
	var/list/vars_of = GLOB.construction_census_writes[handle]
	if(!vars_of)
		return
	for(var/key in H.reads)
		if(vars_of[key])
			var/row = "[E.type] [H.entry ? copytext(H.entry.sig, 1, 120) : H.type] (via [key])"
			GLOB.construction_census_fires[row] = (GLOB.construction_census_fires[row] || 0) + 1
			return

/// Logs the census, busiest first (the boot calls it after the first drains; a test or admin may call it any time).
/proc/construction_census_report()
	var/list/rows = GLOB.construction_census_fires
	log_world("CONSTRUCTION CENSUS: [length(rows)] (type, hook) pair(s) fired for a value the atom's own construction wrote")
	var/list/sorted = sortTim(rows.Copy(), GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	for(var/row in sorted)
		log_world("CONSTRUCTION CENSUS: [sorted[row]]x [row]")

/// TRUE counts every published write (a write past the pre-init and construction branches) by "type.var" (debug tracing; -params
/// bench_published_census=1 turns it on for the map load).
GLOBAL_VAR_INIT(published_write_census, FALSE)
GLOBAL_LIST_EMPTY(published_write_rows)

/proc/published_write_census_report()
	var/list/sorted = sortTim(GLOB.published_write_rows.Copy(), GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	var/total = 0
	for(var/row in sorted)
		total += sorted[row]
	log_world("PUBLISHED WRITE CENSUS: [length(sorted)] type.var row(s), [total] write(s), probes [GLOB.plan_reader_probes]")
	var/shown = 0
	for(var/row in sorted)
		log_world("PUBLISHED WRITE CENSUS: [sorted[row]]x [row]")
		if(++shown >= 60)
			break
