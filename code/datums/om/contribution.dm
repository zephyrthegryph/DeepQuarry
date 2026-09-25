// Object-model core: contributions, grants, clocks, relevance, suspension
// (doc/rewrite/object_model_core.md sections E and A.7-A.8).
//
// One store per entity for everything that is "a source makes something
// true or adds to a number on a target": statuses, stat modifiers, grants,
// clock multipliers and inhibitions, relevance, suspension holds. An effect
// type (one table row) says how contributions combine and stack and which
// channel reports a change.
//
// There is no public setter for the combined value: it only changes through
// om_apply()/om_hold()/om_release(), and a hold dies with its source, so an
// override cannot outlive whatever imposed it.

#define OM_C_EFFECT 0
#define OM_C_SOURCE 1
#define OM_C_VALUE 2
#define OM_C_EXPIRES 3
#define OM_C_KEY 4
#define OM_C_EPOCH 5
#define OM_C_STRIDE 6

/// Timed contribution: expires after `duration` (deciseconds) via the deadline wheel.
/proc/om_apply(datum/target, effect_id, datum/source, duration, value = TRUE, key)
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	var/datum/om/rec/rec = om_rec_of(target)
	if(!rec || !source)
		return FALSE
	var/t = rec.sched.now()
	om_contrib_set(rec, eff, source, value, t + max(duration, 1), key, duration)
	om_expiry_reschedule(rec)
	return TRUE

/// Held contribution: lasts until released or until `source` is deleted.
/// Inside a hook of a `holds` behaviour, it also lasts only while the hook
/// keeps making it (see om_reconcile_holds()).
/proc/om_hold(datum/target, effect_id, datum/source, value = TRUE, key)
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	var/datum/om/rec/rec = om_rec_of(target)
	if(!rec || !source || QDELETED(source))
		return FALSE
	om_contrib_set(rec, eff, source, value, 0, key, 0)
	var/datum/om/scheduler/sched = rec.sched
	var/datum/om/rec/ctx = sched.ctx_rec
	if(ctx)
		var/list/log = ctx.hold_log
		var/found = FALSE
		for(var/i in 1 to length(log) step 5)
			if(log[i] == sched.ctx_bid && log[i + 1] == target && log[i + 2] == eff.idx && log[i + 3] == source && log[i + 4] == key)
				found = TRUE
				break
		if(!found)
			LAZYADD(ctx.hold_log, list(sched.ctx_bid, target, eff.idx, source, key))
			LAZYOR(rec.hook_holders, ctx.owner)
	return TRUE

/// Timed contribution ending exactly at `expires_at` (the target's scheduler
/// time, deciseconds), whatever the effect's stacking rule: for callers that
/// already computed the new expiry (set or adjust a remaining duration). An
/// expiry at or before now releases it.
/proc/om_apply_until(datum/target, effect_id, datum/source, expires_at, value = TRUE, key)
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	var/datum/om/rec/rec = om_rec_of(target)
	if(!rec || !source)
		return FALSE
	var/t = rec.sched.now()
	if(expires_at <= t)
		om_release(target, effect_id, source, key)
		return FALSE
	om_contrib_set(rec, eff, source, value, expires_at, key, expires_at - t, TRUE)
	om_expiry_reschedule(rec)
	return TRUE

/// When `source`'s contribution to `effect_id` on `target` expires (scheduler
/// time, deciseconds): 0 for a hold, null when there is none.
/proc/om_expires_at(datum/target, effect_id, datum/source, key)
	var/datum/om/rec/rec = target?.om_rec
	if(!rec?.contribs)
		return null
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	var/i = om_contrib_find(rec, eff.idx, source, key)
	if(!i)
		return null
	return rec.contribs[i + OM_C_EXPIRES]

/// The time `E`'s scheduler runs on (world.time live, injected in tests). Use it
/// with om_apply_until()/om_expires_at() so tests on a test scheduler agree.
/proc/om_time_of(datum/E)
	var/datum/om/rec/rec = E?.om_rec
	return rec ? rec.sched.now() : om_scheduler().now()

/proc/om_release(datum/target, effect_id, datum/source, key)
	var/datum/om/rec/rec = target?.om_rec
	if(!rec?.contribs)
		return FALSE
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	var/i = om_contrib_find(rec, eff.idx, source, key)
	if(!i)
		return FALSE
	om_contrib_remove(rec, eff, i)
	return TRUE

/// TRUE when the combined value differs from the effect's default (for
/// COMBINE_ANY: when anything contributes).
/proc/om_has(datum/target, effect_id)
	var/v = om_value_of(target, effect_id)
	if(islist(v))
		return length(v) > 0
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	return v != eff.default_value

/// The combined value. COMBINE_SUM_PER_KEY returns a shared list (read only).
/proc/om_value_of(datum/target, effect_id)
	var/datum/om/effect/eff = om_registry().effect(effect_id)
	var/datum/om/rec/rec = target?.om_rec
	if(!rec)
		if(eff.expr)
			return om_effect_eval(null, eff.expr)
		return eff.default_value
	return om_effect_value(rec, eff)

// ---------------------------------------------------------------- store internals

/proc/om_contrib_find(datum/om/rec/rec, eidx, source, key)
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		if(C[i + OM_C_EFFECT] == eidx && C[i + OM_C_SOURCE] == source && C[i + OM_C_KEY] == key)
			return i
	return 0

/proc/om_contrib_set(datum/om/rec/rec, datum/om/effect/eff, datum/source, value, expires, key, duration, exact = FALSE)
	if(eff.expr)
		CRASH("om: [eff.id] is a composite effect; contribute to its parts")
	if(eff.combine == COMBINE_SUM_PER_KEY && (isnull(key) || isnum(key)))
		CRASH("om: [eff.id] needs a text or path key")
	var/datum/om/scheduler/sched = rec.sched
	if(eff.clock_idx)
		om_clock_settle(rec, eff.clock_idx)
	var/old = om_effect_value(rec, eff)
	var/i = om_contrib_find(rec, eff.idx, source, key)
	if(i)
		var/list/C = rec.contribs
		if(exact)
			C[i + OM_C_VALUE] = value
			C[i + OM_C_EXPIRES] = expires
		else if(expires)
			var/old_expires = C[i + OM_C_EXPIRES]
			switch(eff.stacking)
				if(STACKING_REPLACE)
					C[i + OM_C_VALUE] = value
					C[i + OM_C_EXPIRES] = old_expires ? expires : 0
				if(STACKING_EXTEND)
					C[i + OM_C_VALUE] = value
					if(old_expires)
						C[i + OM_C_EXPIRES] = max(old_expires, sched.now()) + duration
				if(STACKING_MAX)
					C[i + OM_C_VALUE] = max(C[i + OM_C_VALUE], value)
					if(old_expires)
						C[i + OM_C_EXPIRES] = max(old_expires, expires)
		else
			C[i + OM_C_VALUE] = value
			C[i + OM_C_EXPIRES] = 0
		C[i + OM_C_EPOCH] = sched.cur_epoch
	else
		LAZYADD(rec.contribs, list(eff.idx, source, value, expires, key, sched.cur_epoch))
		var/datum/om/rec/srec = om_rec_of(source)
		if(srec)
			LAZYOR(srec.held_on, rec.owner)
	om_cval_drop(rec, eff.idx)
	om_effect_changed(rec, eff, old)

/proc/om_contrib_remove(datum/om/rec/rec, datum/om/effect/eff, i)
	if(eff.clock_idx)
		om_clock_settle(rec, eff.clock_idx)
	var/old = om_effect_value(rec, eff)
	rec.contribs.Cut(i, i + OM_C_STRIDE)
	if(!length(rec.contribs))
		rec.contribs = null
	om_cval_drop(rec, eff.idx)
	om_effect_changed(rec, eff, old)

/proc/om_cval_drop(datum/om/rec/rec, eidx)
	var/list/V = rec.cval
	for(var/i in 1 to length(V) step 2)
		if(V[i] == eidx)
			V.Cut(i, i + 2)
			return

/proc/om_effect_value(datum/om/rec/rec, datum/om/effect/eff)
	if(eff.expr)
		return om_effect_eval(rec, eff.expr)
	var/list/V = rec.cval
	for(var/i in 1 to length(V) step 2)
		if(V[i] == eff.idx)
			return V[i + 1]
	var/value = eff.default_value
	var/list/C = rec.contribs
	var/any = FALSE
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		if(C[i + OM_C_EFFECT] != eff.idx)
			continue
		var/v = C[i + OM_C_VALUE]
		switch(eff.combine)
			if(COMBINE_ANY)
				if(v)
					value = TRUE
			if(COMBINE_SUM)
				value = (any ? value : 0) + v
			if(COMBINE_MAX)
				value = any ? max(value, v) : v
			if(COMBINE_MIN)
				value = any ? min(value, v) : v
			if(COMBINE_MULTIPLY)
				value = (any ? value : 1) * v
			if(COMBINE_SUM_PER_KEY)
				if(!any)
					value = list()
				var/list/per_key = value
				var/key = C[i + OM_C_KEY]
				per_key[key] = (per_key[key] || 0) + v
		any = TRUE
	if(eff.combine == COMBINE_MAX && any && !isnull(eff.default_value))
		value = max(value, eff.default_value)
	if(eff.combine == COMBINE_SUM_PER_KEY && !any)
		value = list()
	LAZYADD(rec.cval, list(eff.idx, value))
	return value

/// Evaluates a composite expression: text ids, ALL_OF/ANY_OF/NOT_OF/SUM_OF.
/proc/om_effect_eval(datum/om/rec/rec, expr)
	if(istext(expr))
		var/datum/om/effect/part = om_registry().effect(expr)
		var/v = rec ? om_effect_value(rec, part) : part.default_value
		return v
	var/list/L = expr
	switch(L[1])
		if("not")
			return !om_effect_eval(rec, L[2])
		if("all")
			for(var/i in 2 to length(L))
				if(!om_effect_eval(rec, L[i]))
					return FALSE
			return TRUE
		if("any")
			for(var/i in 2 to length(L))
				if(om_effect_eval(rec, L[i]))
					return TRUE
			return FALSE
		if("sum")
			. = 0
			for(var/i in 2 to length(L))
				. += om_effect_eval(rec, L[i])

/// After a contribution changed: framework kinds, subclass hook, composites, channel.
/proc/om_effect_changed(datum/om/rec/rec, datum/om/effect/eff, old)
	var/new_value = om_effect_value(rec, eff)
	if(!islist(new_value) && new_value == old)
		return
	var/datum/E = rec.owner
	switch(eff.kind)
		if(OM_EFFECT_CLOCK_MULT, OM_EFFECT_CLOCK_INHIBIT)
			om_clock_changed(rec, eff.clock_idx)
		if(OM_EFFECT_RELEVANCE)
			rec.relevance = new_value
			om_sync_all(rec)
			om_native_relevance(E, new_value)
		if(OM_EFFECT_SUSPEND)
			om_sync_all(rec)
	eff.on_changed(E, old, new_value)
	var/bits = eff.channel | CHANGE_EFFECTS
	if(eff.dependents)
		var/list/effects = om_registry().effects
		for(var/dep_idx in eff.dependents)
			var/datum/om/effect/dep = effects[dep_idx]
			bits |= dep.channel
	if(E)
		om_changed(E, bits)

// ---------------------------------------------------------------- expiry

/// The next expiry on `rec`, as one deadline of the internal expiry behaviour.
/proc/om_expiry_reschedule(datum/om/rec/rec)
	var/soonest = 0
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		var/exp = C[i + OM_C_EXPIRES]
		if(exp && (!soonest || exp < soonest))
			soonest = exp
	var/datum/om/registry/reg = om_registry()
	if(soonest)
		om_after(rec.owner, max(soonest - rec.sched.now(), 0), reg.expiry_behaviour)
	else
		om_cancel_after(rec.owner, reg.expiry_behaviour)

/datum/om/behaviour/internal
	abstract_type = /datum/om/behaviour/internal

/datum/om/behaviour/internal/expiry
	name = "om: contribution expiry"
	lane = LANE_URGENT

/datum/om/behaviour/internal/expiry/on_deadline(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	var/t = rec.sched.now()
	var/list/effects = om_registry().effects
	var/i = 1
	while(i <= length(rec.contribs))
		var/exp = rec.contribs[i + OM_C_EXPIRES]
		if(exp && exp <= t)
			om_contrib_remove(rec, effects[rec.contribs[i + OM_C_EFFECT]], i)
			continue
		i += OM_C_STRIDE
	om_expiry_reschedule(rec)

// ---------------------------------------------------------------- source lifetime and hooks

/// Releases every contribution `source` holds anywhere (source deleted, edge unlinked).
/proc/om_release_all_from(datum/source)
	var/datum/om/rec/srec = source.om_rec
	if(!srec?.held_on)
		return
	var/list/targets = srec.held_on
	srec.held_on = null
	var/list/effects = om_registry().effects
	for(var/datum/target as anything in targets)
		var/datum/om/rec/rec = target.om_rec
		if(!rec)
			continue
		var/i = 1
		while(i <= length(rec.contribs))
			if(rec.contribs[i + OM_C_SOURCE] == source)
				om_contrib_remove(rec, effects[rec.contribs[i + OM_C_EFFECT]], i)
				continue
			i += OM_C_STRIDE
		om_expiry_reschedule(rec)

/// Target teardown: forget the contributions on `E` and every back-reference to it.
/proc/om_clear_target(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		var/datum/source = C[i + OM_C_SOURCE]
		var/datum/om/rec/srec = source?.om_rec
		if(srec)
			LAZYREMOVE(srec.held_on, E)
	for(var/datum/holder as anything in rec.hook_holders)
		var/datum/om/rec/hrec = holder.om_rec
		if(!hrec?.hold_log)
			continue
		var/j = 1
		while(j <= length(hrec.hold_log))
			if(hrec.hold_log[j + 1] == E)
				hrec.hold_log.Cut(j, j + 5)
				continue
			j += 5
	rec.hook_holders = null
	rec.contribs = null
	rec.cval = null

/// After a `holds` hook returns: every hold the hook made before but not this
/// time is released.
/proc/om_reconcile_holds(datum/om/rec/rec, bid, epoch)
	var/list/log = rec.hold_log
	if(!log)
		return
	var/list/effects = om_registry().effects
	var/j = 1
	while(j <= length(log))
		if(log[j] != bid)
			j += 5
			continue
		var/datum/target = log[j + 1]
		var/datum/om/rec/trec = target?.om_rec
		var/i = trec ? om_contrib_find(trec, log[j + 2], log[j + 3], log[j + 4]) : 0
		if(i && trec.contribs[i + OM_C_EPOCH] == epoch)
			j += 5
			continue
		log.Cut(j, j + 5)
		if(i)
			om_contrib_remove(trec, effects[trec.contribs[i + OM_C_EFFECT]], i)
	if(!length(log))
		rec.hold_log = null

/// Behaviour stopped: all of its hook holds go.
/proc/om_release_hook_holds(datum/om/rec/rec, bid)
	var/list/log = rec.hold_log
	if(!log)
		return
	var/list/effects = om_registry().effects
	var/j = 1
	while(j <= length(log))
		if(log[j] != bid)
			j += 5
			continue
		var/datum/target = log[j + 1]
		var/eidx = log[j + 2]
		var/source = log[j + 3]
		var/key = log[j + 4]
		log.Cut(j, j + 5)
		var/datum/om/rec/trec = target?.om_rec
		if(!trec)
			continue
		var/i = om_contrib_find(trec, eidx, source, key)
		if(i)
			om_contrib_remove(trec, effects[eidx], i)
	if(!length(log))
		rec.hold_log = null

// ---------------------------------------------------------------- grants

/// Grants are effects with COMBINE_SUM_PER_KEY: kind -> effect id, id -> key,
/// source -> contribution source. Ids are text or type paths.
/proc/om_grant(datum/target, kind, id, datum/source)
	return om_hold(target, kind, source, 1, id)

/proc/om_revoke(datum/target, kind, id, datum/source)
	return om_release(target, kind, source, id)

/proc/om_has_grant(datum/target, kind, id)
	var/list/per_key = om_value_of(target, kind)
	return islist(per_key) && per_key[id] > 0

/// Every grant `source` gives `target`: list of list(kind, id).
/proc/om_grants_from(datum/target, datum/source)
	. = list()
	var/datum/om/rec/rec = target?.om_rec
	if(!rec)
		return
	var/list/effects = om_registry().effects
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		if(C[i + OM_C_SOURCE] != source)
			continue
		var/datum/om/effect/eff = effects[C[i + OM_C_EFFECT]]
		if(eff.combine == COMBINE_SUM_PER_KEY)
			. += list(list(eff.id, C[i + OM_C_KEY]))

// ---------------------------------------------------------------- clocks

/// Stride 4 entry for clock `cidx`, created on first need.
/proc/om_clock_entry(datum/om/rec/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return i
	var/t = rec.sched.now()
	LAZYADD(rec.clocks, list(cidx, om_clock_compute(rec, cidx), t, t))
	return length(rec.clocks) - 3

/proc/om_clock_compute(datum/om/rec/rec, cidx)
	var/datum/om/clock_def/C = om_registry().clocks[cidx]
	var/mult = om_effect_value(rec, C.mult)
	var/inhibit = om_effect_value(rec, C.inhibit)
	return clamp(mult * (1 - clamp(inhibit, 0, 1)), C.min_rate, C.max_rate)

/// The entity's rate in clock `cidx` (1 when nothing modifies it).
/proc/om_clock_rate(datum/om/rec/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return K[i + 1]
	if(!rec.contribs)
		return 1
	return om_clock_compute(rec, cidx)

/// Local (clock) time in deciseconds.
/proc/om_clock_local(datum/om/rec/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return K[i + 2] + (rec.sched.now() - K[i + 3]) * K[i + 1]
	return rec.sched.now()

/// Folds elapsed time into local time at the current rate. Always before a rate change.
/proc/om_clock_settle(datum/om/rec/rec, cidx)
	var/i = om_clock_entry(rec, cidx)
	var/list/K = rec.clocks
	var/t = rec.sched.now()
	K[i + 2] += (t - K[i + 3]) * K[i + 1]
	K[i + 3] = t

/// After a clock effect changed: new rate, clocked deadlines re-inserted,
/// roster re-synced (a zero rate sleeps cadence work).
/proc/om_clock_changed(datum/om/rec/rec, cidx)
	var/i = om_clock_entry(rec, cidx)
	var/list/K = rec.clocks
	var/new_rate = om_clock_compute(rec, cidx)
	if(K[i + 1] == new_rate)
		return
	K[i + 1] = new_rate
	om_clock_reschedule(rec, cidx)
	om_sync_all(rec)

/// Public: rate of `E` in clock domain `clock_id`.
/proc/om_clock_rate_of(datum/E, clock_id)
	var/datum/om/clock_def/C = om_registry().clock_by_id[clock_id]
	if(!C)
		CRASH("om: unknown clock [clock_id]")
	var/datum/om/rec/rec = E.om_rec
	return rec ? om_clock_rate(rec, C.idx) : 1

// ---------------------------------------------------------------- relevance and suspension

/// `observer` makes `E` at least `level` relevant until released or deleted.
/proc/om_observe(datum/E, datum/observer, level)
	return om_hold(E, EFFECT_RELEVANCE, observer, level)

/proc/om_unobserve(datum/E, datum/observer)
	return om_release(E, EFFECT_RELEVANCE, observer)

/proc/om_relevance(datum/E)
	return E.om_rec ? E.om_rec.relevance : RELEVANCE_NONE

/// Suspends every cadence and wake of `E` while `source` holds it.
/proc/om_suspend(datum/E, datum/source)
	return om_hold(E, EFFECT_SUSPENDED, source, TRUE)

/proc/om_unsuspend(datum/E, datum/source)
	return om_release(E, EFFECT_SUSPENDED, source)

#undef OM_C_EFFECT
#undef OM_C_SOURCE
#undef OM_C_VALUE
#undef OM_C_EXPIRES
#undef OM_C_KEY
#undef OM_C_EPOCH
#undef OM_C_STRIDE
