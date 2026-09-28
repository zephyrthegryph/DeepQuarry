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
	if(D && ismovable(D) && hint != QDEL_HINT_LETMELIVE)
		dq_lifecycle_release_loc(D, aborted)
	return hint

/// What an aborted destroy transaction still owes: declared refs scrubbed,
/// and a movable's contents deleted (as /atom/movable/Destroy() would have).
/proc/dq_lifecycle_finish_aborted(datum/D)
	try
		dq_lifecycle_scrub(D)
		// Leave the registries and the live world (phase 7's /atom/Destroy()
		// may never have run): a deleted object left in a registry is a hard-delete source.
		if(isatom(D))
			var/atom/A = D
			A.dematerialize()
		else
			D.leave_registries()
		if(D.om_hid)
			om_handle_release(D)
		if(ismovable(D))
			var/atom/movable/AM = D
			for(var/atom/movable/thing in contents_of(AM).Copy())
				qdel(thing)
	catch(var/exception/e)
		dq_report_caught(e, "finishing the aborted destroy of [D.type]")

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

/// The phases of destroy_transaction(), in order.
/proc/destroy_transaction_phases(datum/D, force, datum/qdel_item/trash)
	DQ_LIFECYCLE_TRACE(D, "begin")
	// Indexed by LIFECYCLE_PHASE_* id, so it must have a slot per phase
	// (an empty lazy list made every phase write an out-of-bounds runtime).
	if(length(trash.phase_ms) < LIFECYCLE_PHASE_COUNT)
		trash.phase_ms = new /list(LIFECYCLE_PHASE_COUNT)

	// Phase 0: guard. From here QDELETED(D) is true (gc_destroyed is set),
	// which is what stops re-entrant qdel(D) (qdel()'s own check, above this
	// call) and any pair/partner loop that already checks QDELETED().
	var/tick = world.tick_usage
	D.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
	D.datum_flags |= DF_DESTROYING
	OM_EMIT(D, /datum/om/event/qdeleting, force)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_GUARD, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_GUARD done")

	// Phase 2 for datums that aren't atoms: leave registries (atoms leave in
	// their own phase 2, through dematerialize).
	dq_lifecycle_leave_registries(D)

	if(isatom(D))
		var/atom/movable/AM = D
		if(ismovable(AM))
			// Phase 0.5: mind, pre-order, whole tree. A no-op until a body
			// plan declares a TRANSFER(mind) slot_def (DQ Medical, O2).
			tick = world.tick_usage
			dq_lifecycle_resolve_minds(AM)
			dq_lifecycle_time(trash, LIFECYCLE_PHASE_MIND, tick)
			DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_MIND done")

	// Phase 1: unbind, for every datum: Rust entity bindings, pipe/cable
	// topology, heat bodies (lifecycle_unbind() overrides). Must precede
	// dematerialize.
	tick = world.tick_usage
	D.lifecycle_unbind()
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_UNBIND, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_UNBIND done")

	// Phase 2: dematerialize. Index leaves that aren't registries yet
	// (lifecycle_dematerialize() overrides), for every datum.
	tick = world.tick_usage
	D.lifecycle_dematerialize()
	DQ_LIFECYCLE_TRACE(D, "lifecycle_dematerialize() returned")
	if(ismovable(D))
		dq_lifecycle_release_from_holder(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_DEMATERIALIZE, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_DEMATERIALIZE done")

	if(isatom(D))
		var/atom/movable/AM = D
		if(ismovable(AM))
			// Phase 3: contents. Every slot's declared destroy policy,
			// post-order (children before parents -- see
			// code/datums/containment/lifecycle.dm's file header for why
			// that falls out of ordinary qdel() recursion with no extra work).
			tick = world.tick_usage
			AM.dq_lifecycle_resolve_contents()
			dq_lifecycle_spill_declared(AM)
			dq_lifecycle_time(trash, LIFECYCLE_PHASE_CONTENTS, tick)
			DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_CONTENTS done")

	// Phase 4: links. Owned children deleted, pair partners nulled,
	// back-list memberships removed (L2, code/datums/lifecycle/links.dm).
	tick = world.tick_usage
	D.lifecycle_prerelease() // teardown that still reads the declared vars (links.dm)
	D.on_destroy(force) // the type's destroy hook: back-vars, partners and handles still live
	if(D.om_rec)
		om_behaviours_on_destroy(D) // each attached behaviour's on_entity_destroy(E)
	if(ismovable(D))
		dq_lifecycle_leave_own_slot(D) // slot-exit hooks see live back-refs
	dq_lifecycle_clear_links(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_LINKS, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_LINKS done")

	// Phase 5: teardown. Processing (auto-stopped via
	// periodic_pipe, set by om_task_periodic()), screens,
	// clock callbacks (hook point, DQ Medical w6/k1) and grants (hook point).
	// Timers, reactor, components, signals and tgui are already handled by
	// /datum/Destroy() itself (phase 7) and are not duplicated here.
	tick = world.tick_usage
	dq_lifecycle_teardown(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_TEARDOWN, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_TEARDOWN done")

	// Phase 6: effects. Declared destroy_effects data (L3).
	tick = world.tick_usage
	var/datum/destroy_effects_data/effects = D.destroy_effects()
	var/turf/effects_turf
	// Under a batch (batch.dm) effects are merged per turf and neighbour updates run once at the end.
	if(effects && !dq_batch_effects(D, effects))
		effects_turf = effects.apply(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_EFFECTS, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_EFFECTS done")

	// Phase 7: the core Destroy() chain (the type's on_destroy() already ran
	// at the start of phase 4, while its declared links still read) (/datum,
	// /atom, /atom/movable, ... and the MC's controllers: the only Destroy()
	// overrides tools/ci/lifecycle_counts_lint.py allows). A type's declared
	// destroy_hint replaces the core's plain QDEL_HINT_QUEUE.
	tick = world.tick_usage
	var/hint = D.Destroy(force)
	if(D.destroy_hint && hint == QDEL_HINT_QUEUE)
		hint = D.destroy_hint
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_DESTROY, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_DESTROY done")

	if(isnull(D)) // Destroy() hard-deleted itself (rare; some override del()s src)
		return hint

	// Phase 6's second half: neighbours that smooth against D, now it's gone.
	if(effects_turf)
		tick = world.tick_usage
		effects.apply_after(D, effects_turf)
		dq_lifecycle_time(trash, LIFECYCLE_PHASE_EFFECTS, tick)
		DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_EFFECTS done")

	// Phase 8: scrub. Null outbound declared owned/pair vars to break
	// reference cycles, then hand D to GC. Nothing is parked in nullspace.
	tick = world.tick_usage
	dq_lifecycle_scrub(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_SCRUB, tick)
	DQ_LIFECYCLE_TRACE(D, "LIFECYCLE_PHASE_SCRUB done")

	// Postcondition (leak_check.dm): on in test builds, toggleable on servers.
	// Nothing D still holds may be a deleted object that holds D back.
	if(GLOB.dq_lifecycle_leak_check && hint != QDEL_HINT_LETMELIVE)
		dq_lifecycle_postcondition(D)

	DQ_LIFECYCLE_TRACE(D, "end")
	return hint

#undef DQ_LIFECYCLE_TRACE

/// Phase 4, after on_destroy() and before the links clear: the dying movable
/// leaves its holder's ledger slot now, so its on_unslotted() hooks (a body
/// part's detach, which reads `owner`) run while REF_BACK vars still name their
/// partners. It keeps its loc until Destroy() (phase 7) moves it out; that
/// move's note_exit() then finds no entry. The ledger never re-adopts it:
/// sync() skips things being deleted.
/proc/dq_lifecycle_leave_own_slot(atom/movable/AM)
	var/atom/holder = AM.loc
	var/datum/ledger/L = holder?.ledger
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
/datum/proc/lifecycle_keep(force)
	SHOULD_NOT_SLEEP(TRUE)
	return FALSE

/// The type's destroy hook, run at the start of phase 4, right after
/// lifecycle_prerelease() and before the links clear: contents are resolved
/// (phase 3), but REF_BACK/BACKLIST/PAIR vars, owned children and OM handles
/// (om_handle_is) are all still live, so teardown can reach its owner and
/// partners. The core Destroy() chain runs later, in phase 7. The place for domain consequences only:
/// anything a REF_* declaration, lifecycle_unbind(), lifecycle_dematerialize(),
/// lifecycle_prerelease() or destroy_effects() expresses goes there instead.
/// Always call ..(). Returns nothing: the GC hint is destroy_hint.
/// Behaviours get the same hook as /datum/om/behaviour/proc/on_entity_destroy(E).
/datum/proc/on_destroy(force)
	SHOULD_CALL_PARENT(TRUE)
	return

// ---- Phase 1: unbind (hook point) ----

/// Phase 1 (doc/rewrite/lifecycle.md §2): R10 entity bindings
/// (vg_entity_unbind), heat bodies and pipe/cable topology, through a
/// declared `bindings` table -- must precede dematerialize. Nothing in this
/// track declares one yet; this is the hook the Rust/heat/atmos tracks land
/// on, matching the ~20 atmos/heat Destroy() blocks and the heat release
/// currently hard-ordered in /atom/Destroy the doc calls out to replace.
/datum/proc/lifecycle_unbind()
	return

// ---- Phase 2: dematerialize (hook point) ----

/// Phase 2: leave registries and drop rule bindings, same as today (most of
/// this already happens through existing Destroy() bodies and signal
/// handlers; L3's registry declarations replace the remaining `GLOB.x += src`
/// sites over time). Hook point for now.
/datum/proc/lifecycle_dematerialize()
	return

// ---- Phase 5: teardown ----

/// Ends any periodic work (om_task_periodic(), code/datums/om/periodic.dm),
/// releases HUD/screen objects from any client they're shown to, and calls
/// the clock and grants teardown hook points.
/proc/dq_lifecycle_teardown(datum/D)
	if(D.periodic_pipe)
		om_task_periodic_stop(D)
	if(isatom(D))
		var/atom/AT = D
		AT.dq_lifecycle_release_screen()
		// A walk_towards()/walk() loop keeps an internal BYOND reference.
		if(ismovable(AT))
			walk(AT, 0)
	dq_lifecycle_clock_teardown(D)
	dq_lifecycle_revoke_grants(D)

/// Removes `src` from any client's `screen` list it is shown on. Default: a
/// plain atom shows on nobody's screen. /obj/screen overrides this to leave
/// whichever hud/mob it was added to.
/atom/proc/dq_lifecycle_release_screen()
	return

/// Clock teardown hook point (DQ Medical w6/k1): cancels callbacks owned by
/// and targeting `D`. A no-op until that track lands `clock_teardown()`.
/proc/dq_lifecycle_clock_teardown(datum/D)
	return

/// Grants auto-revoke hook point (P5, doc/rewrite/lifecycle.md §2 phase 5,
/// §6): a granted ability/language/verb/factor whose source is `D` should
/// revoke itself, following the pattern of a COMSIG_QDELETING handler owned
/// by the grant's holder rather than the source cleaning up after itself. A
/// no-op until that track lands.
/proc/dq_lifecycle_revoke_grants(datum/D)
	// Object model (code/datums/om/entity.dm): contributions and grants this
	// datum holds anywhere, its own store, behaviours (on_stop), deadlines, tasks.
	if(D.om_rec)
		om_teardown_rest(D)
	// OM handles to D stop resolving (object_model_core.md §4.11).
	if(D.om_hid)
		om_handle_release(D)

// ---- Phase 6: effects ----

/// Declared destroy_effects data (L3, doc/rewrite/lifecycle.md §5): message,
/// sound, debris type, neighbour update. Nothing declares any yet (L4
/// migrates real Destroy() effect bodies over); this reads the declaration
/// when one exists.
/datum/proc/destroy_effects()
	return null

/proc/dq_lifecycle_effects(datum/D)
	var/datum/destroy_effects_data/data = D.destroy_effects()
	return data?.apply(D)

// ---- Phase 8: scrub ----

/// Nulls every declared REF_OWNED/REF_OWNED_LIST/REF_PAIR var still pointing
/// somewhere (links.dm's phase-4 clear already emptied most of them; this
/// catches whatever phase 7's leftover Destroy() set again) to break
/// reference cycles, then does nothing else -- D is not parked anywhere,
/// it is simply handed to the GC from here.
/proc/dq_lifecycle_scrub(datum/D)
	dq_lifecycle_null_declared_refs(D)
