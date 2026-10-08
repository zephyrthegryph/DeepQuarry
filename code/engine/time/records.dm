// Object-model core: per-entity record, roster membership, change dispatch
// (doc/rewrite/object_model_core.md sections A and B).
//
// Any datum can be an entity. It costs two vars on /datum, both at their
// default (free) until the entity joins: `om_rec` and `om_listen`.

/// The entity's record. Null until the entity first joins.
// The object-model core's own record for this entity; released by the core (entity.dm) on leave
/datum/var/tmp/datum/scheduler_record/om_rec
/// Union of every channel something listens to on this entity. A setter's
/// state_changed() returns on `!(om_listen & bits)` without a proc call more.
/datum/var/tmp/om_listen = 0

/datum/scheduler_record
	var/datum/owner
	var/datum/time_scheduler/sched
	/// Cadence phase shared by all of this entity's rings.
	var/phase = 0
	var/relevance = RELEVANCE_NONE
	var/datum/scheduler_type_table/table
	var/started = FALSE
	var/torn_down = FALSE
	/// Attached behaviours, sorted by id (= run order), with parallel lists.
	var/list/att
	var/list/att_pend
	var/list/att_ring
	var/list/att_state
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
	/// Cross-entity derived inputs (fields.dm, "rel.field"): stride 2, holder entity, mask. A raise of
	/// `mask` here raises CHANGE_RELATED on the holder (its derived field's channel includes it).
	var/list/relay_in
	/// The entities this one relays from (their relay_in lists name it), for relink and teardown.
	var/list/relay_out
	/// Stride 4: origin entity, mask, behaviour id (negative: derived idx), structural (1 when an intermediate hop).
	var/list/fwd_in
	var/list/fwd_out
	/// Verb store: VERB_NAMED key -> the renamed verb instance on this entity (grant_verbs.dm).
	var/list/named_verbs
	/// Stride 5: derived idx, value, dirty, computed at, aggregate aux.
	var/list/dv
	/// Stride 4: clock idx, rate, local time (ds), settled at (ds).
	var/list/clocks
	/// Step accumulators (seconds), indexed by the behaviour's step_idx. Grown on first use.
	var/list/steps
	/// Pipeline state (/datum/work_frame), indexed by the pipeline's pipe_idx. Grown on first use.
	var/list/pipes
	/// Stride 2: behaviour id, time of its last on_wake (min_interval behaviours only).
	var/list/throttle
	var/bulk_bits = 0
	var/service_pend = 0
	/// Stack of before_* event types being delivered on this entity (lazy).
	var/list/in_veto
	var/native_bits = 0

/datum/scheduler_record/New(datum/owner, datum/time_scheduler/sched)
	if(!att)
		att = list()
	if(!att_pend)
		att_pend = list()
	if(!att_ring)
		att_ring = list()
	if(!att_state)
		att_state = list()
	src.owner = owner
	src.sched = sched
	phase = sched.next_phase()

/// The entity's record, created on first use in the current scheduler.
/proc/scheduler_record_of(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(rec)
		return rec
	if(QDELETED(E))
		return null
	rec = new /datum/scheduler_record(E, time_scheduler())
	E.om_rec = rec
	rec.table = definition_registry().type_table(E.type)
	if(!rec.table.cache_scanned)
		entity_cache_scan(rec.table, E)
	if(!rec.table.appearance_scanned)
		rec.table.appearance_scanned = TRUE
		rec.table.appearance_mask = E.scheduler_presentation_mask()
	if(rec.table.service_mask | rec.table.cache_mask | rec.table.appearance_mask | rec.table.sys_periodic_mask | rec.table.relay_mask)
		E.om_listen |= rec.table.service_mask | rec.table.cache_mask | rec.table.appearance_mask | rec.table.sys_periodic_mask | rec.table.relay_mask
	if(rec.table.derived_relays)
		scheduler_field_derived_relink(E, rec)
	return rec

// ---------------------------------------------------------------- declared caches

/// Reads `E`'s declared_cache_vars() into its type table (every instance of a type
/// declares the same rules). A cache with no rule is an error.
/proc/entity_cache_scan(datum/scheduler_type_table/T, datum/E)
	T.cache_scanned = TRUE
	var/list/decl = E.declared_cache_vars()
	for(var/name in decl)
		var/list/rule = decl[name]
		if(!islist(rule) || length(rule) != 2 || !(name in E.vars))
			time_scheduler().error("[E.type]: declared cache [name] needs a CACHE_ON_* rule")
			continue
		switch(rule[1])
			if("change")
				T.cache_mask |= rule[2]
				LAZYADD(T.cache_change, list(rule[2], name))
			if("event")
				LAZYADD(T.cache_events, list(rule[2], name))
			if("relation")
				var/datum/relation_definition/R = definition_registry().relation(rule[2])
				LAZYADD(T.cache_relations, list(R.id, name))
			else
				time_scheduler().error("[E.type]: declared cache [name] has an unknown rule [rule[1]]")

/// Nulls every declared cache on `E` whose rule in `rules` (stride 2: key, var) matches.
/proc/entity_cache_clear(datum/E, list/rules, key, bits)
	for(var/i in 1 to length(rules) step 2)
		var/k = rules[i]
		if(bits ? (k & bits) : (ispath(key) ? ispath(key, k) : k == key))
			E.vars[rules[i + 1]] = null

// ---------------------------------------------------------------- start / attach

/// Joins `E` to the object model: attaches every behaviour its decls name and
/// applies its self effects and grants. Atoms call this from Initialize()
/// when their type has a decl; plain datums call it themselves.
/proc/entity_start(datum/E)
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	if(!rec || rec.started)
		return rec
	rec.started = TRUE
	var/datum/scheduler_type_table/T = rec.table
	for(var/datum/scheduled_behaviour/B as anything in T.behaviours)
		entity_attach(E, B)
	return rec

/// Attaches behaviour `B` (type or def) to `E`. Idempotent.
/proc/entity_attach(datum/E, B)
	var/datum/scheduled_behaviour/def = definition_registry().behaviour(B)
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	if(!rec)
		return FALSE
	var/n = length(rec.att)
	var/pos = n + 1
	for(var/i in 1 to n)
		var/datum/scheduled_behaviour/other = rec.att[i]
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
	entity_recompute_listen(rec)
	if(def.compiled_related)
		relation_rebuild_fwd(rec)
	if(def.wake_on_native)
		entity_native_watch(rec)
	entity_sync(rec, pos, TRUE)
	return TRUE

/proc/entity_detach(datum/E, B)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return FALSE
	var/datum/scheduled_behaviour/def = definition_registry().behaviour(B)
	var/i = rec.att.Find(def)
	if(!i)
		return FALSE
	entity_stop_behaviour(rec, i)
	deadline_cancel_after(E, def)
	rec.att_ver++
	rec.att.Cut(i, i + 1)
	rec.att_pend.Cut(i, i + 1)
	rec.att_ring.Cut(i, i + 1)
	rec.att_state.Cut(i, i + 1)
	entity_recompute_listen(rec)
	if(def.compiled_related)
		relation_rebuild_fwd(rec)
	if(def.wake_on_native)
		entity_native_watch(rec)
	return TRUE

/proc/entity_attached(datum/E, B)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return FALSE
	return !!rec.att.Find(definition_registry().behaviour(B))

/// Parks `B` on `E`: off its cadence ring until entity_unpark(). Wakes and deadlines still arrive.
/proc/entity_park(datum/E, B)
	var/datum/scheduler_record/rec = E.om_rec
	var/i = rec?.att.Find(definition_registry().behaviour(B))
	if(!i)
		return
	rec.att_state[i] |= OM_ATT_PARKED
	entity_sync(rec, i, FALSE)

/proc/entity_unpark(datum/E, B)
	var/datum/scheduler_record/rec = E.om_rec
	var/i = rec?.att.Find(definition_registry().behaviour(B))
	if(!i)
		return
	rec.att_state[i] &= ~OM_ATT_PARKED
	entity_sync(rec, i, FALSE)

/// Roster membership for attachment `i`: started (on_start/on_stop) and which
/// cadence ring it sits on. `recheck` re-evaluates `requires`.
/proc/entity_sync(datum/scheduler_record/rec, i, recheck)
	var/datum/scheduled_behaviour/B = rec.att[i]
	var/state = rec.att_state[i]
	if(recheck)
		if(entity_requires_pass(rec.owner, B))
			state |= OM_ATT_REQ_OK
		else
			state &= ~OM_ATT_REQ_OK
		rec.att_state[i] = state
	var/eligible = !rec.torn_down && (state & OM_ATT_REQ_OK) && !entity_suspended(rec)
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
		entity_stop_behaviour(rec, i)
		return
	var/datum/cadence_ring/desired = null
	if(eligible && !(state & OM_ATT_PARKED))
		var/interval = B.compiled_intervals[rec.relevance + 1]
		if(interval > 0 && (!B.clock_idx || clock_rate(rec, B.clock_idx) > 0))
			desired = rec.sched.ring_for(B, interval)
	var/datum/cadence_ring/current = rec.att_ring[i]
	if(desired == current)
		return
	if(current)
		current.remove(rec.owner, rec.phase)
	if(desired)
		desired.add(rec.owner, rec.phase)
	rec.att_ring[i] = desired

/// Leaves the roster: off its ring, holds released, on_stop called.
/proc/entity_stop_behaviour(datum/scheduler_record/rec, i)
	var/datum/scheduled_behaviour/B = rec.att[i]
	var/datum/cadence_ring/current = rec.att_ring[i]
	if(current)
		current.remove(rec.owner, rec.phase)
		rec.att_ring[i] = null
	// Conservative: bits another behaviour still pends take the full dispatch path next time.
	rec.pend_union &= ~rec.att_pend[i]
	rec.att_pend[i] = 0
	if(!(rec.att_state[i] & OM_ATT_STARTED))
		return
	rec.att_state[i] &= ~OM_ATT_STARTED
	rec.sched.call_hook(rec, B, OM_HOOK_STOP)

/proc/entity_requires_pass(datum/E, datum/scheduled_behaviour/B)
	for(var/datum/requirement_definition/C as anything in B.compiled_requires)
		if(!isnull(C.why_not(E, null)))
			return FALSE
	return TRUE

/proc/entity_suspended(datum/scheduler_record/rec)
	if(!rec.owner?.rx?.stats)
		return FALSE
	return stat_value(rec.owner, STAT_SUSPENDED)

/// Re-syncs every attachment (relevance, suspension or clock rate changed).
/proc/entity_sync_all(datum/scheduler_record/rec, recheck = FALSE)
	var/i = 1
	while(i <= length(rec.att))
		var/datum/scheduled_behaviour/B = rec.att[i]
		var/ver = rec.att_ver
		entity_sync(rec, i, recheck)
		if(rec.att_ver == ver)
			i++
			continue
		// A hook detached or attached behaviours; continue from B's position.
		var/at = rec.att.Find(B)
		i = (at ? at : i - 1) + 1

// ---------------------------------------------------------------- listen mask

/// Recomputed only when attachments, watches, forwards or derived storage change.
/proc/entity_recompute_listen(datum/scheduler_record/rec)
	var/slow = rec.table?.service_mask | rec.table?.sys_periodic_mask
	var/mask = slow
	for(var/datum/scheduled_behaviour/B as anything in rec.att)
		mask |= B.interest
		slow |= B.requires_mask | B.related_added_mask
	for(var/i in 1 to length(rec.watches_in) step 3)
		slow |= rec.watches_in[i + 1]
	for(var/i in 1 to length(rec.relay_in) step 2)
		slow |= rec.relay_in[i + 1]
	slow |= rec.table?.relay_mask
	for(var/i in 1 to length(rec.fwd_in) step 4)
		slow |= rec.fwd_in[i + 1]
	if(rec.dv)
		var/list/defs = definition_registry().derived
		for(var/i in 1 to length(rec.dv) step 5)
			var/datum/derived_definition/D = defs[rec.dv[i]]
			slow |= D.inputs
	rec.slow_mask = slow
	rec.owner.om_listen = mask | slow | rec.table?.cache_mask | rec.table?.appearance_mask | (rec.owner.seq_states ? seq_listen_mask(rec.owner) : 0)

/// The mask other entities and behaviours observe (decides eager derived values).
/proc/entity_observed_mask(datum/scheduler_record/rec)
	. = 0
	for(var/datum/scheduled_behaviour/B as anything in rec.att)
		. |= B.wake_on
	for(var/i in 1 to length(rec.watches_in) step 3)
		. |= rec.watches_in[i + 1]
	for(var/i in 1 to length(rec.fwd_in) step 4)
		. |= rec.fwd_in[i + 1]

// ---------------------------------------------------------------- change dispatch

/// The kernel's change dispatch, reached only through state_changed() (the public change API). Level-triggered:
/// it says "these channels may have changed"; observers re-read current state. Any raise on an atom
/// whose type derives something (a look, hidden verbs, capabilities, periodic work) queues its refresh
/// (dx_conventions.md section 1); `force_refresh` queues it for any entity.
/proc/entity_raise_change(datum/E, bits, force_refresh = FALSE)
	if(E.om_listen & bits)
		entity_dispatch_change(E, bits)
	if(force_refresh || (isatom(E) && !E.refresh_queued && (GLOB.type_derives_cache[E.type] || E.periodic_cadence || E.periodic_interval)))
		refresh_mark(E, DEP_ALL, bits)

/proc/entity_dispatch_change(datum/E, bits)
	// Sequence steps that read these channels wake (code/controllers/kernel/sequence.dm). state_changed(), entity_raise_change() and the
	// OM_CHANGED() setters reach here: E's listen mask carries its sequences' channels (seq_listen_mask()).
	if(E.seq_states)
		seq_channels(E, bits)
	var/datum/scheduler_record/rec = E.om_rec
	// A declared appearance reading these channels refreshes once this frame (code/datums/sys/appearance.dm).
	if(bits & (rec ? rec.table.appearance_mask : E.scheduler_presentation_mask()))
		E.scheduler_queue_presentation()
	if(!rec || rec.torn_down)
		return
	var/datum/time_scheduler/sched = rec.sched
	// A declared cache keyed on these channels is stale now (clearing is idempotent,
	// so it runs before the repeat and bulk short cuts below).
	if(rec.table.cache_mask & bits)
		entity_cache_clear(E, rec.table.cache_change, null, bits)
	// A declared periodic field changed: start or stop the declared work now (code/datums/sys/periodic.dm).
	if(rec.table.sys_periodic_mask & bits)
		E.scheduler_evaluate_periodic()
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
		var/datum/scheduled_behaviour/B = rec.att[i]
		if(B.interest & bits)
			if(B.requires_mask & bits)
				var/ver = rec.att_ver
				entity_sync(rec, i, TRUE)
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
	// A field a cross-entity derived input reads changed here: relay it to the holders.
	if(rec.relay_in)
		var/list/R = rec.relay_in
		for(var/j in 1 to length(R) step 2)
			if(R[j + 1] & bits)
				state_changed(R[j], CHANGE_RELATED)
	// A relation var a cross-entity derived input follows changed: resubscribe.
	if(rec.table.relay_mask & bits)
		scheduler_field_derived_relink(E, rec)
	if(rec.watches_in)
		var/list/W = rec.watches_in
		for(var/j in 1 to length(W) step 3)
			if(W[j + 1] & bits)
				entity_wake_id(W[j], W[j + 2], CHANGE_RELATED)
	if(rec.fwd_in)
		// fwd_in is copy-on-write (relation.dm): a forward added or removed by a wake
		// replaces the list, so this loop keeps walking the one it started with.
		var/list/F = rec.fwd_in
		for(var/j in 1 to length(F) step 4)
			if(!(F[j + 1] & bits))
				continue
			var/bid = F[j + 2]
			if(bid > 0)
				entity_wake_id(F[j], bid, CHANGE_RELATED)
			else
				derived_agg_member_changed(F[j], -bid, E)
	if(rec.dv)
		derived_derived_inputs_changed(rec, bits)
	if(rec.table.service_mask & bits)
		if(!rec.service_pend)
			sched.service_queue += rec
		rec.service_pend |= bits & rec.table.service_mask

/// Queues on_wake for behaviour id `bid` on `E` with `bits`.
/proc/entity_wake_id(datum/E, bid, bits)
	var/datum/scheduler_record/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/i in 1 to length(rec.att))
		var/datum/scheduled_behaviour/B = rec.att[i]
		if(B.id == bid)
			if(rec.att_state[i] & OM_ATT_STARTED)
				rec.att_pend[i] |= bits
				rec.pend_union |= bits
				rec.sched.enqueue(rec, B.lane)
			return

/// Wakes behaviour `B` on `E` next drain (on_wake gets CHANGE_EXPLICIT).
/proc/entity_wake(datum/E, B)
	var/datum/scheduled_behaviour/def = definition_registry().behaviour(B)
	entity_wake_id(E, def.id, CHANGE_EXPLICIT)

// ---------------------------------------------------------------- watches

/// Dynamic watch: `owner`'s behaviour `B` wakes (CHANGE_RELATED) when `target`
/// changes any of `mask`. Removed when either end is torn down.
/proc/entity_watch(datum/owner, datum/target, mask, B)
	var/datum/scheduled_behaviour/def = definition_registry().behaviour(B)
	var/datum/scheduler_record/trec = scheduler_record_of(target)
	var/datum/scheduler_record/orec = scheduler_record_of(owner)
	if(!trec || !orec)
		return FALSE
	LAZYINITLIST(trec.watches_in)
	var/list/W = trec.watches_in
	for(var/i in 1 to length(W) step 3)
		if(W[i] == owner && W[i + 2] == def.id)
			W[i + 1] = mask
			entity_recompute_listen(trec)
			return TRUE
	W += list(owner, mask, def.id)
	LAZYOR(orec.watching, target)
	entity_recompute_listen(trec)
	return TRUE

/proc/entity_unwatch(datum/owner, datum/target, B)
	var/datum/scheduler_record/trec = target?.om_rec
	if(!trec?.watches_in)
		return
	var/bid = B ? definition_registry().behaviour(B).id : 0
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
		var/datum/scheduler_record/orec = owner.om_rec
		if(orec)
			LAZYREMOVE(orec.watching, target)
	entity_recompute_listen(trec)

// ---------------------------------------------------------------- bulk

/// Region-scale operations: changes inside are coalesced per entity and
/// delivered once at the matching entity_bulk_end(); events marked skip_in_bulk
/// are dropped.
/proc/entity_bulk_begin()
	time_scheduler().bulk_depth++

/proc/entity_bulk_end()
	var/datum/time_scheduler/sched = time_scheduler()
	if(sched.bulk_depth <= 0)
		CRASH("entity_bulk_end() without entity_bulk_begin()")
	sched.bulk_depth--
	if(sched.bulk_depth)
		return
	var/list/pending = sched.bulk_list
	sched.bulk_list = list()
	for(var/datum/scheduler_record/rec as anything in pending)
		var/bits = rec.bulk_bits
		rec.bulk_bits = 0
		if(!rec.torn_down)
			entity_dispatch_change(rec.owner, bits)

// ---------------------------------------------------------------- teardown

/// Lifecycle phase 4 (links): edges, watches, forwards. Called from
/// dq_lifecycle_clear_links(); both ends are still non-null.
/proc/entity_teardown_links(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	for(var/datum/relation_edge/edge as anything in rec.edges?.Copy())
		relation_unlink_edge(edge, E)
	for(var/datum/target as anything in rec.watching?.Copy())
		entity_unwatch(E, target, null)
	rec.watching = null
	if(rec.watches_in)
		var/list/W = rec.watches_in
		for(var/i in 1 to length(W) step 3)
			var/datum/watcher = W[i]
			var/datum/scheduler_record/wrec = watcher.om_rec
			if(wrec)
				LAZYREMOVE(wrec.watching, E)
		rec.watches_in = null
	scheduler_field_relay_clear(E, rec)
	relation_clear_fwd_out(rec)
	for(var/i in 1 to length(rec.fwd_in) step 4)
		var/datum/origin = rec.fwd_in[i]
		var/datum/scheduler_record/orec = origin.om_rec
		if(orec)
			LAZYREMOVE(orec.fwd_out, E)
	rec.fwd_in = null

/// Lifecycle phase 4: every attached behaviour's on_entity_destroy(E), before the links clear.
/proc/entity_behaviours_on_destroy(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/datum/scheduled_behaviour/B as anything in rec.att.Copy())
		if(rec.torn_down)
			return
		rec.sched.call_hook(rec, B, OM_HOOK_DESTROY)

/// Lifecycle phase 5 (teardown): contributions both ways, behaviours
/// (on_stop), deadlines, tasks. Called from dq_lifecycle_om_teardown().
/proc/entity_teardown_rest(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	entity_teardown_links(E)
	for(var/i in length(rec.att) to 1 step -1)
		entity_stop_behaviour(rec, i)
	rec.torn_down = TRUE
	rec.deadlines = null
	timers_clear(rec)
	rec.dv = null
	E.om_listen = 0
	// Break the rec <-> entity cycle; wheel and queue entries hold the rec
	// and skip it once torn down.
	E.om_rec = null
	rec.owner = null

// ---------------------------------------------------------------- containment and atom hooks

/// TRUE when some decl applies to `path` (atoms join on materialize).
/proc/entity_type_has_decl(path)
	return definition_registry().decl_typecache[path]

/// Ledger: `thing` entered one of `holder`'s slots. A slot is itself a
/// relation (thing = source, holder = target): entering one links it, so it
/// gets the relation's declared view fields, `changes` channels and
/// contributes/grants for free, on top of the ledger's own bookkeeping.
/proc/entity_slot_entered(atom/holder, atom/movable/thing, datum/relation_definition/slot/def)
	if(holder.om_listen & CHANGE_CONTENTS)
		entity_dispatch_change(holder, CHANGE_CONTENTS)
	if(def)
		relation_link(thing, holder, def.type)

/// Ledger: `thing` left one of `holder`'s slots.
/proc/entity_slot_left(atom/holder, atom/movable/thing, datum/relation_definition/slot/def)
	if(def && thing.om_rec)
		relation_unlink(thing, holder, def.type)
	if(holder.om_listen & CHANGE_CONTENTS)
		entity_dispatch_change(holder, CHANGE_CONTENTS)
