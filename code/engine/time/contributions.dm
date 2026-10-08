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
// contribution_apply()/contribution_hold()/contribution_release(), and a hold dies with its source, so an
// override cannot outlive whatever imposed it.

#define OM_C_EFFECT 0
#define OM_C_SOURCE 1
#define OM_C_VALUE 2
#define OM_C_EXPIRES 3
#define OM_C_KEY 4
#define OM_C_EPOCH 5
#define OM_C_STRIDE 6

/// Timed contribution: expires after `duration` (deciseconds) via the deadline wheel.
/proc/contribution_apply(datum/target, effect_id, datum/source, duration, value = TRUE, key)
	var/datum/effect_definition/eff = definition_registry().effect(effect_id)
	var/datum/scheduler_record/rec = scheduler_record_of(target)
	if(!rec || !source)
		return FALSE
	var/t = rec.sched.now()
	contribution_contrib_set(rec, eff, source, value, t + max(duration, 1), key, duration)
	contribution_expiry_reschedule(rec)
	return TRUE

/// Held contribution: lasts until released or until `source` is deleted.
/// Inside a hook of a `holds` behaviour, it also lasts only while the hook
/// keeps making it (see contribution_reconcile_holds()).
/proc/contribution_hold(datum/target, effect_id, datum/source, value = TRUE, key)
	var/datum/effect_definition/eff = definition_registry().effect(effect_id)
	var/datum/scheduler_record/rec = scheduler_record_of(target)
	if(!rec || !source || QDELETED(source))
		return FALSE
	contribution_contrib_set(rec, eff, source, value, 0, key, 0)
	var/datum/time_scheduler/sched = rec.sched
	var/datum/scheduler_record/ctx = sched.ctx_rec
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
/proc/contribution_apply_until(datum/target, effect_id, datum/source, expires_at, value = TRUE, key)
	var/datum/scheduler_record/rec = scheduler_record_of(target)
	if(!rec || !source)
		return FALSE
	return contribution_contrib_until(rec, definition_registry().effect(effect_id), source, expires_at, value, key)

/// contribution_apply_until() for callers holding the effect def (one id lookup per call).
/proc/contribution_contrib_until(datum/scheduler_record/rec, datum/effect_definition/eff, datum/source, expires_at, value = TRUE, key)
	var/t = rec.sched.now()
	if(expires_at <= t)
		var/i = rec.contribs ? contribution_contrib_find(rec, eff.idx, source, key) : 0
		if(i)
			contribution_contrib_remove(rec, eff, i)
			contribution_expiry_reschedule(rec)
		return FALSE
	contribution_contrib_set(rec, eff, source, value, expires_at, key, expires_at - t, TRUE)
	contribution_expiry_reschedule(rec)
	return TRUE

/// Expiry of `source`'s contribution to effect idx `eidx`: 0 for a hold, null when none.
/proc/contribution_contrib_expiry(datum/scheduler_record/rec, eidx, datum/source, key)
	var/i = rec.contribs ? contribution_contrib_find(rec, eidx, source, key) : 0
	return i ? rec.contribs[i + OM_C_EXPIRES] : null

/// Releases every timed contribution to `eff` on `rec` (holds stay).
/proc/contribution_contrib_release_timed(datum/scheduler_record/rec, datum/effect_definition/eff)
	var/i = 1
	var/removed = FALSE
	while(i <= length(rec.contribs))
		if(rec.contribs[i + OM_C_EFFECT] == eff.idx && rec.contribs[i + OM_C_EXPIRES])
			contribution_contrib_remove(rec, eff, i)
			removed = TRUE
			continue
		i += OM_C_STRIDE
	if(removed)
		contribution_expiry_reschedule(rec)

/// When `source`'s contribution to `effect_id` on `target` expires (scheduler
/// time, deciseconds): 0 for a hold, null when there is none.
/proc/contribution_expires_at(datum/target, effect_id, datum/source, key)
	var/datum/scheduler_record/rec = target?.om_rec
	if(!rec?.contribs)
		return null
	return contribution_contrib_expiry(rec, definition_registry().effect(effect_id).idx, source, key)

/// The time `E`'s scheduler runs on (world.time live, injected in tests). Use it
/// with contribution_apply_until()/contribution_expires_at() so tests on a test scheduler agree.
/proc/scheduler_time_of(datum/E)
	var/datum/scheduler_record/rec = E?.om_rec
	return rec ? rec.sched.now() : time_scheduler().now()

/proc/contribution_release(datum/target, effect_id, datum/source, key)
	var/datum/scheduler_record/rec = target?.om_rec
	if(!rec?.contribs)
		return FALSE
	var/datum/effect_definition/eff = definition_registry().effect(effect_id)
	var/i = contribution_contrib_find(rec, eff.idx, source, key)
	if(!i)
		return FALSE
	contribution_contrib_remove(rec, eff, i)
	return TRUE

/// TRUE when the combined value differs from the effect's default (for
/// COMBINE_ANY: when anything contributes).
/proc/contribution_has(datum/target, effect_id)
	var/v = contribution_value_of(target, effect_id)
	if(islist(v))
		return length(v) > 0
	var/datum/effect_definition/eff = definition_registry().effect(effect_id)
	return v != eff.default_value

/// The combined value. COMBINE_SUM_PER_KEY returns a shared list (read only).
/proc/contribution_value_of(datum/target, effect_id)
	var/datum/effect_definition/eff = definition_registry().effect(effect_id)
	var/datum/scheduler_record/rec = target?.om_rec
	if(!rec)
		if(eff.expr)
			return contribution_effect_eval(null, eff.expr)
		return eff.default_value
	return contribution_effect_value(rec, eff)

// ---------------------------------------------------------------- store internals

/proc/contribution_contrib_find(datum/scheduler_record/rec, eidx, source, key)
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		if(C[i + OM_C_EFFECT] == eidx && C[i + OM_C_SOURCE] == source && C[i + OM_C_KEY] == key)
			return i
	return 0

/proc/contribution_contrib_set(datum/scheduler_record/rec, datum/effect_definition/eff, datum/source, value, expires, key, duration, exact = FALSE)
	if(eff.expr)
		CRASH("om: [eff.id] is a composite effect; contribute to its parts")
	if(eff.combine == COMBINE_SUM_PER_KEY && (isnull(key) || isnum(key)))
		CRASH("om: [eff.id] needs a text or path key")
	var/datum/time_scheduler/sched = rec.sched
	if(eff.clock_idx)
		contribution_clock_settle(rec, eff.clock_idx)
	var/old = contribution_effect_value(rec, eff)
	var/i = contribution_contrib_find(rec, eff.idx, source, key)
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
		var/datum/scheduler_record/srec = scheduler_record_of(source)
		if(srec)
			LAZYOR(srec.held_on, rec.owner)
	contribution_cval_drop(rec, eff.idx)
	contribution_effect_changed(rec, eff, old)

/proc/contribution_contrib_remove(datum/scheduler_record/rec, datum/effect_definition/eff, i)
	if(eff.clock_idx)
		contribution_clock_settle(rec, eff.clock_idx)
	var/old = contribution_effect_value(rec, eff)
	rec.contribs.Cut(i, i + OM_C_STRIDE)
	if(!length(rec.contribs))
		rec.contribs = null
	contribution_cval_drop(rec, eff.idx)
	contribution_effect_changed(rec, eff, old)

/proc/contribution_cval_drop(datum/scheduler_record/rec, eidx)
	var/list/V = rec.cval
	for(var/i in 1 to length(V) step 2)
		if(V[i] == eidx)
			V.Cut(i, i + 2)
			return

/proc/contribution_effect_value(datum/scheduler_record/rec, datum/effect_definition/eff)
	if(eff.expr)
		return contribution_effect_eval(rec, eff.expr)
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
/proc/contribution_effect_eval(datum/scheduler_record/rec, expr)
	if(istext(expr))
		var/datum/effect_definition/part = definition_registry().effect(expr)
		var/v = rec ? contribution_effect_value(rec, part) : part.default_value
		return v
	var/list/L = expr
	switch(L[1])
		if("not")
			return !contribution_effect_eval(rec, L[2])
		if("all")
			for(var/i in 2 to length(L))
				if(!contribution_effect_eval(rec, L[i]))
					return FALSE
			return TRUE
		if("any")
			for(var/i in 2 to length(L))
				if(contribution_effect_eval(rec, L[i]))
					return TRUE
			return FALSE
		if("sum")
			. = 0
			for(var/i in 2 to length(L))
				. += contribution_effect_eval(rec, L[i])

/// After a contribution changed: framework kinds, subclass hook, composites, channel.
/proc/contribution_effect_changed(datum/scheduler_record/rec, datum/effect_definition/eff, old)
	var/new_value = contribution_effect_value(rec, eff)
	if(!islist(new_value) && new_value == old)
		return
	var/datum/E = rec.owner
	if(eff.implies_idx && !!old != !!new_value)
		// Implied effects are held by the entity itself, keyed by the implying effect.
		var/list/effects = definition_registry().effects
		var/key = "implied:[eff.id]"
		for(var/idx in eff.implies_idx)
			if(new_value)
				contribution_contrib_set(rec, effects[idx], E, TRUE, 0, key, 0)
			else
				var/i = contribution_contrib_find(rec, idx, E, key)
				if(i)
					contribution_contrib_remove(rec, effects[idx], i)
	if(eff.blocks && new_value && !old)
		// An immunity gained ends the timed statuses it blocks.
		var/list/effects = definition_registry().effects
		for(var/idx in eff.blocks)
			contribution_contrib_release_timed(rec, effects[idx])
	switch(eff.kind)
		if(OM_EFFECT_CLOCK_MULT, OM_EFFECT_CLOCK_INHIBIT)
			contribution_clock_changed(rec, eff.clock_idx)
			timers_rate_changed(rec)
	eff.on_changed(E, old, new_value)
	var/bits = eff.channel | CHANGE_EFFECTS
	var/list/keys = eff.publishes ? list(eff.publishes) : null
	if(eff.dependents)
		var/list/effects = definition_registry().effects
		for(var/dep_idx in eff.dependents)
			var/datum/effect_definition/dep = effects[dep_idx]
			bits |= dep.channel
			if(dep.publishes)
				LAZYOR(keys, dep.publishes)
	if(E)
		state_changed(E, bits)
		for(var/key in keys)
			PUBLISH_CHANGE(E, key)

// ---------------------------------------------------------------- expiry

/// The next expiry on `rec`, as one deadline of the internal expiry behaviour.
/proc/contribution_expiry_reschedule(datum/scheduler_record/rec)
	var/soonest = 0
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		var/exp = C[i + OM_C_EXPIRES]
		if(exp && (!soonest || exp < soonest))
			soonest = exp
	var/datum/definition_registry/reg = definition_registry()
	if(soonest)
		deadline_deadline(rec.owner, max(soonest - rec.sched.now(), 0), reg.expiry_behaviour)
	else
		deadline_cancel_after(rec.owner, reg.expiry_behaviour)

/datum/scheduled_behaviour/internal
	abstract_type = /datum/scheduled_behaviour/internal

/datum/scheduled_behaviour/internal/expiry
	name = "om: contribution expiry"
	lane = LANE_URGENT

/datum/scheduled_behaviour/internal/expiry/on_deadline(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	var/t = rec.sched.now()
	var/list/effects = definition_registry().effects
	var/i = 1
	while(i <= length(rec.contribs))
		var/exp = rec.contribs[i + OM_C_EXPIRES]
		if(exp && exp <= t)
			contribution_contrib_remove(rec, effects[rec.contribs[i + OM_C_EFFECT]], i)
			continue
		i += OM_C_STRIDE
	contribution_expiry_reschedule(rec)

// ---------------------------------------------------------------- source lifetime and hooks

/// Releases every contribution `source` holds anywhere (source deleted, edge unlinked).
/proc/contribution_release_all_from(datum/source)
	var/datum/scheduler_record/srec = source.om_rec
	if(!srec?.held_on)
		return
	var/list/targets = srec.held_on
	srec.held_on = null
	var/list/effects = definition_registry().effects
	for(var/datum/target as anything in targets)
		var/datum/scheduler_record/rec = target.om_rec
		if(!rec)
			continue
		var/i = 1
		while(i <= length(rec.contribs))
			if(rec.contribs[i + OM_C_SOURCE] == source)
				contribution_contrib_remove(rec, effects[rec.contribs[i + OM_C_EFFECT]], i)
				continue
			i += OM_C_STRIDE
		contribution_expiry_reschedule(rec)

/// Target teardown: forget the contributions on `E` and every back-reference to it.
/proc/contribution_clear_target(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	var/list/C = rec.contribs
	for(var/i in 1 to length(C) step OM_C_STRIDE)
		var/datum/source = C[i + OM_C_SOURCE]
		var/datum/scheduler_record/srec = source?.om_rec
		if(srec)
			LAZYREMOVE(srec.held_on, E)
	for(var/datum/holder as anything in rec.hook_holders)
		var/datum/scheduler_record/hrec = holder.om_rec
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
	rec.named_verbs = null

/// After a `holds` hook returns: every hold the hook made before but not this
/// time is released.
/proc/contribution_reconcile_holds(datum/scheduler_record/rec, bid, epoch)
	var/list/log = rec.hold_log
	if(!log)
		return
	var/list/effects = definition_registry().effects
	var/j = 1
	while(j <= length(log))
		if(log[j] != bid)
			j += 5
			continue
		var/datum/target = log[j + 1]
		var/datum/scheduler_record/trec = target?.om_rec
		var/i = trec ? contribution_contrib_find(trec, log[j + 2], log[j + 3], log[j + 4]) : 0
		if(i && trec.contribs[i + OM_C_EPOCH] == epoch)
			j += 5
			continue
		log.Cut(j, j + 5)
		if(i)
			contribution_contrib_remove(trec, effects[trec.contribs[i + OM_C_EFFECT]], i)
	if(!length(log))
		rec.hold_log = null

/// Behaviour stopped: all of its hook holds go.
/proc/contribution_release_hook_holds(datum/scheduler_record/rec, bid)
	var/list/log = rec.hold_log
	if(!log)
		return
	var/list/effects = definition_registry().effects
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
		var/datum/scheduler_record/trec = target?.om_rec
		if(!trec)
			continue
		var/i = contribution_contrib_find(trec, eidx, source, key)
		if(i)
			contribution_contrib_remove(trec, effects[eidx], i)
	if(!length(log))
		rec.hold_log = null

// ---------------------------------------------------------------- clocks

/// Stride 4 entry for clock `cidx`, created on first need.
/proc/contribution_clock_entry(datum/scheduler_record/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return i
	var/t = rec.sched.now()
	LAZYADD(rec.clocks, list(cidx, contribution_clock_compute(rec, cidx), t, t))
	return length(rec.clocks) - 3

/proc/contribution_clock_compute(datum/scheduler_record/rec, cidx)
	var/datum/definition_registry/reg = definition_registry()
	var/datum/clock_definition/C = reg.clocks[cidx]
	if(C.id == CLOCK_BIO)
		// Biological time runs at the clock_rate_bio stat (MIN, base 1): stasis holds it lower (bio_clock_rate_changed()).
		var/rate = rec.owner.biological_clock_rate()
		return isnull(rate) ? 1 : clamp(rate, C.min_rate, C.max_rate)
	var/mult = contribution_effect_value(rec, reg.effects[C.mult_idx])
	var/inhibit = contribution_effect_value(rec, reg.effects[C.inhibit_idx])
	return clamp(mult * (1 - clamp(inhibit, 0, 1)), C.min_rate, C.max_rate)

/// The entity's rate in clock `cidx` (1 when nothing modifies it).
/proc/contribution_clock_rate(datum/scheduler_record/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return K[i + 1]
	return contribution_clock_compute(rec, cidx)

/// Local (clock) time in deciseconds.
/proc/contribution_clock_local(datum/scheduler_record/rec, cidx)
	var/list/K = rec.clocks
	for(var/i in 1 to length(K) step 4)
		if(K[i] == cidx)
			return K[i + 2] + (rec.sched.now() - K[i + 3]) * K[i + 1]
	return rec.sched.now()

/// Folds elapsed time into local time at the current rate. Always before a rate change.
/proc/contribution_clock_settle(datum/scheduler_record/rec, cidx)
	var/i = contribution_clock_entry(rec, cidx)
	var/list/K = rec.clocks
	var/t = rec.sched.now()
	K[i + 2] += (t - K[i + 3]) * K[i + 1]
	K[i + 3] = t

/// After a clock effect changed: new rate, clocked deadlines re-inserted,
/// roster re-synced (a zero rate sleeps cadence work).
/proc/contribution_clock_changed(datum/scheduler_record/rec, cidx)
	var/i = contribution_clock_entry(rec, cidx)
	var/list/K = rec.clocks
	var/new_rate = contribution_clock_compute(rec, cidx)
	if(K[i + 1] == new_rate)
		return
	K[i + 1] = new_rate
	deadline_clock_reschedule(rec, cidx)
	entity_sync_all(rec)

/// The time on `E`'s clock `clock_id`, in deciseconds (doc/rewrite/final_api.html section 3). Body and medical code that needs
/// "how much biological time has passed" reads CLOCK_BIO here instead of world.time: it runs at the clock_rate_bio stat, so
/// stasis slows or stops it. An entity whose clock never moved off rate 1 reads its scheduler's time.
/proc/clock_now(datum/E, clock_id)
	var/datum/clock_definition/C = definition_registry().clock_by_id[clock_id]
	if(!C)
		CRASH("om: unknown clock [clock_id]")
	var/datum/scheduler_record/rec = E?.om_rec
	return rec ? contribution_clock_local(rec, C.idx) : time_scheduler().now()

/// STAT_CLOCK_RATE_BIO of `E` moved: biological time so far is folded in at the old rate, then the bio clock, its deadlines,
/// timers and cadences take the new one.
/proc/bio_clock_rate_changed(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	var/static/bio_idx
	if(!bio_idx)
		var/datum/clock_definition/C = definition_registry().clock_by_id[CLOCK_BIO]
		bio_idx = C.idx
	contribution_clock_settle(rec, bio_idx)
	contribution_clock_changed(rec, bio_idx)
	timers_rate_changed(rec)

// ---------------------------------------------------------------- relevance and suspension

/// STAT_RELEVANCE of `E` moved to `level`: the OM record's behaviours pick their cadence by it (rec.relevance) and the Rust side mirrors
/// it; CHANGE_RELEVANCE wakes the sequences sweeping E (seq_channels(), through the dispatch).
/proc/relevance_changed(datum/E, level)
	var/datum/scheduler_record/rec = E.om_rec
	if(rec)
		rec.relevance = level
		entity_sync_all(rec)
	entity_native_relevance(E, level)
	state_changed(E, CHANGE_RELEVANCE) // the stat changed; its channel readers (the sequence sweep, OM cadences) still listen by channel

/// STAT_SUSPENDED of `E` flipped: the OM record's cadences and own-clock timers stop or resume with it.
/proc/suspended_changed(datum/E)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	entity_sync_all(rec)
	timers_rate_changed(rec)

#undef OM_C_EFFECT
#undef OM_C_SOURCE
#undef OM_C_VALUE
#undef OM_C_EXPIRES
#undef OM_C_KEY
#undef OM_C_EPOCH
#undef OM_C_STRIDE

/// Non-biological entities keep the unmodified clock; the lifeform adapter supplies its stat.
/datum/proc/biological_clock_rate()
	return null
