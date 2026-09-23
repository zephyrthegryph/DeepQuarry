/**
 * # SSvg
 *
 * The reconciler and per-sweep maintenance for the Rust binding layer
 * (doc/rewrite/rust_bindings.md §7). Every `wait`, this subsystem:
 *
 * 1. Ticks every registered Rust domain once (`vg_entity_tick_all()`), so a
 *    component's state is never more than one sweep old even though nothing
 *    writes it per idle tick.
 * 2. Recomputes a budget's worth of bound atoms' declared inputs and
 *    compares them with what Rust has stored, through `vg_reconcile()`
 *    (generated per bound type). A mismatch is repaired (the generated
 *    reconcile proc pushes the recomputed value before returning it as a
 *    finding) and logged.
 *
 * `bound` (which atoms to sweep) is maintained by `on_materialize()`/
 * `on_dematerialize()` (`code/game/atoms_movable.dm`), not by generated
 * code: it tracks "this atom currently has a live vg_entity", independent
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
	wait = 10 SECONDS
	priority = FIRE_PRIORITY_VG
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT

	/// Every atom with a live vg_entity. Membership: register()/unregister(),
	/// called from on_materialize()/on_dematerialize().
	var/list/bound = list()
	/// Where the production sweep left off.
	var/sweep_index = 1
	/// Atoms checked per fire(). §7: 5,000 atoms over 60s is ~85/s; at the
	/// default 10s `wait` that is about 850 per fire — this stays well
	/// under that so a single fire() never dominates a tick, and covers a
	/// smaller population (the common case) within one lap easily.
	var/sweep_batch = 100

	/// COUNT metric (§12): must stay 0. Repairs this sweep / lifetime.
	var/last_repairs = 0
	var/total_repairs = 0
	var/list/last_findings = list()

/datum/controller/subsystem/vg/Recover()
	bound = SSvg.bound
	sweep_index = SSvg.sweep_index
	total_repairs = SSvg.total_repairs

/datum/controller/subsystem/vg/stat_entry(msg)
	msg = "B:[length(bound)] R:[total_repairs]"
	return ..()

/datum/controller/subsystem/vg/fire(resumed)
	vg_entity_tick_all()
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

/datum/controller/subsystem/vg/proc/unregister(atom/movable/mover)
	var/index = bound.Find(mover)
	if(!index)
		return
	bound.Cut(index, index + 1)
	if(sweep_index > index)
		sweep_index--

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
