// destroy_transaction() (roadmap L1, doc/rewrite/lifecycle.md §2): the one
// place qdel() hands off to. Phases run in a fixed order; each is timed onto
// `trash.phase_ms` (doc §8's "per-phase destroy time" test). Contents (phase
// 3) and mind (phase 0.5) live in code/datums/containment/lifecycle.dm --
// they're container-specific. Links (phase 4) live in
// code/datums/lifecycle/links.dm. Everything else is here.
//
// No nullspace parking (DQ Medical requirement): nothing here ever moves an
// atom to nullspace "to finish later". Phase 3 runs while the holder still
// has a loc, so TRANSFER and SPILL always have a live destination to reach.

/// Runs `D`'s whole destruction. Called from qdel() only -- SHOULD_NOT_OVERRIDE
/// because the phase order encodes every ordering hazard the codebase used to
/// rely on ad-hoc Destroy() comments for. Returns what phase 7's Destroy()
/// (or, for a plain /datum with no override, the base no-op) returned.
/// Test/debug tracing: while GLOB.dq_lifecycle_trace_depth > 0, every phase of
/// every destroy transaction is logged, so a transaction that never returns
/// (a sleep or a runaway loop in a phase) shows the last phase it finished.
GLOBAL_VAR_INIT(dq_lifecycle_trace_depth, 0)
#define DQ_LIFECYCLE_TRACE(D, what) if(GLOB.dq_lifecycle_trace_depth) { log_world("LIFECYCLE_TRACE: [D.type] [ref(D)] [what]") }

/proc/destroy_transaction(datum/D, force, datum/qdel_item/trash)
	var/hint = QDEL_HINT_QUEUE
	var/aborted = FALSE
	GLOB.destroy_transaction_depth++
	try
		hint = destroy_transaction_phases(D, force, trash)
	catch(var/exception/e)
		// A runtime in any phase (often a Destroy() override touching state an
		// Initialize() that returned INITIALIZE_HINT_QDEL early never set up)
		// used to abandon the transaction: the atom kept its loc and contents,
		// stayed "being destroyed" forever, and a second qdel() was refused.
		// Report it, then finish what must happen for the object to be freed.
		aborted = TRUE
		dq_report_caught(e, "destroy transaction of [D?.type]")
		if(D)
			dq_lifecycle_finish_aborted(D)
	GLOB.destroy_transaction_depth--
	if(D && hint != QDEL_HINT_LETMELIVE)
		capability_runtime_forget(D)
	if(D && ismovable(D) && hint != QDEL_HINT_LETMELIVE)
		dq_lifecycle_release_loc(D, aborted)
	return hint

/// What an aborted destroy transaction still owes: declared refs scrubbed, the
/// datum out of the live world and its registries, its object-model state torn
/// down (timers, hooks, tasks, behaviours: an atom's dematerialize() does this,
/// any other datum needs dq_lifecycle_om_teardown()), OM handles released, and
/// a movable's contents deleted (as /atom/movable/Destroy() would have).
/proc/dq_lifecycle_finish_aborted(datum/D)
	try
		// A fault before phase 4 leaves ordinary owned fields intact, not re-set.
		// Dispose them by their declared policies before the leftover-state scrub.
		if(D.destroy_phase <= LIFECYCLE_PHASE_LINKS)
			own_teardown(D)
		dq_lifecycle_scrub(D)
		// Leave the registries and the live world (phase 7 may never have run).
		if(isatom(D))
			var/atom/A = D
			A.dematerialize()
		else
			D.leave_registries()
	catch(var/exception/e)
		dq_report_caught(e, "finishing the aborted destroy of [D.type]")
	// Mandatory runtime cleanup must still run if a child or registry hook faulted.
	try
		dq_lifecycle_om_teardown(D)
	catch(var/exception/runtime_error)
		dq_report_caught(runtime_error, "tearing down runtime state after the aborted destroy of [D.type]")
	try
		if(D.rx)
			rx_teardown(D)
	catch(var/exception/native_error)
		dq_report_caught(native_error, "tearing down native state after the aborted destroy of [D.type]")
	try
		if(ismovable(D))
			var/atom/movable/AM = D
			for(var/atom/movable/thing in contents_of(AM).Copy())
				qdel(thing)
	catch(var/exception/contents_error)
		dq_report_caught(contents_error, "disposing contents after the aborted destroy of [D.type]")

/// A destroyed movable leaves its loc (/atom/movable/Destroy() ends with
/// moveToNullspace()). One still somewhere had a Destroy() that skipped ..()
/// or runtimed: it is moved out here, so it never lingers on a turf where
/// nothing can delete it again.
/proc/dq_lifecycle_release_loc(atom/movable/AM, aborted)
	if(isnull(AM.loc))
		return
	if(!aborted)
		dq_lifecycle_report("LIFECYCLE: [AM.type] still in [AM.loc.type] after Destroy() (an override skipped ..()?); moved to nullspace")
	try
		AM.moveToNullspace()
	catch(var/exception/e)
		dq_report_caught(e, "moving the destroyed [AM.type] to nullspace")
	if(AM.loc)
		AM.loc = null // ALLOW(containment): last-resort nullspace after moveToNullspace() threw

/// The destroy transaction's steps, in order: the one declared sequence (DESTROY_STEP_* in
/// code/__defines/lifecycle.dm). destroy_transaction_phases() runs exactly this list; a step's
/// place in it is the only thing that decides when it runs (dq_destroy_sequence_tests.dm checks
/// the invariants: phases never go backwards except the effects' second half, and the contents
/// release check sits right after the contents steps, before links dispose of the ledger).
GLOBAL_LIST_INIT(destroy_step_sequence, list(
	DESTROY_STEP_GUARD, // phase 0: QDELETED(D) from here; the teardown guard refuses new work
	DESTROY_STEP_LEAVE_REGISTRIES, // non-atoms leave registries (atoms do it in dematerialize)
	DESTROY_STEP_MIND, // phase 0.5: minds, pre-order, whole tree (movables)
	DESTROY_STEP_UNBIND, // phase 1: Rust bindings, topology, heat bodies; before dematerialize
	DESTROY_STEP_DEMATERIALIZE, // phase 2: index leaves; an owned entity leaves its owner's var
	DESTROY_STEP_CONTENTS_RESOLVE, // phase 3: every slot's declared destroy policy, post-order
	DESTROY_STEP_CONTENTS_SPILL, // phase 3: OWN_SPILL movables drop out
	DESTROY_STEP_CONTENTS_CHECK_RELEASED, // phase 3: the check that it did, while the ledger exists
	DESTROY_STEP_LINKS, // phase 4: prerelease, on_destroy, owned values by policy, relations
	DESTROY_STEP_TEARDOWN, // phase 5: periodic work, screens, OM timers/hooks/tasks, handles
	DESTROY_STEP_EFFECTS, // phase 6: declared destroy effects
	DESTROY_STEP_DESTROY, // phase 7: the core Destroy() chain
	DESTROY_STEP_EFFECTS_AFTER, // phase 6's second half: neighbours that smooth against D
	DESTROY_STEP_SCRUB, // phase 8: re-set owned vars reported and deleted, cycles broken
	DESTROY_STEP_POSTCONDITION, // leak check (test builds, toggleable on servers)
))

/// How many destroy transactions are running (nested qdel()s inside a teardown count). While it
/// is positive, the teardown guard refuses writes touching dying entities silently
/// (code/datums/ownership/guard.dm).
GLOBAL_VAR_INIT(destroy_transaction_depth, 0)

/// Runs GLOB.destroy_step_sequence on D. Each step sets D.destroy_phase to its phase (never
/// lowering it) before it runs and is timed onto that phase.
/proc/destroy_transaction_phases(datum/D, force, datum/qdel_item/trash)
	DQ_LIFECYCLE_TRACE(D, "begin")
	// Indexed by LIFECYCLE_PHASE_* id, so it must have a slot per phase
	// (an empty lazy list made every phase write an out-of-bounds runtime).
	if(length(trash.phase_ms) < LIFECYCLE_PHASE_COUNT)
		trash.phase_ms = new /list(LIFECYCLE_PHASE_COUNT)

	var/hint = QDEL_HINT_QUEUE
	var/datum/destroy_effects_data/effects
	var/turf/effects_turf
	var/tick
	var/phase
	for(var/step in GLOB.destroy_step_sequence)
		phase = DESTROY_STEP_PHASE(step)
		if(D.destroy_phase < phase)
			D.destroy_phase = phase
		tick = world.tick_usage
		switch(step)
			if(DESTROY_STEP_GUARD)
				// From here QDELETED(D) is true (gc_destroyed is set), which is what stops
				// re-entrant qdel(D) (qdel()'s own check, above this call), and the teardown
				// guard refuses new ownership, relations, timers, hooks and tasks on D.
				D.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
				D.datum_flags |= DF_DESTROYING
				PUBLISH_LEGACY(D, /datum/notice/qdeleting, force)
				if(length(GLOB.notice_late_queue))
					notice_late_subject_deleting(D) // notices queued past the depth cap for D reach its observers now, while D is still whole
				ending_begin(D) // on_ending() hooks, lives_while() scopes, the ended notice with its cause (code/engine/lifeforms/lifetimes.dm)
			if(DESTROY_STEP_LEAVE_REGISTRIES)
				dq_lifecycle_leave_registries(D)
				continue // untimed, as before
			if(DESTROY_STEP_MIND)
				// A no-op until a body plan declares a TRANSFER(mind) slot_def (DQ Medical, O2).
				if(!ismovable(D))
					continue
				dq_lifecycle_resolve_minds(D)
			if(DESTROY_STEP_UNBIND)
				D.lifecycle_unbind()
				lifecycle_decls_unbind(D) // DECLARE_BIND releases (declarations.dm)
			if(DESTROY_STEP_DEMATERIALIZE)
				D.lifecycle_dematerialize()
				DQ_LIFECYCLE_TRACE(D, "lifecycle_dematerialize() returned")
				// An owned entity leaves its owner's var (ownership.md sec 1.5: no owner keeps a dying child).
				if(D.own_holder_ref)
					own_release_from_owner(D)
			if(DESTROY_STEP_CONTENTS_RESOLVE)
				// Children before parents: see code/datums/containment/lifecycle.dm's header.
				if(!ismovable(D))
					continue
				var/atom/movable/resolving = D
				resolving.dq_lifecycle_resolve_contents()
			if(DESTROY_STEP_CONTENTS_SPILL)
				if(!ismovable(D))
					continue
				own_spill_phase(D)
			if(DESTROY_STEP_CONTENTS_CHECK_RELEASED)
				if(!ismovable(D))
					continue
				var/atom/movable/checking = D
				checking.dq_lifecycle_check_released()
			if(DESTROY_STEP_LINKS)
				// Owned values disposed of by policy, relation edges and REF views cleared on
				// both ends (doc/rewrite/ownership.md, code/datums/ownership/).
				D.lifecycle_prerelease() // teardown that still reads the declared vars (links.dm)
				D.on_destroy(force) // the type's destroy hook: back-vars, partners and handles still live
				if(D.om_rec)
					entity_behaviours_on_destroy(D) // each attached behaviour's on_entity_destroy(E)
				if(ismovable(D))
					dq_lifecycle_leave_own_slot(D) // slot-exit hooks see live back-refs
				dq_lifecycle_clear_links(D)
			if(DESTROY_STEP_TEARDOWN)
				// Periodic work (om_task_periodic()), client screens, walk() loops, then the
				// object-model teardown: OM timers, hooks, tasks, deadlines, grants and
				// behaviours (entity_teardown_rest()) and OM handles. /datum/Destroy() (phase 7) only
				// clears the tag, closes tgui windows and does reference-tracking bookkeeping.
				dq_lifecycle_teardown(D)
			if(DESTROY_STEP_EFFECTS)
				// Declared destroy_effects data (L3). Under a batch (batch.dm) effects are merged
				// per turf and neighbour updates run once at the end.
				effects = D.destroy_effects()
				effects?.apply_per_atom(D)
				if(effects && !dq_batch_effects(D, effects))
					effects_turf = effects.apply(D)
			if(DESTROY_STEP_DESTROY)
				// The core Destroy() chain (the type's on_destroy() already ran in the links
				// step, while its declared links still read) (/datum, /atom, /atom/movable, ...
				// and the MC's controllers: the only Destroy() overrides
				// tools/ci/lifecycle_counts_lint.py allows). A type's declared destroy_hint
				// replaces the core's plain QDEL_HINT_QUEUE.
				hint = D.Destroy(force)
				if(isnull(D)) // Destroy() hard-deleted itself (rare; some override del()s src)
					return hint
				if(D.destroy_hint && hint == QDEL_HINT_QUEUE)
					hint = D.destroy_hint
			if(DESTROY_STEP_EFFECTS_AFTER)
				if(!effects_turf)
					continue
				effects.apply_after(D, effects_turf)
			if(DESTROY_STEP_SCRUB)
				// Null outbound declared owned/pair vars to break reference cycles, then hand D
				// to GC. Nothing is parked in nullspace.
				dq_lifecycle_scrub(D)
			if(DESTROY_STEP_POSTCONDITION)
				// leak_check.dm: nothing D still holds may be a deleted object that holds D back.
				if(GLOB.dq_lifecycle_leak_check && hint != QDEL_HINT_LETMELIVE)
					dq_lifecycle_postcondition(D)
				continue // untimed, as before
		dq_lifecycle_time(trash, phase, tick)
		DQ_LIFECYCLE_TRACE(D, "[DESTROY_STEP_NAME(step)] done")

	DQ_LIFECYCLE_TRACE(D, "end")
	return hint

#undef DQ_LIFECYCLE_TRACE

/// Phase 4, after on_destroy() and before the links clear: the dying movable
/// leaves its holder's ledger slot now, so its on_unslotted() hooks (a body
/// part's detach, which reads `owner`) run while BACK vars still name their
/// partners. It keeps its loc until Destroy() (phase 7) moves it out; that
/// move's note_exit() then finds no entry. The ledger never re-adopts it:
/// sync() skips things being deleted.
/proc/dq_lifecycle_leave_own_slot(atom/movable/AM)
	var/atom/holder = AM.loc
	var/datum/ledger/L = holder?.containment_ledger()
	if(!L?.entries[AM])
		return
	L.pending_exit_flags = LEDGER_MOVE_FORCED
	L.note_exit(AM)

/// Accumulates the milliseconds since `start_tick` onto phase `id`. Cheap:
/// one TICK_USAGE_TO_MS and one list write, mirroring how destroy_time
/// itself is already measured in qdel().
/proc/dq_lifecycle_time(datum/qdel_item/trash, id, start_tick)
	trash.phase_ms[id] += TICK_USAGE_TO_MS(start_tick)
	#ifdef BENCHMARK_DEEP_PROFILE
	benchmark_qdel_phase(id, TICK_USAGE_TO_MS(start_tick))
	#endif

// ---- Declared destroy behaviour ----

/// The QDEL_HINT_* this type hands the garbage collector after a normal destroy
/// (QDEL_HINT_IWILLGC for handle-like datums, QDEL_HINT_HARDDEL_NOW, ...). Set it
/// on the type instead of overriding Destroy() to return a hint. A type default:
/// no per-instance cost.
/datum/var/destroy_hint = QDEL_HINT_QUEUE

/// TRUE to refuse this qdel(): the object is left whole (checked before phase 0)
/// and qdel() returns it to life. Singletons and pooled objects that only a forced
/// qdel() may delete use LIFECYCLE_KEEP_UNLESS_FORCED(type); state-dependent
/// refusal overrides this. Must not sleep or change state.
/// The type's destroy hook, run at the start of phase 4, right after
/// lifecycle_prerelease() and before the links clear: contents are resolved
/// (phase 3), but BACK/BACKLIST/PAIR vars, owned children and OM handles
/// (om_handle_is) are all still live, so teardown can reach its owner and
/// partners. The core Destroy() chain runs later, in phase 7. The place for domain consequences only:
/// anything a DECLARE_REF line, lifecycle_unbind(), lifecycle_dematerialize(),
/// lifecycle_prerelease() or destroy_effects() expresses goes there instead.
/// Always call ..(). Returns nothing: the GC hint is destroy_hint.
/// Behaviours get the same hook as /datum/om/behaviour/proc/on_entity_destroy(E).
// ---- Phase 1: unbind (hook point) ----

/// Phase 1 (doc/rewrite/lifecycle.md §2): R10 entity bindings
/// (vg_entity_unbind), heat bodies and pipe/cable topology -- must precede
/// dematerialize. Types override it
/// to disconnect topology before the holder leaves the world (for example
/// /obj/machinery/atmospherics/lifecycle_unbind() tears down its pipe
/// connections). Must not sleep; call ..().
// ---- Phase 2: dematerialize (hook point) ----

/// Phase 2, for every datum, before a movable is released from its holder: the
/// hook for a type's own indexes that are not OM registries (registries are
/// left by dq_lifecycle_leave_registries() / an atom's dematerialize()). No
/// type overrides it today; the default does nothing. Must not sleep.
// ---- Phase 5: teardown ----

/// Ends any periodic work (om_task_periodic(), code/datums/om/periodic.dm),
/// releases HUD/screen objects from any client they're shown to, stops walk()
/// loops, and tears down the datum's object-model state.
/proc/dq_lifecycle_teardown(datum/D)
	if(D.periodic_pipe)
		om_task_periodic_stop(D)
	if(isatom(D))
		var/atom/AT = D
		AT.dq_lifecycle_release_screen()
		// A walk_towards()/walk() loop keeps an internal BYOND reference.
		if(ismovable(AT))
			walk(AT, 0)
	dq_lifecycle_om_teardown(D)

/// Removes `src` from any client's `screen` list it is shown on. Default: a
/// plain atom shows on nobody's screen. /obj/screen overrides this to leave
/// whichever hud/mob it was added to.
/atom/proc/dq_lifecycle_release_screen()
	return

/// The object-model teardown (phase 5, and an aborted transaction): every OM
/// timer, deadline, hook, task, grant and behaviour `D` has
/// (entity_teardown_rest(), code/datums/om/entity.dm), then its OM handles stop
/// resolving. Safe to call twice: both halves check their own state.
/proc/dq_lifecycle_om_teardown(datum/D)
	// Object model (code/datums/om/entity.dm): contributions and grants this
	// datum holds anywhere, its own store, behaviours (on_stop), deadlines, tasks.
	if(D.om_rec)
		entity_teardown_rest(D)
	// OM handles to D stop resolving (object_model_core.md §4.11).
	if(D.om_hid)
		entity_handle_release(D)
	// Phase 4 may have aborted before native runtime ownership was disposed.
	if(D.rx)
		rx_teardown(D)

// ---- Phase 6: effects ----

/// Declared destroy_effects data (L3, doc/rewrite/lifecycle.md §5): message,
/// sound, debris type, neighbour update. Declared with DESTROY_EFFECTS(PATH,
/// DATA); phase 6 of destroy_transaction() applies it (merged per turf under a
/// batch). Null: no effects.
/datum/proc/destroy_effects()
	return null

// ---- Phase 8: scrub ----

/// Phase 8: an owned var re-set during teardown is deleted and reported (own_scrub(), never a
/// silent null); REF views still set are unlinked. D is not parked anywhere, it is simply
/// handed to the GC from here.
/proc/dq_lifecycle_scrub(datum/D)
	own_scrub(D)

/datum/controller/lifecycle_registry_immortal()
	return FALSE
