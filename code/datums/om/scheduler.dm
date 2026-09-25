// Object-model core: the scheduler (doc/rewrite/object_model_core.md section A).
//
// One instance runs live (SSbehaviours). Unit tests make their own with
// om_test_begin(): same code, injectable time, call caps instead of tick
// usage for budgets, and scheduler_advance(seconds).
//
// Per run, in order:
//   1. deadlines (bucketed wheel, guaranteed OM_DEADLINE_SHARE of the budget)
//   2. borrow pass: rings about to breach their max_interval, from the whole budget
//   3. each lane in order with its guaranteed share: eager derived values
//      (LANE_DERIVED), services (LANE_DERIVED), wakes, then cadence rings
//   4. whatever budget is left, to any lane with work left, in lane order
// Every call site checks the budget after each entity, so each phase makes
// progress every run and none can starve the others.

GLOBAL_DATUM(om_sched, /datum/om/scheduler)
GLOBAL_DATUM(om_live_sched, /datum/om/scheduler)

/proc/om_scheduler()
	RETURN_TYPE(/datum/om/scheduler)
	if(!GLOB.om_sched)
		if(!GLOB.om_live_sched)
			GLOB.om_live_sched = new /datum/om/scheduler
		GLOB.om_sched = GLOB.om_live_sched
	return GLOB.om_sched

/// Starts a deterministic test scheduler (time 0, fixed phases). Entities
/// that join while it is current belong to it.
/proc/om_test_begin()
	RETURN_TYPE(/datum/om/scheduler)
	om_registry()
	var/datum/om/scheduler/sched = new /datum/om/scheduler
	sched.manual_time = 0
	sched.deterministic = TRUE
	sched.dl_cursor = 0
	GLOB.om_sched = sched
	return sched

/proc/om_test_end()
	if(!GLOB.om_live_sched)
		GLOB.om_live_sched = new /datum/om/scheduler
	GLOB.om_sched = GLOB.om_live_sched

/// Advances the current (test) scheduler by `seconds`, one slot at a time.
/proc/scheduler_advance(seconds)
	om_scheduler().advance(seconds)

/datum/om/scheduler
	/// Null: world.time. A number: injected time (deciseconds).
	var/manual_time
	var/deterministic = FALSE
	var/phase_seed = 0
	var/gen = 0

	/// behaviour id -> list of rings (one per interval in use).
	var/list/rings = list()
	/// lane -> rings, in behaviour id order.
	var/list/lane_rings
	/// lane -> recs with pending wakes.
	var/list/wake_q
	var/list/service_queue = list()
	/// Recs with eager derived values to recompute.
	var/list/derived_queue = list()

	var/bulk_depth = 0
	var/list/bulk_list = list()

	/// Deadline wheel: OM_DEADLINE_BUCKETS lists of (rec, bid, gen, due) entries.
	var/list/buckets
	/// Next unprocessed decisecond.
	var/dl_cursor = 0
	var/dl_processing = FALSE

	/// Events (event.dm).
	var/emit_depth = 0
	var/list/event_queue = list()

	/// Hook context for holds reconciliation (contribution.dm).
	var/hook_epoch = 0
	var/cur_epoch = 0
	var/datum/om/rec/ctx_rec
	var/ctx_bid = 0

	/// Budget shares per lane (fractions of the run's budget).
	var/list/lane_share = list(0.3, 0.3, 0.15, 0.15, 0.1)
	/// Tests: max hook calls per lane per run (list of 5), and for deadlines.
	var/list/harness_caps
	var/harness_deadline_cap = 0
	/// Current phase's absolute tick usage limit and call cap.
	var/limit = 0
	var/cap = 0
	var/calls = 0
	/// Borrow threshold: a ring whose oldest due slot is this fraction of max_interval late borrows.
	var/borrow_fraction = 0.75

	/// behaviour id -> list(OM_STAT_LEN) counters.
	var/list/stats = list()
	var/list/errors = list()
	/// Tests expecting an error: recorded, no stack trace.
	var/expect_errors = FALSE
	var/last_run_ms = 0
	var/runs = 0

/datum/om/scheduler/New()
	lane_rings = new /list(OM_LANE_COUNT)
	wake_q = new /list(OM_LANE_COUNT)
	for(var/lane in 1 to OM_LANE_COUNT)
		lane_rings[lane] = list()
		wake_q[lane] = list()
	buckets = new /list(OM_DEADLINE_BUCKETS)
	for(var/i in 1 to OM_DEADLINE_BUCKETS)
		buckets[i] = list()
	dl_cursor = round(now())

/datum/om/scheduler/proc/now()
	return isnull(manual_time) ? world.time : manual_time

/datum/om/scheduler/proc/next_phase()
	if(deterministic)
		return phase_seed++
	return rand(0, 65535)

/datum/om/scheduler/proc/error(msg)
	errors += msg
	if(length(errors) > 200)
		errors.Cut(1, 101)
	if(!expect_errors)
		stack_trace("om: [msg]")

/datum/om/scheduler/proc/stat_inc(bid, index, amount = 1)
	var/list/S = stat_for(bid)
	S[index] += amount

/datum/om/scheduler/proc/stat_for(bid)
	RETURN_TYPE(/list)
	var/key = min(bid, OM_MAX_STAT_TYPES)
	if(length(stats) < key)
		stats.len = key
	var/list/S = stats[key]
	if(!S)
		S = new /list(OM_STAT_LEN)
		for(var/i in 1 to OM_STAT_LEN)
			S[i] = 0
		stats[key] = S
	return S

// ---------------------------------------------------------------- rings

/datum/om/ring
	var/datum/om/behaviour/B
	var/interval
	var/size
	var/list/slots
	/// Per slot: time (ds) the slot last began running.
	var/list/last_run
	/// Absolute slot number to process next (never skipped).
	var/next_abs
	/// Slot in progress (deferred mid-slot) or 0, and the position in it.
	var/cur_slot = 0
	var/cur_i = 1
	var/cur_dt = 0

/datum/om/ring/New(datum/om/behaviour/B, interval, now)
	src.B = B
	src.interval = interval
	size = max(1, round(interval / OM_SLOT_DS))
	slots = new /list(size)
	last_run = new /list(size)
	for(var/i in 1 to size)
		slots[i] = list()
		last_run[i] = now
	next_abs = round(now / OM_SLOT_DS) + 1

/datum/om/ring/proc/add(datum/E, phase)
	var/list/L = slots[(phase % size) + 1]
	L += E

/datum/om/ring/proc/remove(datum/E, phase)
	var/s = (phase % size) + 1
	var/list/L = slots[s]
	var/idx = L.Find(E)
	if(!idx)
		return
	L.Cut(idx, idx + 1)
	if(s == cur_slot && idx < cur_i)
		cur_i--

/datum/om/ring/proc/population()
	. = 0
	for(var/list/L as anything in slots)
		. += length(L)

/datum/om/scheduler/proc/ring_for(datum/om/behaviour/B, interval)
	if(length(rings) < B.id)
		rings.len = B.id
	var/list/mine = rings[B.id]
	if(!mine)
		mine = list()
		rings[B.id] = mine
	for(var/datum/om/ring/R as anything in mine)
		if(R.interval == interval)
			return R
	var/datum/om/ring/R = new /datum/om/ring(B, interval, now())
	mine += R
	var/list/lane = lane_rings[B.lane]
	var/pos = length(lane) + 1
	for(var/i in 1 to length(lane))
		var/datum/om/ring/other = lane[i]
		if(other.B.id > B.id)
			pos = i
			break
	lane.Insert(pos, R)
	return R

// ---------------------------------------------------------------- run

/// One scheduler pass. `tick_limit` is an absolute world.tick_usage (live:
/// Master.current_ticklimit). Returns TRUE if all due work finished.
/datum/om/scheduler/proc/run_pass(tick_limit)
	var/start = TICK_USAGE
	var/t = now()
	runs++
	var/avail = max(tick_limit - start, 0)
	var/done = TRUE

	// 1. Deadlines.
	limit = start + avail * OM_DEADLINE_SHARE
	cap = harness_deadline_cap
	calls = 0
	if(!run_deadlines(t))
		done = FALSE

	// 2. Borrow pass for rings near their staleness bound.
	limit = tick_limit
	for(var/lane in 1 to OM_LANE_COUNT)
		cap = harness_caps ? harness_caps[lane] : 0
		calls = 0
		for(var/datum/om/ring/R as anything in lane_rings[lane])
			if(ring_urgent(R, t))
				run_ring(R, t)

	// 3. Lanes with guaranteed shares.
	for(var/lane in 1 to OM_LANE_COUNT)
		limit = min(TICK_USAGE + avail * lane_share[lane], tick_limit)
		cap = harness_caps ? harness_caps[lane] : 0
		calls = 0
		if(!run_lane(lane, t))
			done = FALSE

	// 4. Leftover budget.
	if(!done && TICK_USAGE < tick_limit && !harness_caps)
		done = TRUE
		limit = tick_limit
		cap = 0
		if(!run_deadlines(t))
			done = FALSE
		for(var/lane in 1 to OM_LANE_COUNT)
			if(!run_lane(lane, t))
				done = FALSE
	last_run_ms = TICK_USAGE_TO_MS(start)
	return done

/datum/om/scheduler/proc/out_of_budget()
	if(TICK_USAGE > limit)
		return TRUE
	if(cap && ++calls >= cap)
		return TRUE
	return FALSE

/datum/om/scheduler/proc/run_lane(lane, t)
	. = TRUE
	// Eager derived values are inputs to wakes in every lane: a behaviour in
	// an earlier lane observing a derived channel must see the change this
	// pass, not the next. The queue is empty (one length check) almost always.
	if(!run_derived_queue())
		return FALSE
	if(lane == LANE_DERIVED)
		if(!run_services())
			return FALSE
	if(!run_wakes(lane))
		return FALSE
	for(var/datum/om/ring/R as anything in lane_rings[lane])
		if(!run_ring(R, t))
			return FALSE

/datum/om/scheduler/proc/ring_urgent(datum/om/ring/R, t)
	if(R.next_abs > round(t / OM_SLOT_DS))
		return FALSE
	var/s = (R.next_abs % R.size) + 1
	if(!length(R.slots[s]))
		return FALSE
	return (t - R.last_run[s]) >= R.B.compiled_max_interval * borrow_fraction

/// Processes every due slot of `R` in order. Never skips a slot: a slot not
/// reached this run is processed next run with its real elapsed dt.
/datum/om/scheduler/proc/run_ring(datum/om/ring/R, t)
	var/now_abs = round(t / OM_SLOT_DS)
	var/datum/om/behaviour/B = R.B
	// More than a full ring behind (skipped ticks, a long lag): every slot is
	// due, so each runs once, with its real elapsed dt, instead of the same
	// slot running several times in one pass with dt 0.
	if(!R.cur_slot && now_abs - R.next_abs >= R.size)
		R.next_abs = now_abs - R.size + 1
	while(R.next_abs <= now_abs)
		var/s = (R.next_abs % R.size) + 1
		var/list/L = R.slots[s]
		if(!R.cur_slot)
			if(!length(L))
				R.last_run[s] = t
				R.next_abs++
				continue
			R.cur_slot = s
			R.cur_i = 1
			var/dt_ds = t - R.last_run[s]
			R.cur_dt = dt_ds / 10
			R.last_run[s] = t
			var/list/S = stat_for(B.id)
			var/late = t - R.next_abs * OM_SLOT_DS
			if(late > S[OM_STAT_LATE_MAX])
				S[OM_STAT_LATE_MAX] = late
			if(dt_ds > B.compiled_max_interval)
				S[OM_STAT_BREACHES]++
		if(!run_slot(R, L))
			stat_inc(B.id, OM_STAT_DEFERRALS)
			return FALSE
		R.cur_slot = 0
		R.next_abs++
	return TRUE

/// Runs one slot's entities from R.cur_i. FALSE when the budget ran out.
/datum/om/scheduler/proc/run_slot(datum/om/ring/R, list/L)
	var/datum/om/behaviour/B = R.B
	var/dt = R.cur_dt
	var/fast = !(B.clock_idx || B.max_dt || B.step_interval || B.holds)
	var/lim = limit
	var/cp = cap
	var/n_calls = calls
	var/ran = 0
	var/t0 = TICK_USAGE
	var/out = FALSE
	while(TRUE)
		try
			if(fast)
				while(R.cur_i <= length(L))
					var/datum/E = L[R.cur_i]
#ifdef OM_PROFILE_CALLS
					var/c0 = TICK_USAGE
#endif
					B.tick(E, dt)
#ifdef OM_PROFILE_CALLS
					var/list/PS = stat_for(B.id)
					PS[OM_STAT_CALL_MAX] = max(PS[OM_STAT_CALL_MAX], TICK_USAGE_TO_MS(c0))
#endif
					ran++
					if(R.cur_i <= length(L) && L[R.cur_i] == E)
						R.cur_i++
					if(TICK_USAGE > lim || (cp && ++n_calls >= cp))
						out = TRUE
						break
			else
				while(R.cur_i <= length(L))
					var/datum/E = L[R.cur_i]
					tick_slow(B, E, dt)
					ran++
					if(R.cur_i <= length(L) && L[R.cur_i] == E)
						R.cur_i++
					if(TICK_USAGE > lim || (cp && ++n_calls >= cp))
						out = TRUE
						break
			break
		catch(var/exception/e)
			error("[B.name] tick: [e] ([e.file]:[e.line])")
			stat_inc(B.id, OM_STAT_ERRORS)
			R.cur_i++
	calls = n_calls
	var/list/S = stat_for(B.id)
	S[OM_STAT_RUNS] += ran
	S[OM_STAT_MS] += TICK_USAGE_TO_MS(t0)
	return !(out && R.cur_i <= length(L))

/// Clocked, substepped, fixed-step or holding behaviours.
/datum/om/scheduler/proc/tick_slow(datum/om/behaviour/B, datum/E, dt)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return
	if(B.clock_idx)
		dt *= om_clock_rate(rec, B.clock_idx)
	if(B.step_interval)
		var/acc = dt
		var/k = 0
		for(var/i in 1 to length(rec.steps) step 2)
			if(rec.steps[i] == B.id)
				k = i
				acc += rec.steps[i + 1]
				break
		var/n = round(acc / B.step_interval)
		if(n > B.max_catchup)
			stat_inc(B.id, OM_STAT_BREACHES)
			n = B.max_catchup
			acc = n * B.step_interval
		acc -= n * B.step_interval
		if(k)
			rec.steps[k + 1] = acc
		else
			LAZYADD(rec.steps, list(B.id, acc))
		for(var/i in 1 to n)
			call_hook(rec, B, OM_HOOK_STEP)
		return
	if(B.max_dt && dt > B.max_dt)
		var/n = min(CEILING(dt / B.max_dt, 1), OM_MAX_SUBSTEPS)
		var/sub = dt / n
		for(var/i in 1 to n)
			call_hook(rec, B, OM_HOOK_TICK, sub)
		return
	call_hook(rec, B, OM_HOOK_TICK, dt)

/// Every hook except the fast cadence path goes through here: runtimes are
/// caught (no flag or depth can stick), return values are ignored, and
/// holds made by `holds` behaviours are reconciled.
/datum/om/scheduler/proc/call_hook(datum/om/rec/rec, datum/om/behaviour/B, kind, arg)
	var/datum/E = rec.owner
	if(!E)
		return
	var/prev_rec = ctx_rec
	var/prev_bid = ctx_bid
	var/prev_epoch = cur_epoch
	if(B.holds)
		ctx_rec = rec
		ctx_bid = B.id
		cur_epoch = ++hook_epoch
	var/failed = FALSE
	try
		switch(kind)
			if(OM_HOOK_TICK)
				B.tick(E, arg)
			if(OM_HOOK_WAKE)
				B.on_wake(E, arg)
			if(OM_HOOK_DEADLINE)
				B.on_deadline(E)
			if(OM_HOOK_STEP)
				B.on_step(E)
			if(OM_HOOK_START)
				B.on_start(E)
			if(OM_HOOK_STOP)
				B.on_stop(E)
			if(OM_HOOK_NATIVE)
				B.on_native(E, arg)
	catch(var/exception/e)
		failed = TRUE
		error("[B.name] hook [kind]: [e] ([e.file]:[e.line])")
		stat_inc(B.id, OM_STAT_ERRORS)
	if(B.holds)
		if(!failed && kind != OM_HOOK_STOP && !rec.torn_down)
			om_reconcile_holds(rec, B.id, cur_epoch)
		ctx_rec = prev_rec
		ctx_bid = prev_bid
		cur_epoch = prev_epoch

/// Runs `B`'s tick on `E` now, outside its ring (Life's run-this-system-now
/// path). dt is the caller's; the ring's own schedule is unchanged.
/proc/om_tick_now(datum/E, B, dt)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec)
		return FALSE
	var/datum/om/behaviour/def = om_registry().behaviour(B)
	if(!rec.att.Find(def))
		return FALSE
	rec.sched.call_hook(rec, def, OM_HOOK_TICK, dt)
	return TRUE

// ---------------------------------------------------------------- wakes

/datum/om/scheduler/proc/enqueue(datum/om/rec/rec, lane)
	var/bit = 1 << lane
	if(rec.queued & bit)
		return
	rec.queued |= bit
	var/list/Q = wake_q[lane]
	Q += rec

/// One on_wake per behaviour per entity per run, with the union of bits.
/// Changes raised while draining go to the next run, except to behaviours
/// later in the same entity's run order, which see them this run.
/datum/om/scheduler/proc/run_wakes(lane)
	var/list/Q = wake_q[lane]
	if(!length(Q))
		return TRUE
	wake_q[lane] = list()
	var/bit = 1 << lane
	var/idx = 0
	while(idx < length(Q))
		idx++
		var/datum/om/rec/rec = Q[idx]
		rec.queued &= ~bit
		if(rec.torn_down)
			continue
		var/i = 1
		while(i <= length(rec.att))
			var/datum/om/behaviour/B = rec.att[i]
			var/bits = rec.att_pend[i]
			if(B.lane != lane || !bits)
				i++
				continue
			rec.att_pend[i] = 0
			if(B.compiled_wake_if && !isnull(B.compiled_wake_if.why_not(rec.owner, null)))
				i++
				continue
			stat_inc(B.id, OM_STAT_WAKES)
			call_hook(rec, B, OM_HOOK_WAKE, bits)
			if(rec.torn_down)
				break
			var/at = rec.att.Find(B)
			i = (at ? at : i - 1) + 1
		if(out_of_budget() && idx < length(Q))
			var/list/carry = Q.Copy(idx + 1) + wake_q[lane]
			wake_q[lane] = list()
			for(var/datum/om/rec/left as anything in carry)
				left.queued &= ~bit
			for(var/datum/om/rec/left as anything in carry)
				enqueue(left, lane)
			return FALSE
	return TRUE

/datum/om/scheduler/proc/run_services()
	if(!length(service_queue))
		return TRUE
	var/list/Q = service_queue
	service_queue = list()
	for(var/idx in 1 to length(Q))
		var/datum/om/rec/rec = Q[idx]
		var/bits = rec.service_pend
		rec.service_pend = 0
		if(rec.torn_down || !bits)
			continue
		var/datum/E = rec.owner
		for(var/datum/om/service/S as anything in rec.table.services)
			var/mine = 0
			for(var/observed in S.wake_on_any)
				if(istype(E, observed))
					mine |= S.wake_on_any[observed]
			if(mine & bits)
				try
					S.on_changes(E, mine & bits)
				catch(var/exception/e)
					error("[S.type] on_changes: [e]")
		if(out_of_budget() && idx < length(Q))
			service_queue = Q.Copy(idx + 1) + service_queue
			return FALSE
	return TRUE

// ---------------------------------------------------------------- deadlines

/datum/om/scheduler/proc/insert_deadline(datum/om/rec/rec, bid, gen, due)
	// The first bucket whose turn comes at or after `due`. round() is floor
	// in DM: a fractional due (clock rescheduling, sub-decisecond world.time)
	// landed in a bucket that ran while the entry was not yet due, was kept
	// there, and waited a whole wheel turn.
	var/ds = CEILING(due, 1)
	var/floor_ds = dl_processing ? dl_cursor + 1 : dl_cursor
	if(ds < floor_ds)
		ds = floor_ds
	var/list/L = buckets[(ds % OM_DEADLINE_BUCKETS) + 1]
	L.Add(rec, bid, gen, due)

/datum/om/scheduler/proc/run_deadlines(t)
	var/now_ds = round(t)
	if(dl_cursor > now_ds)
		return TRUE
	. = TRUE
	dl_processing = TRUE
	try
		if(now_ds - dl_cursor >= OM_DEADLINE_BUCKETS)
			// Far behind (a test jumping hours): one sweep of every bucket.
			for(var/b in 1 to OM_DEADLINE_BUCKETS)
				if(!run_bucket(b, t))
					. = FALSE
					break
			if(.)
				dl_cursor = now_ds + 1
		else
			while(dl_cursor <= now_ds)
				if(!run_bucket((dl_cursor % OM_DEADLINE_BUCKETS) + 1, t))
					. = FALSE
					break
				dl_cursor++
	catch(var/exception/e)
		error("deadline wheel: [e]")
	dl_processing = FALSE

/datum/om/scheduler/proc/run_bucket(b, t)
	var/list/L = buckets[b]
	if(!length(L))
		return TRUE
	buckets[b] = list()
	var/list/keep = list()
	var/datum/om/registry/reg = om_registry()
	var/i = 1
	var/ok = TRUE
	while(i <= length(L))
		var/datum/om/rec/rec = L[i]
		var/bid = L[i + 1]
		var/gen_i = L[i + 2]
		var/due = L[i + 3]
		i += 4
		if(due > t)
			keep.Add(rec, bid, gen_i, due)
			continue
		fire_deadline(rec, bid, gen_i, t, reg)
		if(out_of_budget() && i <= length(L))
			keep += L.Copy(i)
			ok = FALSE
			break
	var/list/added = buckets[b]
	buckets[b] = keep + added
	return ok

/datum/om/scheduler/proc/fire_deadline(datum/om/rec/rec, bid, gen_i, t, datum/om/registry/reg)
	if(rec.torn_down || !rec.deadlines)
		return
	var/list/D = rec.deadlines
	var/k = 0
	for(var/j in 1 to length(D) step 3)
		if(D[j] == bid)
			k = j
			break
	if(!k || D[k + 1] != gen_i)
		return
	var/datum/om/behaviour/B = reg.behaviours[bid]
	var/local_target = D[k + 2]
	if(!isnull(local_target))
		var/local_now = om_clock_local(rec, B.clock_idx)
		if(local_now < local_target - 0.001)
			var/rate = om_clock_rate(rec, B.clock_idx)
			if(rate > 0)
				insert_deadline(rec, bid, gen_i, t + (local_target - local_now) / rate)
			return
	D.Cut(k, k + 3)
	stat_inc(bid, OM_STAT_DEADLINES)
	call_hook(rec, B, OM_HOOK_DEADLINE)

// ---------------------------------------------------------------- harness

/// Test harness: advance injected time slot by slot, running each slot.
/datum/om/scheduler/proc/advance(seconds)
	if(isnull(manual_time))
		CRASH("om: advance() on the live scheduler")
	var/target = manual_time + seconds * 10
	while(manual_time < target)
		manual_time = min(manual_time + OM_SLOT_DS, target)
		run_pass(1e9)

/// Test harness: jump time without running (simulates skipped ticks).
/datum/om/scheduler/proc/jump(seconds)
	manual_time += seconds * 10

// ---------------------------------------------------------------- diagnostics

/// Admin-readable snapshot: per behaviour type counters, ring sizes, queue lengths.
/proc/om_diagnostics(datum/om/scheduler/sched)
	sched = sched || GLOB.om_live_sched || om_scheduler()
	var/datum/om/registry/reg = om_registry()
	. = list()
	var/list/types = list()
	for(var/bid in 1 to length(sched.stats))
		var/list/S = sched.stats[bid]
		if(!S)
			continue
		var/datum/om/behaviour/B = bid <= length(reg.behaviours) ? reg.behaviours[bid] : null
		var/population = 0
		if(bid <= length(sched.rings))
			for(var/datum/om/ring/R as anything in sched.rings[bid])
				population += R.population()
		types[B ? B.name : "other"] = list(
			"runs" = S[OM_STAT_RUNS],
			"ms" = round(S[OM_STAT_MS], 0.001),
			"late_max_ds" = S[OM_STAT_LATE_MAX],
			"deferrals" = S[OM_STAT_DEFERRALS],
			"breaches" = S[OM_STAT_BREACHES],
			"wakes" = S[OM_STAT_WAKES],
			"deadlines" = S[OM_STAT_DEADLINES],
			"errors" = S[OM_STAT_ERRORS],
			"call_max_ms" = S[OM_STAT_CALL_MAX],
			"population" = population,
		)
	.["types"] = types
	var/list/queues = list()
	for(var/lane in 1 to OM_LANE_COUNT)
		queues += length(sched.wake_q[lane])
	.["wake_queues"] = queues
	.["last_run_ms"] = sched.last_run_ms
	.["runs"] = sched.runs
	.["errors"] = sched.errors.Copy()
	.["registry_errors"] = reg.errors.Copy()
