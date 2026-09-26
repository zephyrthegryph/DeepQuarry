/**
 * # SSvg
 *
 * The reconciler and per-sweep maintenance for the Rust binding layer
 * (doc/rewrite/rust_bindings.md §7). Every `wait`, this subsystem:
 *
 * 1. Feeds the elapsed time to the Rust world's pacer (`vg_world_tick()`),
 *    which steps every law when a step is owed, and ticks the Rust hosts
 *    that are not on the world yet (`vg_entity_tick_all()`).
 * 2. Recomputes a budget's worth of bound atoms' declared inputs and
 *    compares them with what Rust has stored, through `vg_reconcile()`
 *    (generated per bound type). A mismatch is repaired (the generated
 *    reconcile proc pushes the recomputed value before returning it as a
 *    finding) and logged.
 *
 * 3. Drains and dispatches every typed event (§8), through the generated
 *    `vg_drain_events()`: one `vg_world_events()` FFI call returns them
 *    all; a component event is resolved to its bound atom by
 *    `entity_lookup()` and checked against `atom.vg_entity` before its
 *    handler is called, so a component detached between the event firing
 *    and this drain is silently dropped rather than misdelivered. Domain
 *    events call the generated `SSvg.on_<domain>_<event>()` handlers.
 *
 * `bound` (which atoms to sweep) and `entities_by_index` (which atom a
 * `vg_entity` belongs to) are maintained by `on_materialize()`/
 * `on_dematerialize()` (`code/game/atoms_movable.dm`), not by generated
 * code: they track "this atom currently has a live vg_entity", independent
 * of which components it holds.
 *
 * Production sweeps cover every bound atom within about 60 seconds
 * (`sweep_batch` sized against `wait` and the live count). Test and dev
 * builds instead reconcile everything in one call, `reconcile_all()`,
 * from the test sandbox's teardown and the binding fuzz test: there, a
 * divergence is a runtime that fails the test that caused it, not a log.
 */
SUBSYSTEM_DEF(vg)
	name = "Verdigris Bindings"
	wait = 0.5 SECONDS
	priority = FIRE_PRIORITY_VG
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT

	/// Every atom with a live vg_entity. Membership: register()/unregister(),
	/// called from on_materialize()/on_dematerialize().
	var/list/bound = list()
	/// vg_entity's index (see VG_ENTITY_INDEX_MASK) -> the bound atom, for
	/// event dispatch (§8). 1-indexed like every DM list: slot "[index+1]".
	var/list/entities_by_index = list()
	/// Where the production sweep left off.
	var/sweep_index = 1
	/// Atoms checked per fire(). Scaled against `wait` to keep the same
	/// atoms/s reconciliation rate as before `wait` dropped from 10
	/// seconds to 0.5 (rust_architecture.md step 6: gas needs `vg_world_tick()`
	/// paced for its own real-time cadence, and this is the one driver, so
	/// `wait` itself moved instead of adding a second tick caller) — 100
	/// atoms per 10s was ~10/s; 5 per 0.5s keeps that rate.
	var/sweep_batch = 5

	/// COUNT metric (§12): must stay 0. Repairs this sweep / lifetime.
	var/last_repairs = 0
	var/total_repairs = 0
	var/list/last_findings = list()

/datum/controller/subsystem/vg/Recover()
	bound = SSvg.bound
	entities_by_index = SSvg.entities_by_index
	sweep_index = SSvg.sweep_index
	total_repairs = SSvg.total_repairs

/datum/controller/subsystem/vg/stat_entry(msg)
	msg = "B:[length(bound)] R:[total_repairs]"
	return ..()

/datum/controller/subsystem/vg/fire(resumed)
	vg_world_tick(wait / (1 SECONDS))
	vg_entity_tick_all()
	vg_drain_events()
	if(!length(bound))
		return
	last_repairs = 0
	last_findings = list()
	var/checked = 0
	var/wrapped = FALSE
	while(checked < sweep_batch && length(bound))
		if(sweep_index > length(bound))
			if(wrapped)
				break
			sweep_index = 1
			wrapped = TRUE
		var/atom/movable/mover = bound[sweep_index]
		checked++
		if(QDELETED(mover) || !mover.vg_entity)
			bound.Cut(sweep_index, sweep_index + 1)
			continue
		sweep_index++
		reconcile_one(mover)

/// Reconciles one atom, folding its findings into this fire()'s counters.
/datum/controller/subsystem/vg/proc/reconcile_one(atom/movable/mover)
	var/list/mismatches = mover.vg_reconcile()
	if(!length(mismatches))
		return
	last_repairs += length(mismatches)
	total_repairs += length(mismatches)
	var/entry = "[mover.type] [REF(mover)]: [jointext(mismatches, "; ")]"
	last_findings += entry
#if defined(UNIT_TESTS) || defined(TESTING)
	for(var/m in mismatches)
		stack_trace("VG_RECONCILE repaired a divergence: [mover.type]: [m]")
#else
	for(var/m in mismatches)
		log_runtime("VG_RECONCILE [mover.type]: [m]")
#endif

/// `register`/`unregister`: called from on_materialize()/on_dematerialize()
/// (code/game/atoms_movable.dm), not generated code.
/datum/controller/subsystem/vg/proc/register(atom/movable/mover)
	if(!(mover in bound))
		bound += mover
	var/slot = ((mover.vg_entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(length(entities_by_index) < slot)
		entities_by_index.len = slot
	entities_by_index[slot] = mover

/datum/controller/subsystem/vg/proc/unregister(atom/movable/mover)
	var/index = bound.Find(mover)
	if(index)
		bound.Cut(index, index + 1)
		if(sweep_index > index)
			sweep_index--
	var/slot = ((mover.vg_entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(entities_by_index[slot] == mover)
		entities_by_index[slot] = null

/// The atom `entity`'s index belongs to, or null. Event dispatch (§8) still
/// checks `atom.vg_entity == entity` itself: a recycled index briefly holds
/// a different, newer entity, and this alone would misdeliver.
/datum/controller/subsystem/vg/proc/entity_lookup(entity)
	var/slot = ((entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(slot > length(entities_by_index))
		return null
	return entities_by_index[slot]

/**
 * Full reconciliation of every bound atom in one call (§7): the test
 * sandbox teardown and the binding fuzz test call this after every step, so
 * a missed update fails the test that introduced it instead of waiting for
 * the production sweep's budget. Returns every finding (empty: no
 * divergence); does not touch the production sweep's index or counters.
 */
/datum/controller/subsystem/vg/proc/reconcile_all()
	. = list()
	for(var/atom/movable/mover as anything in bound.Copy())
		if(QDELETED(mover) || !mover.vg_entity)
			continue
		var/list/mismatches = mover.vg_reconcile()
		if(length(mismatches))
			. += "[mover.type] [REF(mover)]: [jointext(mismatches, "; ")]"

/// Test/debug: `vg_entity` count Rust reports versus `length(bound)`, and
/// the raw Rust-side debug list (`vg_entity_debug_list()`). A mismatch here
/// means an atom bound or unbound without going through vg_bind()/
/// vg_entity_unbind() — a desync in the binding layer itself.
/datum/controller/subsystem/vg/proc/entity_census()
	return list(
		"dm_bound" = length(bound),
		"rust_entities" = vg_entity_count(),
	)

/// Global convenience: `vg_reconcile_all()` (called from the test sandbox
/// teardown and the fuzz test), forwarding to SSvg.
/proc/vg_reconcile_all()
	return SSvg.reconcile_all()

/// `vg_describe(atom)` (§3): every attached component's fields, or
/// "(unbound)".
/proc/vg_describe(atom/movable/mover)
	if(!istype(mover) || !mover.vg_entity)
		return "(unbound)"
	return vg_entity_describe(mover.vg_entity)
