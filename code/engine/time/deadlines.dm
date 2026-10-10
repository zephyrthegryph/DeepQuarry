// Object-model core: deadlines (doc/rewrite/object_model_core.md section A.5). Hold times are
// deadlines too (a rule's hold_for is a keyed after() of its binding); the Rust world keeps the watches (world_watches.dm).
//
// A deadline is three numbers in a wheel bucket and three in the entity's
// record: no datum per timer, no signal registration, no FFI call. One
// deadline per (entity, behaviour); setting it again replaces it (the old
// wheel entry goes stale by generation and is skipped when it comes round).

/// Calls B.on_deadline(E) after `delay` deciseconds (in B's clock, if it has one). `sub`
/// keys further deadlines of the same behaviour on the same entity: OM_DL_THROTTLE is the
/// scheduler's deferred wake, OM_DL_STAGE + n a pipeline stage's rewake (on_keyed_deadline()).
/proc/deadline_deadline(datum/E, delay, B, sub = 0)
	var/datum/scheduled_behaviour/def = definition_registry().behaviour(B)
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	if(!rec)
		return FALSE
	var/datum/time_scheduler/sched = rec.sched
	var/key = def.id + sub * OM_DL_SUB
	var/gen = ++sched.gen
	var/t = sched.now()
	var/local_target = null
	var/due = t + max(delay, 0)
	if(def.clock_idx)
		var/rate = clock_rate(rec, def.clock_idx)
		local_target = clock_local(rec, def.clock_idx) + max(delay, 0)
		due = rate > 0 ? t + max(delay, 0) / rate : null
	var/list/D = rec.deadlines
	var/k = 0
	for(var/i in 1 to length(D) step 3)
		if(D[i] == key)
			k = i
			break
	if(k)
		D[k + 1] = gen
		D[k + 2] = local_target
	else
		LAZYADD(rec.deadlines, list(key, gen, local_target))
	if(!isnull(due))
		sched.insert_deadline(rec, key, gen, due)
	return TRUE

/proc/deadline_cancel_after(datum/E, B, sub = 0)
	var/datum/scheduler_record/rec = E?.om_rec
	if(!rec?.deadlines)
		return FALSE
	var/key = definition_registry().behaviour(B).id + sub * OM_DL_SUB
	var/list/D = rec.deadlines
	for(var/i in 1 to length(D) step 3)
		if(D[i] == key)
			D.Cut(i, i + 3)
			if(!length(D))
				rec.deadlines = null
			return TRUE
	return FALSE

/// Cancels every deadline of `B` on `E`, whatever its sub-key.
/proc/deadline_cancel_all_after(datum/E, B)
	var/datum/scheduler_record/rec = E?.om_rec
	if(!rec?.deadlines)
		return
	var/bid = definition_registry().behaviour(B).id
	var/list/D = rec.deadlines
	var/i = 1
	while(i <= length(D))
		if(D[i] % OM_DL_SUB == bid)
			D.Cut(i, i + 3)
			continue
		i += 3
	if(!length(D))
		rec.deadlines = null

/proc/deadline_deadline_pending(datum/E, B, sub = 0)
	var/datum/scheduler_record/rec = E?.om_rec
	if(!rec?.deadlines)
		return FALSE
	var/key = definition_registry().behaviour(B).id + sub * OM_DL_SUB
	for(var/i in 1 to length(rec.deadlines) step 3)
		if(rec.deadlines[i] == key)
			return TRUE
	return FALSE

/// A clock's rate changed: clocked deadlines get a new generation and a new
/// real-time position (a rate increase must not wait for the old position).
/proc/deadline_clock_reschedule(datum/scheduler_record/rec, cidx)
	var/list/D = rec.deadlines
	if(!D)
		return
	var/datum/definition_registry/reg = definition_registry()
	var/datum/time_scheduler/sched = rec.sched
	var/t = sched.now()
	for(var/i in 1 to length(D) step 3)
		var/local_target = D[i + 2]
		if(isnull(local_target))
			continue
		var/datum/scheduled_behaviour/B = reg.behaviours[D[i] % OM_DL_SUB]
		if(B.clock_idx != cidx)
			continue
		var/gen = ++sched.gen
		D[i + 1] = gen
		var/rate = clock_rate(rec, cidx)
		if(rate > 0)
			var/remaining = max(local_target - clock_local(rec, cidx), 0)
			sched.insert_deadline(rec, D[i], gen, t + remaining / rate)
