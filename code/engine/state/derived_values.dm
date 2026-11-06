// engine core: derived values
// (doc/rewrite/archive/object_model_core.md section C).
//
// A derived value is stored on the entity's record, indexed by the derived
// type's small integer id (never by path or string at runtime). It is lazy:
// a change on an input channel only sets the dirty bit, and the next read
// recomputes it. It becomes eager by itself when something observes its
// output channel: then the dirty entry is queued, recomputed once in
// LANE_DERIVED (inputs first, by boot order), and the channel is raised only
// if the value changed.
//

#define DV_ID 0
#define DV_VALUE 1
#define DV_DIRTY 2
#define DV_AT 3
#define DV_STRIDE 4

/// Reads derived value `name` (a DERIVE row name or a /datum/derived_definition type) of `E`.
/proc/derived_derived(datum/E, name)
	var/datum/derived_definition/D = definition_registry().derived_def(name)
	var/datum/scheduler_record/rec = scheduler_record_of(E)
	if(!rec)
		return null
	var/k = derived_dv_find(rec, D.idx)
	if(!k)
		k = derived_dv_create(rec, D)
	else if(rec.dv[k + DV_DIRTY] || (D.max_age && rec.sched.now() - rec.dv[k + DV_AT] > D.max_age))
		derived_dv_full(rec, k, D)
	return rec.dv[k + DV_VALUE]

/proc/derived_dv_find(datum/scheduler_record/rec, didx)
	var/list/V = rec.dv
	for(var/i in 1 to length(V) step DV_STRIDE)
		if(V[i] == didx)
			return i
	return 0

/proc/derived_dv_create(datum/scheduler_record/rec, datum/derived_definition/D)
	LAZYADD(rec.dv, list(D.idx, null, 1, 0))
	var/k = length(rec.dv) - DV_STRIDE + 1
	derived_dv_full(rec, k, D)
	entity_recompute_listen(rec)
	return k

/// Full recompute (first read, dirty read, max_age).
/proc/derived_dv_full(datum/scheduler_record/rec, k, datum/derived_definition/D)
	rec.dv[k + DV_VALUE] = D.compute(rec.owner)
	rec.dv[k + DV_DIRTY] = 0
	rec.dv[k + DV_AT] = rec.sched.now()

/// Input channels changed: mark dependents dirty.
/proc/derived_derived_inputs_changed(datum/scheduler_record/rec, bits)
	var/list/defs = definition_registry().derived
	var/list/V = rec.dv
	for(var/k in 1 to length(V) step DV_STRIDE)
		var/datum/derived_definition/D = defs[V[k]]
		if((D.inputs & bits) && !V[k + DV_DIRTY])
			derived_dv_mark(rec, k, D)

/proc/derived_dv_mark(datum/scheduler_record/rec, k, datum/derived_definition/D)
	rec.dv[k + DV_DIRTY] = 1
	if(!D.channel)
		return
	if(entity_observed_mask(rec) & D.channel)
		rec.sched.derived_queue |= rec
	else
		// Lazy: nobody watches the output, but other derived values may read
		// it; raising the channel only marks them dirty in turn.
		state_changed(rec.owner, D.channel)

/// LANE_DERIVED: recompute queued eager values, inputs first.
/datum/time_scheduler/proc/run_derived_queue()
	if(!length(derived_queue))
		return TRUE
	var/list/Q = derived_queue
	derived_queue = list()
	var/list/defs = definition_registry().derived
	for(var/idx in 1 to length(Q))
		var/datum/scheduler_record/rec = Q[idx]
		if(rec.torn_down)
			continue
		var/guard = 0
		while(guard++ < 64)
			var/best = 0
			var/best_order = 0
			var/observed = entity_observed_mask(rec)
			for(var/k in 1 to length(rec.dv) step DV_STRIDE)
				if(!rec.dv[k + DV_DIRTY])
					continue
				var/datum/derived_definition/D = defs[rec.dv[k]]
				if(!(D.channel & observed))
					continue
				if(!best || D.order < best_order)
					best = k
					best_order = D.order
			if(!best)
				break
			var/datum/derived_definition/D = defs[rec.dv[best]]
			var/old = rec.dv[best + DV_VALUE]
			try
				derived_dv_full(rec, best, D)
			catch(var/exception/e)
				rec.dv[best + DV_DIRTY] = 0
				report_caught(e, "derived [D.name]: [e]")
				continue
			if(islist(old) || old != rec.dv[best + DV_VALUE])
				state_changed(rec.owner, D.channel)
		if(out_of_budget() && idx < length(Q))
			derived_queue = Q.Copy(idx + 1) | derived_queue
			return FALSE
	return TRUE

#undef DV_ID
#undef DV_VALUE
#undef DV_DIRTY
#undef DV_AT
#undef DV_STRIDE
