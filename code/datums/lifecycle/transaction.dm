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
/proc/destroy_transaction(datum/D, force, datum/qdel_item/trash)
	SHOULD_NOT_OVERRIDE(TRUE)
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
	SEND_SIGNAL(D, COMSIG_QDELETING, force)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_GUARD, tick)

	if(isatom(D))
		var/atom/movable/AM = D
		if(ismovable(AM))
			// Phase 0.5: mind, pre-order, whole tree. A no-op until a body
			// plan declares a TRANSFER(mind) slot_def (DQ Medical, O2).
			tick = world.tick_usage
			dq_lifecycle_resolve_minds(AM)
			dq_lifecycle_time(trash, LIFECYCLE_PHASE_MIND, tick)

			// Phase 1: unbind. Hook point -- R10 entity bindings, heat
			// bodies, pipe/cable topology are outside this track's scope.
			tick = world.tick_usage
			dq_lifecycle_unbind(AM)
			dq_lifecycle_time(trash, LIFECYCLE_PHASE_UNBIND, tick)

			// Phase 2: dematerialize. Hook point for registries (L3) not
			// already covered by the base Destroy() (phase 7) or links
			// (phase 4).
			tick = world.tick_usage
			dq_lifecycle_dematerialize(AM)
			dq_lifecycle_time(trash, LIFECYCLE_PHASE_DEMATERIALIZE, tick)

			// Phase 3: contents. Every slot's declared destroy policy,
			// post-order (children before parents -- see
			// code/datums/containment/lifecycle.dm's file header for why
			// that falls out of ordinary qdel() recursion with no extra work).
			tick = world.tick_usage
			AM.dq_lifecycle_resolve_contents()
			dq_lifecycle_time(trash, LIFECYCLE_PHASE_CONTENTS, tick)

	// Phase 4: links. Owned children deleted, pair partners nulled,
	// back-list memberships removed (L2, code/datums/lifecycle/links.dm).
	tick = world.tick_usage
	dq_lifecycle_clear_links(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_LINKS, tick)

	// Phase 5: teardown. Processing (auto-stopped via
	// lifecycle_processing_subsystem, recorded by START_PROCESSING), screens,
	// clock callbacks (hook point, DQ Medical w6/k1) and grants (hook point).
	// Timers, reactor, components, signals and tgui are already handled by
	// /datum/Destroy() itself (phase 7) and are not duplicated here.
	tick = world.tick_usage
	dq_lifecycle_teardown(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_TEARDOWN, tick)

	// Phase 6: effects. Declared destroy_effects data (L3).
	tick = world.tick_usage
	dq_lifecycle_effects(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_EFFECTS, tick)

	// Phase 7: leftover Destroy(). Only real domain consequences should
	// remain here once L4's mechanical sweeps land; today this is still
	// almost every type's Destroy().
	tick = world.tick_usage
	var/hint = D.Destroy(force)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_DESTROY, tick)

	if(isnull(D)) // Destroy() hard-deleted itself (rare; some override del()s src)
		return hint

	// Phase 8: scrub. Null outbound declared owned/pair vars to break
	// reference cycles, then hand D to GC. Nothing is parked in nullspace.
	tick = world.tick_usage
	dq_lifecycle_scrub(D)
	dq_lifecycle_time(trash, LIFECYCLE_PHASE_SCRUB, tick)

	return hint

/// Accumulates the milliseconds since `start_tick` onto phase `id`. Cheap:
/// one TICK_USAGE_TO_MS and one list write, mirroring how destroy_time
/// itself is already measured in qdel().
/proc/dq_lifecycle_time(datum/qdel_item/trash, id, start_tick)
	trash.phase_ms[id] += TICK_USAGE_TO_MS(start_tick)

// ---- Phase 1: unbind (hook point) ----

/// Phase 1 (doc/rewrite/lifecycle.md §2): R10 entity bindings
/// (vg_entity_unbind), heat bodies and pipe/cable topology, through a
/// declared `bindings` table -- must precede dematerialize. Nothing in this
/// track declares one yet; this is the hook the Rust/heat/atmos tracks land
/// on, matching the ~20 atmos/heat Destroy() blocks and the heat release
/// currently hard-ordered in /atom/Destroy the doc calls out to replace.
/datum/proc/lifecycle_unbind()
	return

/proc/dq_lifecycle_unbind(atom/movable/AM)
	AM.lifecycle_unbind()

// ---- Phase 2: dematerialize (hook point) ----

/// Phase 2: leave registries and drop rule bindings, same as today (most of
/// this already happens through existing Destroy() bodies and signal
/// handlers; L3's registry declarations replace the remaining `GLOB.x += src`
/// sites over time). Hook point for now.
/datum/proc/lifecycle_dematerialize()
	return

/proc/dq_lifecycle_dematerialize(atom/movable/AM)
	AM.lifecycle_dematerialize()

// ---- Phase 5: teardown ----

/// Stops whatever subsystem START_PROCESSING last recorded (see MC.dm),
/// releases HUD/screen objects from any client they're shown to, and calls
/// the clock and grants teardown hook points.
/proc/dq_lifecycle_teardown(datum/D)
	if(D.lifecycle_processing_subsystem)
		var/datum/controller/subsystem/SS = D.lifecycle_processing_subsystem
		D.datum_flags &= ~DF_ISPROCESSING
		D.lifecycle_processing_subsystem = null
		// processing/currentrun are declared per-subsystem-subtype, not on
		// the shared /datum/controller/subsystem base (every subsystem that
		// processes redeclares its own, the way START_PROCESSING's own
		// `Processor.processing` expects) -- vars[] reaches them generically
		// without needing SS's exact concrete type here.
		var/list/processing = SS.vars["processing"]
		processing?.Remove(D)
		var/list/currentrun = SS.vars["currentrun"]
		currentrun?.Remove(D)
	if(isatom(D))
		var/atom/AT = D
		AT.dq_lifecycle_release_screen()
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

// ---- Phase 6: effects ----

/// Declared destroy_effects data (L3, doc/rewrite/lifecycle.md §5): message,
/// sound, debris type, neighbour update. Nothing declares any yet (L4
/// migrates real Destroy() effect bodies over); this reads the declaration
/// when one exists.
/datum/proc/destroy_effects()
	return null

/proc/dq_lifecycle_effects(datum/D)
	var/datum/destroy_effects_data/data = D.destroy_effects()
	if(!data)
		return
	data.apply(D)

// ---- Phase 8: scrub ----

/// Nulls every declared REF_OWNED/REF_OWNED_LIST/REF_PAIR var still pointing
/// somewhere (links.dm's phase-4 clear already emptied most of them; this
/// catches whatever phase 7's leftover Destroy() set again) to break
/// reference cycles, then does nothing else -- D is not parked anywhere,
/// it is simply handed to the GC from here.
/proc/dq_lifecycle_scrub(datum/D)
	dq_lifecycle_null_declared_refs(D)
