// Object-model core: deadlines and rates (doc/rewrite/object_model_core.md
// sections A.5 and F).
//
// A deadline is three numbers in a wheel bucket and three in the entity's
// record: no datum per timer, no signal registration, no FFI call. One
// deadline per (entity, behaviour); setting it again replaces it (the old
// wheel entry goes stale by generation and is skipped when it comes round).

/// Calls B.on_deadline(E) after `delay` deciseconds (in B's clock, if it has one). `sub`
/// keys further deadlines of the same behaviour on the same entity: OM_DL_THROTTLE is the
/// scheduler's deferred wake, OM_DL_STAGE + n a pipeline stage's rewake (on_keyed_deadline()).
/proc/om_after(datum/E, delay, B, sub = 0)
	var/datum/om/behaviour/def = om_registry().behaviour(B)
	var/datum/om/rec/rec = om_rec_of(E)
	if(!rec)
		return FALSE
	var/datum/om/scheduler/sched = rec.sched
	var/key = def.id + sub * OM_DL_SUB
	var/gen = ++sched.gen
	var/t = sched.now()
	var/local_target = null
	var/due = t + max(delay, 0)
	if(def.clock_idx)
		var/rate = om_clock_rate(rec, def.clock_idx)
		local_target = om_clock_local(rec, def.clock_idx) + max(delay, 0)
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

/proc/om_cancel_after(datum/E, B, sub = 0)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec?.deadlines)
		return FALSE
	var/key = om_registry().behaviour(B).id + sub * OM_DL_SUB
	var/list/D = rec.deadlines
	for(var/i in 1 to length(D) step 3)
		if(D[i] == key)
			D.Cut(i, i + 3)
			if(!length(D))
				rec.deadlines = null
			return TRUE
	return FALSE

/// Cancels every deadline of `B` on `E`, whatever its sub-key.
/proc/om_cancel_all_after(datum/E, B)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec?.deadlines)
		return
	var/bid = om_registry().behaviour(B).id
	var/list/D = rec.deadlines
	var/i = 1
	while(i <= length(D))
		if(D[i] % OM_DL_SUB == bid)
			D.Cut(i, i + 3)
			continue
		i += 3
	if(!length(D))
		rec.deadlines = null

/proc/om_deadline_pending(datum/E, B, sub = 0)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec?.deadlines)
		return FALSE
	var/key = om_registry().behaviour(B).id + sub * OM_DL_SUB
	for(var/i in 1 to length(rec.deadlines) step 3)
		if(rec.deadlines[i] == key)
			return TRUE
	return FALSE

/// A clock's rate changed: clocked deadlines get a new generation and a new
/// real-time position (a rate increase must not wait for the old position).
/proc/om_clock_reschedule(datum/om/rec/rec, cidx)
	var/list/D = rec.deadlines
	if(!D)
		return
	var/datum/om/registry/reg = om_registry()
	var/datum/om/scheduler/sched = rec.sched
	var/t = sched.now()
	for(var/i in 1 to length(D) step 3)
		var/local_target = D[i + 2]
		if(isnull(local_target))
			continue
		var/datum/om/behaviour/B = reg.behaviours[D[i] % OM_DL_SUB]
		if(B.clock_idx != cidx)
			continue
		var/gen = ++sched.gen
		D[i + 1] = gen
		var/rate = om_clock_rate(rec, cidx)
		if(rate > 0)
			var/remaining = max(local_target - om_clock_local(rec, cidx), 0)
			sched.insert_deadline(rec, D[i], gen, t + remaining / rate)

// ---------------------------------------------------------------- rates

/// A value that changes linearly: value at time `at`, plus per_second after.
/// Nothing ticks it. Thresholds publish `channel` on the owner when crossed,
/// found by the deadline wheel.
/datum/om/rate
	var/datum/owner
	var/name
	var/value = 0
	var/per_second = 0
	/// Deciseconds.
	var/at = 0
	var/min_value = -INFINITY
	var/max_value = INFINITY
	var/channel = 0
	/// Levels whose crossing publishes `channel`.
	var/list/thresholds
	/// Parallel to thresholds: TRUE while value >= level.
	var/list/above

/// Creates a rate owned by `owner` (it lives as long as the owner's record).
/proc/om_rate_new(datum/owner, name, value = 0, per_second = 0, channel = 0, list/thresholds, min_value = -INFINITY, max_value = INFINITY)
	var/datum/om/rec/rec = om_rec_of(owner)
	if(!rec)
		return null
	var/datum/om/rate/R = new
	R.owner = owner
	R.name = name
	R.value = clamp(value, min_value, max_value)
	R.per_second = per_second
	R.at = rec.sched.now()
	R.channel = channel
	R.min_value = min_value
	R.max_value = max_value
	if(thresholds)
		R.thresholds = thresholds.Copy()
		R.above = list()
		for(var/level in R.thresholds)
			R.above += (R.value >= level)
	LAZYADD(rec.rates, R)
	om_rates_reschedule(rec)
	return R

/proc/om_rate_named(datum/owner, name)
	for(var/datum/om/rate/R as anything in owner?.om_rec?.rates)
		if(R.name == name)
			return R
	return null

/datum/om/rate/proc/sched_now()
	var/datum/om/rec/rec = owner?.om_rec
	return rec ? rec.sched.now() : world.time

/// Value now.
/datum/om/rate/proc/now()
	return clamp(value + per_second * (sched_now() - at) / 10, min_value, max_value)

/// Settles the value at now, then changes the rate.
/datum/om/rate/proc/set_rate(new_per_second)
	settle()
	per_second = new_per_second
	after_change()

/datum/om/rate/proc/set_value(new_value)
	value = clamp(new_value, min_value, max_value)
	at = sched_now()
	after_change()

/datum/om/rate/proc/settle()
	value = now()
	at = sched_now()

/// Deciseconds until the value reaches `level`, or null if it never will.
/datum/om/rate/proc/time_until(level)
	var/v = now()
	if(v == level)
		return 0
	if(!per_second || (level > v) != (per_second > 0))
		return null
	if(level > max_value || level < min_value)
		return null
	return (level - v) / per_second * 10

/datum/om/rate/proc/after_change()
	check_thresholds()
	var/datum/om/rec/rec = owner?.om_rec
	if(rec)
		om_rates_reschedule(rec)

/// Publishes `channel` if any threshold changed side.
/datum/om/rate/proc/check_thresholds()
	if(!thresholds)
		return
	var/v = now()
	var/crossed = FALSE
	for(var/i in 1 to length(thresholds))
		var/is_above = (v >= thresholds[i])
		if(is_above != above[i])
			above[i] = is_above
			crossed = TRUE
	if(crossed && channel && owner)
		om_changed(owner, channel)

/// Next crossing among all the owner's rates, as one deadline.
/proc/om_rates_reschedule(datum/om/rec/rec)
	var/soonest = null
	for(var/datum/om/rate/R as anything in rec.rates)
		for(var/level in R.thresholds)
			var/t = R.time_until(level)
			if(!isnull(t) && t > 0 && (isnull(soonest) || t < soonest))
				soonest = t
	var/datum/om/registry/reg = om_registry()
	if(isnull(soonest))
		om_cancel_after(rec.owner, reg.rate_behaviour)
	else
		om_after(rec.owner, CEILING(soonest, 1), reg.rate_behaviour)

/datum/om/behaviour/internal/rates
	name = "om: rate thresholds"
	lane = LANE_URGENT

/datum/om/behaviour/internal/rates/on_deadline(datum/E)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	for(var/datum/om/rate/R as anything in rec.rates)
		R.check_thresholds()
	om_rates_reschedule(rec)
