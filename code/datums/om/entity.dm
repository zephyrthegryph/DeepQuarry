// Object-model core: per-entity record, roster membership, change dispatch
// (doc/rewrite/object_model_core.md sections A and B).
//
// Any datum can be an entity. It costs two vars on /datum, both at their
// default (free) until the entity joins: `om_rec` and `om_listen`.

/// The entity's record. Null until the entity first joins.
/datum/var/tmp/datum/om/rec/om_rec
/// Union of every channel something listens to on this entity. A setter's
/// om_changed() returns on `!(om_listen & bits)` without a proc call more.
/datum/var/tmp/om_listen = 0

/datum/om/rec
	var/datum/owner
	var/datum/om/scheduler/sched
	/// Cadence phase shared by all of this entity's rings.
	var/phase = 0
	var/relevance = RELEVANCE_NONE
	var/datum/om/type_table/table
	var/started = FALSE
	var/torn_down = FALSE
	/// Attached behaviours, sorted by id (= run order), with parallel lists.
	var/list/att = list()
	var/list/att_pend = list()
	var/list/att_ring = list()
	var/list/att_state = list()
	/// Bumped whenever att changes shape (attach, detach), so loops over att re-find their
	/// position only when a hook actually reshaped it.
	var/att_ver = 0
	/// Lane bits this rec is queued in.
	var/queued = 0
	/// Union of att_pend: channels with an on_wake already queued. A change whose bits are all
	/// pending, and that nothing else watches (slow_mask), has nothing new to do.
	var/pend_union = 0
	/// Channels that need the full dispatch every time: requires re-checks, watches, forwards,
	/// derived inputs, services and tasks. Recomputed with the listen mask.
	var/slow_mask = 0
	/// Stride 3: behaviour id, generation, local target (clocked) or null.
	var/list/deadlines
	var/list/edges
	/// Stride 3: owner entity, mask, behaviour id.
	var/list/watches_in
	var/list/watching
	/// Stride 4: origin entity, mask, behaviour id (negative: derived idx), structural (1 when an intermediate hop).
	var/list/fwd_in
	var/list/fwd_out
	/// Stride 6: effect idx, source, value, expires (0 = held), key, epoch.
	var/list/contribs
	/// Stride 2: effect idx, cached value.
	var/list/cval
	/// Targets we hold contributions on.
	var/list/held_on
	/// Stride 5: behaviour id, target, effect idx, source, key (holds made in hooks).
	var/list/hold_log
	/// Entities whose hold_log names this entity as a target.
	var/list/hook_holders
	/// UI sessions: time (ds) of the last push (ui.dm).
	var/ui_last_push = 0
	/// Stride 5: derived idx, value, dirty, computed at, aggregate aux.
	var/list/dv
	/// Stride 4: clock idx, rate, local time (ds), settled at (ds).
	var/list/clocks
	var/list/rates
	var/list/tasks
	/// Step accumulators (seconds), indexed by the behaviour's step_idx. Grown on first use.
	var/list/steps
	/// Pipeline state (/datum/om/frame), indexed by the pipeline's pipe_idx. Grown on first use.
	var/list/pipes
	/// Stride 2: behaviour id, time of its last on_wake (min_interval behaviours only).
	var/list/throttle
	var/bulk_bits = 0
	var/service_pend = 0
	var/in_veto = FALSE
	var/native_bits = 0

/datum/om/rec/New(datum/owner, datum/om/scheduler/sched)
	src.owner = owner
	src.sched = sched
	phase = sched.next_phase()

/// The entity's record, created on first use in the current scheduler.
/proc/om_rec_of(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(rec)
		return rec
	if(QDELETED(E))
		return null
	rec = new /datum/om/rec(E, om_scheduler())
	E.om_rec = rec
	rec.table = om_registry().type_table(E.type)
	if(rec.table.service_mask)
		E.om_listen |= rec.table.service_mask
	return rec

// ---------------------------------------------------------------- start / attach

/// Joins `E` to the object model: attaches every behaviour its decls name and
/// applies its self effects and grants. Atoms call this from Initialize()
/// when their type has a decl; plain datums call it themselves.
/proc/om_start(datum/E)
	var/datum/om/rec/rec = om_rec_of(E)
	if(!rec || rec.started)
		return rec
	rec.started = TRUE
	var/datum/om/type_table/T = rec.table
	for(var/datum/om/behaviour/B as anything in T.behaviours)
		om_attach(E, B)
	for(var/i in 1 to length(T.self_effects) step 2)
		om_hold(E, T.self_effects[i], E, om_read(E, T.self_effects[i + 1]))
	for(var/i in 1 to length(T.self_grants) step 2)
		om_grant(E, T.self_grants[i], T.self_grants[i + 1], E)
	return rec

/// Attaches behaviour `B` (type or def) to `E`. Idempotent.
/proc/om_attach(datum/E, B)
	var/datum/om/behaviour/def = om_registry().behaviour(B)
	var/datum/om/rec/rec = om_rec_of(E)
	if(!rec)
		return FALSE
	var/n = length(rec.att)
	var/pos = n + 1
	for(var/i in 1 to n)
		var/datum/om/behaviour/other = rec.att[i]
		if(other == def)
			return TRUE
		if(other.id > def.id)
			pos = i
			break
	rec.att_ver++
	rec.att.Insert(pos, def)
	rec.att_pend.Insert(pos, 0)
	rec.att_ring.Insert(pos, null)
	rec.att_state.Insert(pos, 0)
	om_recompute_listen(rec)
	if(def.compiled_related)
		om_rebuild_fwd(rec)
	if(def.wake_on_native)
		om_native_watch(rec)
	om_sync(rec, pos, TRUE)
	return TRUE

/proc/om_detach(datum/E, B)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return FALSE
	var/datum/om/behaviour/def = om_registry().behaviour(B)
	var/i = rec.att.Find(def)
	if(!i)
		return FALSE
	om_stop_behaviour(rec, i)
	om_cancel_after(E, def)
	rec.att_ver++
	rec.att.Cut(i, i + 1)
	rec.att_pend.Cut(i, i + 1)
	rec.att_ring.Cut(i, i + 1)
	rec.att_state.Cut(i, i + 1)
	om_recompute_listen(rec)
	if(def.compiled_related)
		om_rebuild_fwd(rec)
	if(def.wake_on_native)
		om_native_watch(rec)
	return TRUE

/proc/om_attached(datum/E, B)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return FALSE
	return !!rec.att.Find(om_registry().behaviour(B))

/// Parks `B` on `E`: off its cadence ring until om_unpark(). Wakes and deadlines still arrive.
/proc/om_park(datum/E, B)
	var/datum/om/rec/rec = E.om_rec
	var/i = rec?.att.Find(om_registry().behaviour(B))
	if(!i)
		return
	rec.att_state[i] |= OM_ATT_PARKED
	om_sync(rec, i, FALSE)

/proc/om_unpark(datum/E, B)
	var/datum/om/rec/rec = E.om_rec
	var/i = rec?.att.Find(om_registry().behaviour(B))
	if(!i)
		return
	rec.att_state[i] &= ~OM_ATT_PARKED
	om_sync(rec, i, FALSE)

/// Roster membership for attachment `i`: started (on_start/on_stop) and which
/// cadence ring it sits on. `recheck` re-evaluates `requires`.
/proc/om_sync(datum/om/rec/rec, i, recheck)
	var/datum/om/behaviour/B = rec.att[i]
	var/state = rec.att_state[i]
	if(recheck)
		if(om_requires_pass(rec.owner, B))
			state |= OM_ATT_REQ_OK
		else
			state &= ~OM_ATT_REQ_OK
		rec.att_state[i] = state
	var/eligible = !rec.torn_down && (state & OM_ATT_REQ_OK) && !om_suspended(rec)
	if(eligible && !(state & OM_ATT_STARTED))
		rec.att_state[i] = state | OM_ATT_STARTED
		var/ver = rec.att_ver
		rec.sched.call_hook(rec, B, OM_HOOK_START)
		// on_start may have detached or reordered.
		if(rec.att_ver != ver)
			i = rec.att.Find(B)
		if(!i)
			return
		state = rec.att_state[i]
	else if(!eligible && (state & OM_ATT_STARTED))
		om_stop_behaviour(rec, i)
		return
	var/datum/om/ring/desired = null
	if(eligible && !(state & OM_ATT_PARKED))
		var/interval = B.compiled_intervals[rec.relevance + 1]
		if(interval > 0 && (!B.clock_idx || om_clock_rate(rec, B.clock_idx) > 0))
			desired = rec.sched.ring_for(B, interval)
	var/datum/om/ring/current = rec.att_ring[i]
	if(desired == current)
		return
	if(current)
		current.remove(rec.owner, rec.phase)
	if(desired)
		desired.add(rec.owner, rec.phase)
	rec.att_ring[i] = desired

/// Leaves the roster: off its ring, holds released, on_stop called.
/proc/om_stop_behaviour(datum/om/rec/rec, i)
	var/datum/om/behaviour/B = rec.att[i]
	var/datum/om/ring/current = rec.att_ring[i]
	if(current)
		current.remove(rec.owner, rec.phase)
		rec.att_ring[i] = null
	// Conservative: bits another behaviour still pends take the full dispatch path next time.
	rec.pend_union &= ~rec.att_pend[i]
	rec.att_pend[i] = 0
	if(!(rec.att_state[i] & OM_ATT_STARTED))
		return
	rec.att_state[i] &= ~OM_ATT_STARTED
	om_release_hook_holds(rec, B.id)
	rec.sched.call_hook(rec, B, OM_HOOK_STOP)

/proc/om_requires_pass(datum/E, datum/om/behaviour/B)
	for(var/datum/om/check/C as anything in B.compiled_requires)
		if(!isnull(C.why_not(E, null)))
			return FALSE
	return TRUE

/proc/om_suspended(datum/om/rec/rec)
	if(!rec.contribs)
		return FALSE
	return om_value_of(rec.owner, EFFECT_SUSPENDED)

/// Re-syncs every attachment (relevance, suspension or clock rate changed).
/proc/om_sync_all(datum/om/rec/rec, recheck = FALSE)
	var/i = 1
	while(i <= length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		var/ver = rec.att_ver
		om_sync(rec, i, recheck)
		if(rec.att_ver == ver)
			i++
			continue
		// A hook detached or attached behaviours; continue from B's position.
		var/at = rec.att.Find(B)
		i = (at ? at : i - 1) + 1

// ---------------------------------------------------------------- listen mask

/// Recomputed only when attachments, watches, forwards or derived storage change.
/proc/om_recompute_listen(datum/om/rec/rec)
	var/slow = rec.table?.service_mask
	var/mask = slow
	for(var/datum/om/behaviour/B as anything in rec.att)
		mask |= B.interest
		slow |= B.requires_mask | B.related_added_mask
	for(var/i in 1 to length(rec.watches_in) step 3)
		slow |= rec.watches_in[i + 1]
	for(var/i in 1 to length(rec.fwd_in) step 4)
		slow |= rec.fwd_in[i + 1]
	if(rec.dv)
		var/list/defs = om_registry().derived
		for(var/i in 1 to length(rec.dv) step 5)
			var/datum/om/derived/D = defs[rec.dv[i]]
			slow |= D.inputs
	for(var/datum/om/task/T as anything in rec.tasks)
		slow |= T.def.interrupt_on
	rec.slow_mask = slow
	rec.owner.om_listen = mask | slow

/// The mask other entities and behaviours observe (decides eager derived values).
/proc/om_observed_mask(datum/om/rec/rec)
	. = 0
	for(var/datum/om/behaviour/B as anything in rec.att)
		. |= B.wake_on
	for(var/i in 1 to length(rec.watches_in) step 3)
		. |= rec.watches_in[i + 1]
	for(var/i in 1 to length(rec.fwd_in) step 4)
		. |= rec.fwd_in[i + 1]

// ---------------------------------------------------------------- change dispatch

/// Setters call this after writing tracked state. Level-triggered: it says
/// "these channels may have changed"; observers re-read current state.
/proc/om_changed(datum/E, bits)
	if(E.om_listen & bits)
		om_dispatch_change(E, bits)

/proc/om_dispatch_change(datum/E, bits)
	var/datum/om/rec/rec = E.om_rec
	if(!rec || rec.torn_down)
		return
	var/datum/om/scheduler/sched = rec.sched
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	// Tests count raises (a status change must raise its channel once, not twice).
	if(sched.test_raises)
		sched.test_raises += list(list(E, bits))
#endif
	if(sched.bulk_depth)
		if(!rec.bulk_bits)
			sched.bulk_list += rec
		rec.bulk_bits |= bits
		return
	// Repeats of a change whose wake is already queued (a body raising health changes several
	// times in one frame) cost one test.
	if(!(bits & rec.slow_mask) && !(bits & ~rec.pend_union))
		return
	var/i = 1
	while(i <= length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		if(B.interest & bits)
			if(B.requires_mask & bits)
				var/ver = rec.att_ver
				om_sync(rec, i, TRUE)
				if(rec.att_ver != ver)
					i = rec.att.Find(B)
					if(!i)
						i = 1
						continue
			if((B.wake_on & bits) && (rec.att_state[i] & OM_ATT_STARTED))
				rec.att_pend[i] |= B.wake_on & bits
				rec.pend_union |= B.wake_on & bits
				sched.enqueue(rec, B.lane)
		i++
	if(rec.watches_in)
		var/list/W = rec.watches_in
		for(var/j in 1 to length(W) step 3)
			if(W[j + 1] & bits)
				om_wake_id(W[j], W[j + 2], CHANGE_RELATED)
	if(rec.fwd_in)
		// fwd_in is copy-on-write (relation.dm): a forward added or removed by a wake
		// replaces the list, so this loop keeps walking the one it started with.
		var/list/F = rec.fwd_in
		for(var/j in 1 to length(F) step 4)
			if(!(F[j + 1] & bits))
				continue
			var/bid = F[j + 2]
			if(bid > 0)
				om_wake_id(F[j], bid, CHANGE_RELATED)
			else
				om_agg_member_changed(F[j], -bid, E)
	if(rec.dv)
		om_derived_inputs_changed(rec, bits)
	if(rec.table.service_mask & bits)
		if(!rec.service_pend)
			sched.service_queue += rec
		rec.service_pend |= bits & rec.table.service_mask

/// Queues on_wake for behaviour id `bid` on `E` with `bits`.
/proc/om_wake_id(datum/E, bid, bits)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/i in 1 to length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		if(B.id == bid)
			if(rec.att_state[i] & OM_ATT_STARTED)
				rec.att_pend[i] |= bits
				rec.pend_union |= bits
				rec.sched.enqueue(rec, B.lane)
			return

/// Wakes behaviour `B` on `E` next drain (on_wake gets CHANGE_EXPLICIT).
/proc/om_wake(datum/E, B)
	var/datum/om/behaviour/def = om_registry().behaviour(B)
	om_wake_id(E, def.id, CHANGE_EXPLICIT)

// ---------------------------------------------------------------- watches

/// Dynamic watch: `owner`'s behaviour `B` wakes (CHANGE_RELATED) when `target`
/// changes any of `mask`. Removed when either end is torn down.
/proc/om_watch(datum/owner, datum/target, mask, B)
	var/datum/om/behaviour/def = om_registry().behaviour(B)
	var/datum/om/rec/trec = om_rec_of(target)
	var/datum/om/rec/orec = om_rec_of(owner)
	if(!trec || !orec)
		return FALSE
	LAZYINITLIST(trec.watches_in)
	var/list/W = trec.watches_in
	for(var/i in 1 to length(W) step 3)
		if(W[i] == owner && W[i + 2] == def.id)
			W[i + 1] = mask
			om_recompute_listen(trec)
			return TRUE
	W += list(owner, mask, def.id)
	LAZYOR(orec.watching, target)
	om_recompute_listen(trec)
	return TRUE

/proc/om_unwatch(datum/owner, datum/target, B)
	var/datum/om/rec/trec = target?.om_rec
	if(!trec?.watches_in)
		return
	var/bid = B ? om_registry().behaviour(B).id : 0
	var/list/W = trec.watches_in
	var/i = 1
	var/remaining = FALSE
	while(i <= length(W))
		if(W[i] == owner && (!bid || W[i + 2] == bid))
			W.Cut(i, i + 3)
			continue
		if(W[i] == owner)
			remaining = TRUE
		i += 3
	if(!remaining)
		var/datum/om/rec/orec = owner.om_rec
		if(orec)
			LAZYREMOVE(orec.watching, target)
	om_recompute_listen(trec)

// ---------------------------------------------------------------- bulk

/// Region-scale operations: changes inside are coalesced per entity and
/// delivered once at the matching om_bulk_end(); events marked skip_in_bulk
/// are dropped.
/proc/om_bulk_begin()
	om_scheduler().bulk_depth++

/proc/om_bulk_end()
	var/datum/om/scheduler/sched = om_scheduler()
	if(sched.bulk_depth <= 0)
		CRASH("om_bulk_end() without om_bulk_begin()")
	sched.bulk_depth--
	if(sched.bulk_depth)
		return
	var/list/pending = sched.bulk_list
	sched.bulk_list = list()
	for(var/datum/om/rec/rec as anything in pending)
		var/bits = rec.bulk_bits
		rec.bulk_bits = 0
		if(!rec.torn_down)
			om_dispatch_change(rec.owner, bits)

// ---------------------------------------------------------------- teardown

/// Lifecycle phase 4 (links): edges, watches, forwards. Called from
/// dq_lifecycle_clear_links(); both ends are still non-null.
/proc/om_teardown_links(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	for(var/datum/om/edge/edge as anything in rec.edges?.Copy())
		om_unlink_edge(edge, E)
	for(var/datum/target as anything in rec.watching?.Copy())
		om_unwatch(E, target, null)
	rec.watching = null
	if(rec.watches_in)
		var/list/W = rec.watches_in
		for(var/i in 1 to length(W) step 3)
			var/datum/watcher = W[i]
			var/datum/om/rec/wrec = watcher.om_rec
			if(wrec)
				LAZYREMOVE(wrec.watching, E)
		rec.watches_in = null
	om_clear_fwd_out(rec)
	for(var/i in 1 to length(rec.fwd_in) step 4)
		var/datum/origin = rec.fwd_in[i]
		var/datum/om/rec/orec = origin.om_rec
		if(orec)
			LAZYREMOVE(orec.fwd_out, E)
	rec.fwd_in = null

/// Lifecycle phase 5 (teardown): contributions both ways, behaviours
/// (on_stop), deadlines, tasks. Called from dq_lifecycle_revoke_grants().
/proc/om_teardown_rest(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	om_teardown_links(E)
	for(var/datum/om/task/T as anything in rec.tasks?.Copy())
		om_task_cancel(T, "deleted")
	om_release_all_from(E)
	om_clear_target(E)
	for(var/i in length(rec.att) to 1 step -1)
		om_stop_behaviour(rec, i)
	rec.torn_down = TRUE
	rec.deadlines = null
	rec.dv = null
	rec.rates = null
	E.om_listen = 0
	// Break the rec <-> entity cycle; wheel and queue entries hold the rec
	// and skip it once torn down.
	E.om_rec = null
	rec.owner = null

// ---------------------------------------------------------------- containment and atom hooks

/// TRUE when some decl applies to `path` (atoms join on materialize).
/proc/om_type_has_decl(path)
	return om_registry().decl_typecache[path]

/// Ledger: `thing` entered one of `holder`'s slots.
/proc/om_slot_entered(atom/holder, atom/movable/thing, datum/slot_def/def)
	if(holder.om_listen & CHANGE_CONTENTS)
		om_dispatch_change(holder, CHANGE_CONTENTS)
	if(def?.om_relation)
		om_link(thing, holder, def.om_relation)

/// Ledger: `thing` left one of `holder`'s slots.
/proc/om_slot_left(atom/holder, atom/movable/thing, datum/slot_def/def)
	if(def?.om_relation && thing.om_rec)
		om_unlink(thing, holder, def.om_relation)
	if(holder.om_listen & CHANGE_CONTENTS)
		om_dispatch_change(holder, CHANGE_CONTENTS)
