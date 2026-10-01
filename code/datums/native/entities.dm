/**
 * # The entity table of the native system (SSvg)
 *
 * The entity table of the Rust binding layer (doc/rewrite/rust_bindings.md): which atom or datum a
 * `vg_entity` handle belongs to. It does not drive anything: the one driver of the simulation is the
 * native system's frame (code/datums/native/system.dm, `vg_frame()`), and everything Rust reports
 * leaves in that frame's outbox.
 *
 * `bound` and `entities_by_index` (which atom a `vg_entity` belongs to) are maintained by
 * `on_materialize()`/`on_dematerialize()` (`code/game/atoms_movable.dm`), not by generated code:
 * they track "this atom currently has a live vg_entity", independent of which components it holds.
 * A component event is resolved to its bound atom by `entity_lookup()` and checked against
 * `atom.vg_entity` before its handler is called, so a component detached between the event firing
 * and its delivery is silently dropped rather than misdelivered.
 *
 * There is no production repair sweep. Declared inputs are pushed when they change (the generated
 * setters and hooks); a divergence is a bug, found by the drift audit (`reconcile_all()`), which the
 * test sandbox's teardown and the binding fuzz test run after every step, so a missed update fails
 * the test that introduced it.
 */
/// SSvg is the native system (the dissolved subsystem keeps its name: the entity table and the drift audit live on it).
GLOBAL_REAL(SSvg, /datum/system/native)

/datum/system/native/New()
	..()
	SSvg = src

/datum/system/native
	/// Every atom with a live vg_entity. Membership: register()/unregister(),
	/// called from on_materialize()/on_dematerialize().
	var/list/bound = list() // ALLOW(instance_list): singleton system, one instance
	/// vg_entity's index (see VG_ENTITY_INDEX_MASK) -> the bound atom, for
	/// event dispatch (§8). 1-indexed like every DM list: slot "[index+1]".
	var/list/entities_by_index = list() // ALLOW(instance_list): singleton system, one instance

/datum/system/native/stat_entry(msg)
	msg = "B:[length(bound)]"
	return ..()

/// `register`/`unregister`: called from on_materialize()/on_dematerialize()
/// (code/game/atoms_movable.dm), not generated code.
/datum/system/native/proc/register(atom/movable/mover)
	if(!(mover in bound))
		bound += mover // ALLOW(ownership): the entity table is the registry of bound entities, not a holder
	var/slot = ((mover.vg_entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(length(entities_by_index) < slot)
		entities_by_index.len = slot
	entities_by_index[slot] = mover // ALLOW(ownership): the entity table is the registry of bound entities, not a holder

/datum/system/native/proc/unregister(atom/movable/mover)
	var/index = bound.Find(mover)
	if(index)
		bound.Cut(index, index + 1)
	var/slot = ((mover.vg_entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(slot <= length(entities_by_index) && entities_by_index[slot] == mover)
		entities_by_index[slot] = null

/// unregister() for a whole doomed set (batched destroy): one pass over `bound`.
/datum/system/native/proc/unregister_many(list/movers)
	bound -= movers

/// Gives `D` (any datum) its own entity handle, bound in `entities_by_index`
/// like an atom's: `entity_lookup()` finds it. Returns the handle.
/datum/system/native/proc/bind_datum(datum/D)
	var/entity = vg_entity_spawn()
	track_entity(D, entity)
	return entity

/// Frees an entity `bind_datum()` gave out.
/datum/system/native/proc/unbind_datum(datum/D, entity)
	untrack_entity(D, entity)
	vg_entity_unbind(entity)

/// Records `D` as the datum behind `entity`, an entity some other bind made
/// (a cable's network node): `entity_lookup()` finds it.
/datum/system/native/proc/track_entity(datum/D, entity)
	if(!entity)
		return
	var/slot = ((entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(length(entities_by_index) < slot)
		entities_by_index.len = slot
	entities_by_index[slot] = D

/// Forgets `D` behind `entity` (the entity itself is the caller's to free).
/datum/system/native/proc/untrack_entity(datum/D, entity)
	if(!entity)
		return
	var/slot = ((entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(slot <= length(entities_by_index) && entities_by_index[slot] == D)
		entities_by_index[slot] = null

/// The atom `entity`'s index belongs to, or null. Event dispatch (§8) still
/// checks `atom.vg_entity == entity` itself: a recycled index briefly holds
/// a different, newer entity, and this alone would misdeliver.
/datum/system/native/proc/entity_lookup(entity)
	var/slot = ((entity - 1) & VG_ENTITY_INDEX_MASK) + 1
	if(slot > length(entities_by_index))
		return null
	return entities_by_index[slot]

#if defined(UNIT_TESTS) || defined(TESTING) || defined(SPACEMAN_DMM)
/**
 * The drift audit: every bound atom's declared inputs against what Rust stores, in one call. The
 * test sandbox teardown and the binding fuzz test run it after every step (a repaired divergence
 * is a runtime that fails the test that caused it). Returns every finding (empty: no divergence).
 * Test builds only: production never sweeps.
 */
/datum/system/native/proc/reconcile_all()
	. = list()
	for(var/atom/movable/mover as anything in bound.Copy())
		if(QDELETED(mover) || !mover.vg_entity)
			continue
		var/list/mismatches = mover.vg_reconcile()
		if(length(mismatches))
			. += "[mover.type] [REF(mover)]: [jointext(mismatches, "; ")]"

/// Global convenience: `vg_reconcile_all()` (called from the test sandbox teardown and the fuzz test).
/proc/vg_reconcile_all()
	return SSvg.reconcile_all()
#endif

/// Test/debug: `vg_entity` count Rust reports versus `length(bound)`, and
/// the raw Rust-side debug list (`vg_entity_debug_list()`). A mismatch here
/// means an atom bound or unbound without going through vg_bind()/
/// vg_entity_unbind() — a desync in the binding layer itself.
/datum/system/native/proc/entity_census()
	return list(
		"dm_bound" = length(bound),
		"rust_entities" = vg_entity_count(),
	)

/// `vg_describe(atom)` (§3): every attached component's fields, or
/// "(unbound)".
/proc/vg_describe(atom/movable/mover)
	if(!istype(mover) || !mover.vg_entity)
		return "(unbound)"
	return vg_entity_describe(mover.vg_entity)
