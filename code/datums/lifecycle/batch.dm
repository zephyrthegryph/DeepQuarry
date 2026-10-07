// Batched destroy (doc/rewrite/init_and_turfs.md §4.4, doc/rewrite/lifecycle.md §2).
//
// destroy_transaction()'s phases, run across a doomed set instead of one
// object at a time:
//
//   1. Mark first. The whole set is collected and every member gets
//      gc_destroyed = GC_BATCH_DOOMED before any phase runs, so every
//      QDELETED() check in every handler already sees the final state, and
//      qdel() on a member is a silent no-op (the batch runs it).
//   2. Contents that would land somewhere doomed are deleted without moving.
//      A doomed holder's contents are doomed too when the holder's drop
//      location is itself doomed (a doomed atom, or a doomed turf -- a z-level
//      wipe or a shuttle's landing footprint). Phase 3 skips QDELETED things,
//      so they are never moved; they get their own transaction in the batch.
//      Contents whose drop location survives (a gibbed body's organs on the
//      floor, a blown-up locker's contents) still spill as usual. A mob with
//      a client is never doomed through its holder.
//   3. Edges between doomed atoms are dropped with no bookkeeping: links.dm
//      nulls only our own var when the far end of a pair, a back-list owner,
//      or a holder is doomed.
//   4. One Rust unbind call per kind: entity handles owned by doomed datums
//      are queued (dq_entity_unbind()) and freed with one
//      vg_entity_unbind_list(); heat bodies (dq_heat_body_release()), power
//      nodes (dq_power_unbind_node()) and pipe ports
//      (dq_pipe_port_remove()) likewise go in one call each, and the pipe
//      topology commits once for the batch.
//   5. One pass over the registries: a doomed member's registry leaves are
//      queued per registry and applied as one `members -= doomed` each.
//   6. Effects merged per turf: one object's declared destroy effects play
//      per turf, and each neighbour update runs once per turf and type.
//
// Entry points: qdel_batch(list, turfs) for a set already in hand, and a
// collecting scope -- dq_destroy_collect_begin()/_end() -- around code that
// qdel()s things one by one (explosion blast delivery, gib(), shuttle crush):
// inside it, qdel() of a movable marks it doomed and defers it, and _end()
// runs everything collected as one batch.

/// The batch whose transactions are running, or null.
GLOBAL_DATUM(dq_destroy_batch, /datum/destroy_batch)
/// Collecting scopes open (dq_destroy_collect_begin()); qdel() defers movables while > 0.
GLOBAL_VAR_INIT(dq_destroy_collect_depth, 0)
/// What the open collecting scopes deferred: datum -> force.
GLOBAL_LIST_EMPTY(dq_destroy_collected)
/// world.time the outermost collecting scope opened. A scope never spans a
/// sleep; one still open on a later tick was left by a runtime and is closed.
GLOBAL_VAR_INIT(dq_destroy_collect_time, 0)
/// Turfs where a destroy effect (sparks, debris, a destruction message or
/// sound) already played in the open collecting scope or running batch:
/// turf -> TRUE. Cleared when the outermost scope/batch ends.
GLOBAL_LIST_EMPTY(dq_destroy_effect_turfs)

/datum/destroy_batch
	/// Doomed datum -> TRUE, in marking (pre-)order.
	var/list/doomed = list() // ALLOW(instance_list): one per batched destroy, always filled
	/// Turfs whose contents are doomed: anything that would land there is part of the set.
	var/list/doomed_places = list() // ALLOW(instance_list): one per batched destroy, always filled
	/// Doomed datum -> force.
	var/list/forced = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Entity handles freed by the one unbind call at the end.
	var/list/unbind_entities = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Heat body handles released by one vg_heat_body_release_list().
	var/list/release_heat_bodies = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Entity handles whose power node goes in one vg_power_unbind_node_list().
	var/list/unbind_power_nodes = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Flat `port, mixture handle` pairs removed by one vg_pipe_remove_list().
	var/list/remove_pipe_ports = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Pipe port handles whose /datum/pipe_port is freed after that removal.
	var/list/free_pipe_ports = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// A pipe topology commit was asked for while the batch ran: it runs once at the end.
	var/pipe_commit_pending = FALSE
	/// Movables leaving SSvg's bound list in one pass.
	var/list/unbind_movers = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// /datum/registry -> members leaving it in one pass.
	var/list/registry_leaves = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Turf -> TRUE once one object's destroy effects played there.
	var/list/effect_turfs = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Turf -> list of /datum/destroy_effects_data whose apply_after() runs once at the end.
	var/list/after_effects = list() // ALLOW(instance_list): one per batched destroy, filled in the teardown pass
	/// Diagnostics.
	var/effects_merged = 0
	var/edges_dropped = 0

/// TRUE if `D` is in the running batch's doomed set (or a doomed turf).
/proc/dq_batch_doomed(datum/D)
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	return batch && D && (batch.doomed[D] || batch.doomed_places[D])

/// Destroys `roots` (datums; a movable's contents follow it when their drop
/// location is doomed) and everything on `doomed_turfs` (turfs themselves are
/// not deleted) as one batch. `roots[D]`, when set, is D's qdel force.
/// Returns how many datums the batch destroyed.
/proc/qdel_batch(list/roots, list/doomed_turfs, force = FALSE)
	var/datum/destroy_batch/batch = new
	for(var/turf/T as anything in doomed_turfs)
		batch.doomed_places[T] = TRUE
	// 1. Mark first.
	var/list/order = list()
	for(var/turf/T as anything in doomed_turfs)
		for(var/atom/movable/AM as anything in contents_of(T))
			dq_batch_mark(batch, AM, order, force, TRUE)
	for(var/datum/D as anything in roots)
		var/root_force = roots[D]
		dq_batch_mark(batch, D, order, force || root_force, FALSE)
	if(!length(order))
		return 0
	var/next = 1
	while(next <= length(order))
		var/datum/D = order[next++]
		if(ismovable(D))
			dq_batch_mark_contents(batch, D, order, force)
	var/datum/destroy_batch/outer = GLOB.dq_destroy_batch
	GLOB.dq_destroy_batch = batch
	// Children before parents: reverse marking order.
	for(var/i in length(order) to 1 step -1)
		var/datum/D = order[i]
		if(isnull(D) || D.gc_destroyed != GC_BATCH_DOOMED)
			continue // hard-deleted by an earlier member, or already destroyed
		dq_qdel_run(D, batch.forced[D])
	dq_batch_flush(batch)
	GLOB.dq_destroy_batch = outer
	if(!outer && !GLOB.dq_destroy_collect_depth)
		GLOB.dq_destroy_effect_turfs.Cut()
	return length(order)

/// Adds `D` to the set. Returns FALSE when it can't be (already deleted,
/// already doomed, or a client's mob reached through its holder/turf).
/proc/dq_batch_mark(datum/destroy_batch/batch, datum/D, list/order, force, spare_clients)
	if(!D || !isnull(D.gc_destroyed) && D.gc_destroyed != GC_BATCH_DOOMED)
		return FALSE
	if(batch.doomed[D] || isturf(D))
		return FALSE
	if(spare_clients && ismob(D))
		var/mob/M = D
		if(M.client)
			return FALSE
	D.gc_destroyed = GC_BATCH_DOOMED
	batch.doomed[D] = TRUE
	if(force)
		batch.forced[D] = TRUE
	order += D
	return TRUE

/// A doomed holder's contents join the set when they would land somewhere
/// doomed. `order` grows as this runs; qdel_batch()'s loop reaches the new
/// members too, so nesting is followed to any depth.
/proc/dq_batch_mark_contents(datum/destroy_batch/batch, atom/movable/holder, list/order, force)
	if(!length(holder.contents))
		return
	var/atom/drop = holder.drop_location()
	if(drop && !batch.doomed[drop] && !batch.doomed_places[drop])
		return
	for(var/atom/movable/thing as anything in contents_of(holder))
		dq_batch_mark(batch, thing, order, force, TRUE)

/// End of batch: the one unbind call per kind, one pass per registry, merged effects.
/// Pipe ports and power nodes go before the entities behind them are freed.
/proc/dq_batch_flush(datum/destroy_batch/batch)
	if(length(batch.remove_pipe_ports))
		vg_pipe_remove_list(batch.remove_pipe_ports)
		for(var/port in batch.free_pipe_ports)
			rust_free_pipe_port(port)
	if(batch.pipe_commit_pending || length(batch.remove_pipe_ports))
		batch.pipe_commit_pending = FALSE
		if(SSair)
			SSair.rust_pipe_topology_dirty = TRUE
			// An explosion's bulk resolve commits once itself when it ends.
			if(!SSexplosions.is_bulk_resolving())
				// Directly: rust_commit_pending_pipenets() would defer to this batch again.
				SSair.rust_pipe_topology_dirty = FALSE
				SSair.rust_apply_pipe_commit()
	if(length(batch.unbind_power_nodes))
		vg_power_unbind_node_list(batch.unbind_power_nodes)
		power_topology_edited(/datum/destroy_batch)
	if(length(batch.release_heat_bodies))
		vg_heat_body_release_list(batch.release_heat_bodies)
	if(length(batch.unbind_movers))
		SSvg.unregister_many(batch.unbind_movers)
	if(length(batch.unbind_entities))
		vg_entity_unbind_list(batch.unbind_entities)
	for(var/datum/registry/registry as anything in batch.registry_leaves)
		registry.remove_many(batch.registry_leaves[registry])
	for(var/turf/T as anything in batch.after_effects)
		for(var/datum/destroy_effects_data/effects as anything in batch.after_effects[T])
			effects.apply_after(null, T)

/// Frees Rust entity `entity`, owned by `owner`: queued for the batch's one
/// unbind call when `owner` is doomed, freed now otherwise.
/proc/dq_entity_unbind(datum/owner, entity)
	if(!entity)
		return
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(batch?.doomed[owner])
		batch.unbind_entities += entity
		return
	vg_entity_unbind(entity)

/// Releases heat body `handle`, owned by `owner`: queued for the batch's one
/// release call when `owner` is doomed, released now otherwise.
/proc/dq_heat_body_release(datum/owner, handle)
	if(!handle)
		return
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(batch?.doomed[owner])
		batch.release_heat_bodies += handle
		return
	vg_heat_body_release(handle)

/// Drops the power node of entity `entity`, owned by `owner`: queued for the
/// batch's one call when `owner` is doomed, dropped now otherwise.
/proc/dq_power_unbind_node(datum/owner, entity)
	if(!entity)
		return
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(batch?.doomed[owner])
		batch.unbind_power_nodes += entity
		return
	vg_power_unbind_node(entity)
	power_topology_edited(owner)

/// Removes pipe port `port` of `owner` (its gas to `mixture_handle`, 0:
/// discarded) and frees the port datum. Returns TRUE when the batch queued
/// both for its one removal call (`owner` doomed); FALSE: the caller removes
/// and frees the port now.
/proc/dq_pipe_port_remove(datum/owner, port, mixture_handle = 0)
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(!port || !batch?.doomed[owner])
		return FALSE
	batch.remove_pipe_ports += port
	batch.remove_pipe_ports += mixture_handle
	batch.free_pipe_ports += port
	return TRUE

/// TRUE (and deferred to the end of the batch) while a batch runs: pipe
/// topology commits once per batch, after its one removal call.
/proc/dq_batch_defer_pipe_commit()
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(!batch)
		return FALSE
	batch.pipe_commit_pending = TRUE
	return TRUE

/// TRUE (and queued) when `member` is doomed: its leave from `registry`
/// happens in the batch's one pass over that registry.
/proc/dq_batch_defer_registry_leave(datum/registry/registry, datum/member)
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(!batch?.doomed[member])
		return FALSE
	var/list/leaving = batch.registry_leaves[registry]
	if(!leaving)
		leaving = batch.registry_leaves[registry] = list()
	leaving += member
	return TRUE

/// Phase 6 under a batch: plays `effects` for doomed `D` unless another
/// member already played effects on the same turf, and queues the neighbour
/// update once per turf. Returns TRUE when it handled D (the caller skips
/// the unbatched apply/apply_after).
/proc/dq_batch_effects(datum/D, datum/destroy_effects_data/effects)
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(!batch?.doomed[D] || !isatom(D))
		return FALSE
	var/turf/T = get_turf(D)
	if(!T)
		return TRUE
	if(batch.effect_turfs[T] || !dq_destroy_effects_once(T))
		batch.effects_merged++
	else
		batch.effect_turfs[T] = TRUE
		effects.apply(D)
	if(effects.neighbor_type)
		var/list/after = batch.after_effects[T]
		if(!after)
			after = batch.after_effects[T] = list()
		after |= effects
	return TRUE

/// Opens a collecting scope: until the matching dq_destroy_collect_end(),
/// qdel() of a movable marks it doomed and defers it into one batch.
/proc/dq_destroy_collect_begin()
	if(GLOB.dq_destroy_collect_depth && !dq_destroy_collect_live())
		return dq_destroy_collect_begin()
	if(!GLOB.dq_destroy_collect_depth)
		GLOB.dq_destroy_collect_time = EXPIRY_AT(null, CLOCK_WORLD, 0)
		GLOB.dq_destroy_effect_turfs.Cut()
		// Contract damage reports accumulate per atom and publish once when
		// the outermost scope ends (code/modules/contracts/damage_batch.dm),
		// for every collecting scope, not only explosion epochs.
		SScontracts?.begin_contract_batch()
	GLOB.dq_destroy_collect_depth++

/// TRUE while the open collecting scope is current. A scope left open by a
/// runtime (or a sleep) is closed here -- what it collected runs as its
/// batch -- so qdel() never defers forever.
/proc/dq_destroy_collect_live()
	if(GLOB.dq_destroy_collect_time == world.time)
		return TRUE
	stack_trace("destroy collecting scope left open since [GLOB.dq_destroy_collect_time]; closing it")
	GLOB.dq_destroy_collect_depth = 1
	dq_destroy_collect_end()
	return FALSE

/// Closes a collecting scope; the outermost one runs everything collected as
/// one batch. Returns how many datums that batch destroyed.
/proc/dq_destroy_collect_end()
	if(GLOB.dq_destroy_collect_depth <= 0) // unbalanced end: nothing is open (keeps the contract batch balanced)
		GLOB.dq_destroy_collect_depth = 0
		return 0
	if(--GLOB.dq_destroy_collect_depth > 0)
		return 0
	GLOB.dq_destroy_collect_depth = 0
	. = 0
	// A batch's own leftover Destroy() may qdel() more movables; they run
	// normally (the scope is closed), so this runs once.
	var/list/collected = GLOB.dq_destroy_collected
	if(length(collected))
		GLOB.dq_destroy_collected = list()
		for(var/datum/D as anything in collected)
			if(D?.gc_destroyed == GC_BATCH_DOOMED)
				D.gc_destroyed = null // re-marked by qdel_batch(), in its order
		. = qdel_batch(collected)
	GLOB.dq_destroy_effect_turfs.Cut()
	SScontracts?.end_contract_batch()

/// Per-turf destroy effects (init_and_turfs.md §4.4 step 5). Outside a
/// collecting scope or batch this is always TRUE. Inside one it is TRUE for
/// the first caller on `A`'s turf and FALSE after, so a blast plays at most
/// one spark/debris roll, destruction message and sound per turf instead of
/// one per object. Wrap cosmetic destruction effects in it; never gameplay.
/proc/dq_destroy_effects_once(atom/A)
	if(!GLOB.dq_destroy_collect_depth && !GLOB.dq_destroy_batch)
		return TRUE
	var/turf/T = get_turf(A)
	if(!T)
		return TRUE
	if(GLOB.dq_destroy_effect_turfs[T])
		return FALSE
	GLOB.dq_destroy_effect_turfs[T] = TRUE
	return TRUE
