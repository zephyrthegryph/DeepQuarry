// Object-model core: derived values and aggregates
// (doc/rewrite/object_model_core.md section C).
//
// A derived value is stored on the entity's record, indexed by the derived
// type's small integer id (never by path or string at runtime). It is lazy:
// a change on an input channel only sets the dirty bit, and the next read
// recomputes it. It becomes eager by itself when something observes its
// output channel: then the dirty entry is queued, recomputed once in
// LANE_DERIVED (inputs first, by boot order), and the channel is raised only
// if the value changed.
//
// Aggregates over relation members keep each member's contribution cached on
// its edge, so a member joining, leaving or changing is an O(1) delta. MIN
// and MAX rescan only when the extreme member leaves or gets worse.

#define DV_ID 0
#define DV_VALUE 1
#define DV_DIRTY 2
#define DV_AT 3
#define DV_AUX 4
#define DV_STRIDE 5

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
#ifdef OM_DERIVED_AUDIT
	else if(D.aggregate)
		var/incremental = rec.dv[k + DV_VALUE]
		derived_dv_full(rec, k, D)
		if(rec.dv[k + DV_VALUE] != incremental)
			rec.sched.error("derived audit: [D.name] on [E] was [incremental], recomputed [rec.dv[k + DV_VALUE]]")
#endif
	return rec.dv[k + DV_VALUE]

/proc/derived_dv_find(datum/scheduler_record/rec, didx)
	var/list/V = rec.dv
	for(var/i in 1 to length(V) step DV_STRIDE)
		if(V[i] == didx)
			return i
	return 0

/proc/derived_dv_create(datum/scheduler_record/rec, datum/derived_definition/D)
	LAZYADD(rec.dv, list(D.idx, null, 1, 0, 0))
	var/k = length(rec.dv) - DV_STRIDE + 1
	derived_dv_full(rec, k, D)
	entity_recompute_listen(rec)
	if(D.compiled_related || (D.over_rel_id && D.member_inputs))
		relation_rebuild_fwd(rec)
	return k

/// Full recompute (first read, dirty read, max_age, audit).
/proc/derived_dv_full(datum/scheduler_record/rec, k, datum/derived_definition/D)
	var/datum/E = rec.owner
	var/value = null
	var/aux = 0
	if(D.aggregate)
		var/list/contributions = list()
		var/list/members = list()
		for(var/datum/relation_edge/edge as anything in rec.edges)
			if(edge.rel.id == D.over_rel_id && edge.target == E)
				var/c = derived_agg_contribution(D, edge.source)
				derived_edge_cache_set(edge, D.idx, c)
				members += edge.source
				contributions += list(c)
		switch(D.aggregate)
			if(AGG_SUM)
				value = 0
				for(var/c in contributions)
					value += c || 0
			if(AGG_COUNT)
				value = length(contributions)
			if(AGG_ANY)
				for(var/c in contributions)
					if(c)
						aux++
				value = aux > 0
			if(AGG_ALL)
				for(var/c in contributions)
					if(!c)
						aux++
				value = aux == 0
			if(AGG_MIN)
				for(var/c in contributions)
					if(!isnull(c) && (isnull(value) || c < value))
						value = c
			if(AGG_MAX)
				for(var/c in contributions)
					if(!isnull(c) && (isnull(value) || c > value))
						value = c
			if(AGG_CUSTOM)
				for(var/i in 1 to length(members))
					value = D.on_member_added(E, members[i], value, contributions[i])
	else
		value = D.compute(E)
	rec.dv[k + DV_VALUE] = value
	rec.dv[k + DV_DIRTY] = 0
	rec.dv[k + DV_AT] = rec.sched.now()
	rec.dv[k + DV_AUX] = aux

/proc/derived_agg_contribution(datum/derived_definition/D, datum/member)
	if(D.aggregate == AGG_COUNT)
		return 1
	return D.contribution(member)

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

// ---------------------------------------------------------------- aggregate deltas

/proc/derived_edge_cache_get(datum/relation_edge/edge, didx)
	var/list/C = edge.cache
	for(var/i in 1 to length(C) step 2)
		if(C[i] == didx)
			return C[i + 1]
	return null

/proc/derived_edge_cache_set(datum/relation_edge/edge, didx, value)
	var/list/C = edge.cache
	for(var/i in 1 to length(C) step 2)
		if(C[i] == didx)
			C[i + 1] = value
			return
	LAZYADD(edge.cache, list(didx, value))

/proc/derived_agg_edge_added(datum/relation_edge/edge)
	var/datum/scheduler_record/rec = edge.target?.om_rec
	if(!rec?.dv)
		return
	var/list/defs = definition_registry().derived
	for(var/k in 1 to length(rec.dv) step DV_STRIDE)
		var/datum/derived_definition/D = defs[rec.dv[k]]
		if(D.over_rel_id != edge.rel.id || rec.dv[k + DV_DIRTY])
			continue
		var/c = derived_agg_contribution(D, edge.source)
		derived_edge_cache_set(edge, D.idx, c)
		derived_agg_delta(rec, k, D, edge.source, null, c, 1)

/proc/derived_agg_edge_removed(datum/relation_edge/edge, datum/scheduler_record/rec)
	if(!rec?.dv)
		return
	var/list/defs = definition_registry().derived
	for(var/k in 1 to length(rec.dv) step DV_STRIDE)
		var/datum/derived_definition/D = defs[rec.dv[k]]
		if(D.over_rel_id != edge.rel.id || rec.dv[k + DV_DIRTY])
			continue
		derived_agg_delta(rec, k, D, edge.source, derived_edge_cache_get(edge, D.idx), null, -1)

/// A forwarded change from `member` (aggregate member or related input) to `origin`'s derived `didx`.
/proc/derived_agg_member_changed(datum/origin, didx, datum/member)
	var/datum/scheduler_record/rec = origin?.om_rec
	if(!rec?.dv)
		return
	var/k = derived_dv_find(rec, didx)
	if(!k || rec.dv[k + DV_DIRTY])
		return
	var/datum/derived_definition/D = definition_registry().derived[didx]
	if(!D.aggregate || !D.over_rel_id)
		derived_dv_mark(rec, k, D)
		return
	for(var/datum/relation_edge/edge as anything in rec.edges)
		if(edge.rel.id == D.over_rel_id && edge.source == member && edge.target == origin)
			var/old = derived_edge_cache_get(edge, didx)
			var/c = derived_agg_contribution(D, member)
			if(c == old)
				return
			derived_edge_cache_set(edge, didx, c)
			derived_agg_delta(rec, k, D, member, old, c, 0)
			return

/// Applies one member delta. `sign`: 1 joined, -1 left, 0 changed.
/proc/derived_agg_delta(datum/scheduler_record/rec, k, datum/derived_definition/D, datum/member, old_c, new_c, sign)
	var/value = rec.dv[k + DV_VALUE]
	var/aux = rec.dv[k + DV_AUX]
	var/old_value = value
	var/rescan = FALSE
	switch(D.aggregate)
		if(AGG_SUM)
			value += (new_c || 0) - (old_c || 0)
		if(AGG_COUNT)
			value += sign
		if(AGG_ANY)
			aux += (sign >= 0 && new_c ? 1 : 0) - (sign <= 0 && old_c ? 1 : 0)
			value = aux > 0
		if(AGG_ALL)
			aux += (sign >= 0 && !new_c ? 1 : 0) - (sign <= 0 && !old_c ? 1 : 0)
			value = aux == 0
		if(AGG_MIN)
			if(sign >= 0 && !isnull(new_c) && (isnull(value) || new_c < value))
				value = new_c
			else if(sign <= 0 && !isnull(old_c) && old_c == value)
				rescan = TRUE
		if(AGG_MAX)
			if(sign >= 0 && !isnull(new_c) && (isnull(value) || new_c > value))
				value = new_c
			else if(sign <= 0 && !isnull(old_c) && old_c == value)
				rescan = TRUE
		if(AGG_CUSTOM)
			switch(sign)
				if(1)
					value = D.on_member_added(rec.owner, member, value, new_c)
				if(-1)
					value = D.on_member_removed(rec.owner, member, value, old_c)
				else
					value = D.on_member_changed(rec.owner, member, value, old_c, new_c)
	if(rescan)
		value = null
		for(var/datum/relation_edge/edge as anything in rec.edges)
			if(edge.rel.id != D.over_rel_id || edge.target != rec.owner)
				continue
			var/c = derived_edge_cache_get(edge, D.idx)
			if(isnull(c))
				continue
			if(isnull(value) || (D.aggregate == AGG_MIN ? c < value : c > value))
				value = c
	rec.dv[k + DV_VALUE] = value
	rec.dv[k + DV_AUX] = aux
	rec.dv[k + DV_AT] = rec.sched.now()
	if(D.channel && (islist(value) || value != old_value))
		state_changed(rec.owner, D.channel)

#undef DV_ID
#undef DV_VALUE
#undef DV_DIRTY
#undef DV_AT
#undef DV_AUX
#undef DV_STRIDE
