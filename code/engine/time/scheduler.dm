// Object-model core: the scheduler (doc/rewrite/object_model_core.md section A).
//
// One instance runs live (SSbehaviours). Unit tests make their own with
// scheduler_test_begin(): same code, injectable time, call caps instead of tick
// usage for budgets, and scheduler_advance(seconds).
//
// Per run, in order:
//   0. the Rust world step (world_watches.dm), once per tick: its wakes queue on their lanes
//   1. deadlines (bucketed wheel, guaranteed OM_DEADLINE_SHARE of the budget)
//   2. borrow pass: rings about to breach their max_interval, from the whole budget
//   3. each lane in order with its guaranteed share: eager derived values
//      (LANE_DERIVED), services (LANE_DERIVED), wakes, then cadence rings
//   4. whatever budget is left, to any lane with work left, in lane order
// Every call site checks the budget after each entity, so each phase makes
// progress every run and none can starve the others.

GLOBAL_DATUM(om_sched, /datum/time_scheduler)
GLOBAL_DATUM(om_live_sched, /datum/time_scheduler)

/proc/time_scheduler()
	RETURN_TYPE(/datum/time_scheduler)
	if(!GLOB.om_sched)
		if(!GLOB.om_live_sched)
			GLOB.om_live_sched = time_scheduler_factory().make()
		GLOB.om_sched = GLOB.om_live_sched
	return GLOB.om_sched

/// Starts a deterministic test scheduler (time 0, fixed phases). Entities
/// that join while it is current belong to it.
/proc/scheduler_test_begin()
	RETURN_TYPE(/datum/time_scheduler)
	definition_registry()
	var/datum/time_scheduler/sched = time_scheduler_factory().make()
	sched.manual_time = 0
	sched.deterministic = TRUE
	sched.slot_ds = OM_SLOT_DS
	sched.phase_seed = 0
	sched.dl_cursor = 0
	// Its own meter: a test pass must not charge the live one. A short ring, since tests never read a long one.
	sched.meter = new /datum/tick_meter(32)
	GLOB.om_sched = sched
	return sched

/proc/scheduler_test_end()
	if(!GLOB.om_live_sched)
		GLOB.om_live_sched = time_scheduler_factory().make()
	GLOB.om_sched = GLOB.om_live_sched

/// Advances the current (test) scheduler by `seconds`, one slot at a time.
/proc/scheduler_advance(seconds)
	time_scheduler().advance(seconds)

/datum/time_scheduler
	/// The slowest single entity step of a recent tick: list(behaviour, entity, name, usage, ms, world_time).
	var/list/slow_step
	/// While a metrics profile capture runs: "behaviour|entity type" -> tick usage spent in its steps, wakes and
	/// deadlines (note_type_cost()), so a busy behaviour's cost can be traced to the entities behind it. Null
	/// otherwise, which costs each step one var read.
	var/list/type_costs
	/// Null: world.time. A number: injected time (deciseconds).
	var/manual_time
	var/deterministic = FALSE
	/// Next phase handed out. Phases are assigned round robin, so a batch of entities joining
	/// together spreads evenly over a ring's slots instead of clumping by chance.
	var/phase_seed = 0
	/// Width of one cadence slot, deciseconds. Live: one world tick, so a ring's work is spread
	/// over every tick of its interval rather than landing on every Nth tick. Tests: OM_SLOT_DS.
	var/slot_ds = OM_SLOT_DS
	var/gen = 0

	/// behaviour id -> list of rings (one per interval in use).
	var/list/rings
	/// lane -> rings, in behaviour id order.
	var/list/lane_rings
	/// lane -> recs with pending wakes.
	var/list/wake_q
	/// lane -> an empty list swapped in for wake_q[lane] while it drains.
	var/list/wake_spare
	var/list/service_queue
	/// run_services()' second buffer.
	var/list/service_spare = list() // ALLOW(instance_list): scheduler singleton's double buffer
	/// run_bucket()'s buffer for deadlines inserted into the bucket being run.
	var/list/bucket_spare = list() // ALLOW(instance_list): scheduler singleton's double buffer
	/// Recs with eager derived values to recompute.
	var/list/derived_queue

	var/bulk_depth = 0
	var/list/bulk_list

	/// Deadline wheel: OM_DEADLINE_BUCKETS lists of (rec, bid, gen, due) entries.
	var/list/buckets
	/// Next unprocessed decisecond.
	var/dl_cursor = 0
	var/dl_processing = FALSE

	/// Events (event.dm).
	var/emit_depth = 0
	var/list/event_queue

	/// Budget shares per lane (fractions of the run's budget).
	var/list/lane_share = list(0.3, 0.3, 0.15, 0.15, 0.05, 0.05) // ALLOW(instance_list): the scheduler is a singleton (one per live kernel, one per test)
	/// Tests: max hook calls per lane per run (one per lane), and for deadlines.
	var/list/harness_caps
	var/harness_deadline_cap = 0
	/// Current phase's absolute tick usage limit and call cap.
	var/limit = 0
	/// The open pass (pass_begin): when it started, its budget, the scheduler time it covers, and whether all due work finished.
	var/pass_start = 0
	var/pass_avail = 0
	var/pass_t = 0
	var/pass_done = TRUE
	var/cap = 0
	var/calls = 0
	/// Borrow threshold: a ring whose oldest due slot is this fraction of max_interval late borrows.
	var/borrow_fraction = 0.75

	/// RUNLEVEL_* bit of the current runlevel (live: read from Master each pass). Rings of
	/// behaviours whose `runlevels` exclude it go dormant.
	var/runlevel = 0xFFFFFF

	/// Pipelines (pipeline.dm), indexed by pipeline pipe_idx: free frames, parked entities
	/// (each entity's pipe state knows its index) and the audit's round-robin cursor.
	var/list/free_frames
	var/list/parked
	var/list/audit_cursor
	/// Stage profile: "[stage type]" -> sampled ms and calls (pipeline profile_stride).
	var/list/stage_cost
	var/list/stage_calls
	/// Frames run by profiling pipelines (the stage profiler samples every Nth).
	var/pipe_frames = 0

	/// behaviour id -> list(OM_STAT_LEN) counters.
	var/list/stats
	var/list/errors
	/// Tests expecting an error: recorded, no stack trace.
	var/expect_errors = FALSE
	/// Times a lane loop was aborted by a runtime that escaped per-behaviour isolation (run_lane_guarded()).
	var/lane_faults = 0
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	/// Test harness: lane -> TRUE makes run_lane() runtime for that lane (lane-isolation tests).
	var/list/harness_lane_fault
#endif
	var/last_run_ms = 0
	var/runs = 0
	/// Where this scheduler charges what it spends, per system (code/controllers/measure/): the live meter, or a
	/// test's own (scheduler_test_begin()).
	var/datum/tick_meter/meter
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	/// Tests: when a list, every dispatched change is logged here as list(entity, bits).
	var/list/test_raises
#endif

/datum/time_scheduler/New()
	if(!rings)
		rings = list()
	if(!service_queue)
		service_queue = list()
	if(!derived_queue)
		derived_queue = list()
	if(!bulk_list)
		bulk_list = list()
	if(!event_queue)
		event_queue = list()
	if(!free_frames)
		free_frames = list()
	if(!parked)
		parked = list()
	if(!audit_cursor)
		audit_cursor = list()
	if(!stage_cost)
		stage_cost = list()
	if(!stage_calls)
		stage_calls = list()
	if(!stats)
		stats = list()
	if(!errors)
		errors = list()
	lane_rings = new /list(OM_LANE_COUNT)
	wake_q = new /list(OM_LANE_COUNT)
	wake_spare = new /list(OM_LANE_COUNT)
	for(var/lane in 1 to OM_LANE_COUNT)
		lane_rings[lane] = list()
		wake_q[lane] = list()
		wake_spare[lane] = list()
	buckets = new /list(OM_DEADLINE_BUCKETS)
	for(var/i in 1 to OM_DEADLINE_BUCKETS)
		buckets[i] = list()
	dl_cursor = round(now())
	slot_ds = world.tick_lag > 0 ? world.tick_lag : OM_SLOT_DS
	phase_seed = rand(0, 65535)
	meter = km_meter()

/datum/time_scheduler/proc/now()
	return isnull(manual_time) ? world.time : manual_time

/datum/time_scheduler/proc/next_phase()
	return phase_seed++

/datum/time_scheduler/proc/error(msg)
	errors += msg
	if(length(errors) > 200)
		errors.Cut(1, 101)
	if(!expect_errors)
		stack_trace("om: [msg]")

/// error() for a caught exception: recorded like error(), and, unless errors
/// are expected, reported through dq_report_caught() so the runtime log gets
/// the exception's own file/line/stack and a test run counts it.
/datum/time_scheduler/proc/report_caught(exception/e, msg)
	errors += msg
	if(length(errors) > 200)
		errors.Cut(1, 101)
	if(!expect_errors)
		dq_report_caught(e, "om: [msg]")

/datum/time_scheduler/proc/stat_inc(bid, index, amount = 1)
	var/list/S = stat_for(bid)
	S[index] += amount

/datum/time_scheduler/proc/stat_for(bid)
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

/datum/cadence_ring
	/// The behaviour this ring runs, by registry id (definition_registry().behaviours); read with behaviour().
	var/behaviour_id
	var/interval
	/// Slot width, deciseconds (the scheduler's slot_ds when the ring was made).
	var/slot_ds = OM_SLOT_DS
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
	/// TRUE while the behaviour's runlevels exclude the current one (no slot runs).
	var/dormant = FALSE
	/// TRUE when an entity left the slot in progress: its entry is null
	/// (a tombstone) until the slot finishes, so positions never shift under
	/// the running loop.
	var/tombstones = FALSE
	/// Entities that joined the slot in progress: appended when it finishes,
	/// so none runs twice in one slot (leave and rejoin mid-slot).
	var/list/pending_adds

/datum/cadence_ring/New(datum/scheduled_behaviour/B, interval, now, slot_ds = OM_SLOT_DS)
	behaviour_id = B.id
	src.interval = interval
	src.slot_ds = slot_ds
	size = max(1, round(interval / slot_ds))
	slots = new /list(size)
	last_run = new /list(size)
	for(var/i in 1 to size)
		slots[i] = list()
		last_run[i] = now
	next_abs = round(now / slot_ds) + 1

/datum/cadence_ring/proc/add(datum/E, phase)
	var/s = (phase % size) + 1
	if(s == cur_slot)
		LAZYADD(pending_adds, E)
		tombstones = TRUE
		return
	var/list/L = slots[s]
	L += E

/datum/cadence_ring/proc/remove(datum/E, phase)
	var/s = (phase % size) + 1
	var/list/L = slots[s]
	var/idx = L.Find(E)
	if(!idx)
		if(s == cur_slot && pending_adds)
			pending_adds -= E
		return
	if(s == cur_slot)
		// The slot is running (or deferred mid-way): keep positions stable so
		// the loop can walk it with a local index. Compacted when it finishes.
		L[idx] = null
		tombstones = TRUE
		return
	L.Cut(idx, idx + 1)

/// After a slot finishes: drop the tombstones left by removals during it.
/datum/cadence_ring/proc/compact(list/L)
	L.RemoveAll(null)
	if(pending_adds)
		L += pending_adds
		pending_adds = null
	tombstones = FALSE

/datum/cadence_ring/proc/population()
	. = 0
	for(var/list/L as anything in slots)
		for(var/E in L)
			if(E)
				.++
	. += length(pending_adds)

/datum/time_scheduler/proc/ring_for(datum/scheduled_behaviour/B, interval)
	if(length(rings) < B.id)
		rings.len = B.id
	var/list/mine = rings[B.id]
	if(!mine)
		mine = list()
		rings[B.id] = mine
	for(var/datum/cadence_ring/R as anything in mine)
		if(R.interval == interval)
			return R
	var/datum/cadence_ring/R = new /datum/cadence_ring(B, interval, now(), slot_ds)
	mine += R
	var/list/lane = lane_rings[B.lane]
	var/pos = length(lane) + 1
	for(var/i in 1 to length(lane))
		var/datum/cadence_ring/other = lane[i]
		if(other.behaviour_id > B.id)
			pos = i
			break
	lane.Insert(pos, R)
	return R

// ---------------------------------------------------------------- run

/// One scheduler pass. `tick_limit` is an absolute world.tick_usage (live:
/// Kernel.current_ticklimit). Returns TRUE if all due work finished.
///
/// The pass is a sequence of pieces (pass_begin ... pass_end). run_pass() runs them all back to back; the
/// kernel tick (controllers/kernel/kernel.dm) runs the same pieces itself, between its own phases.
/datum/time_scheduler/proc/run_pass(tick_limit)
	pass_begin(tick_limit)
	pass_deadlines(tick_limit)
	pass_borrow(tick_limit)
	pass_lanes(tick_limit)
	pass_leftovers(tick_limit)
	return pass_end()

/// Opens a pass: the clock, the runlevel and this pass's budget. Zeroes the per-pass world wake counts, so it
/// runs before the tick's native frame (kernel phase N).
/datum/time_scheduler/proc/pass_begin(tick_limit)
	pass_start = TICK_USAGE
	pass_t = now()
	runs++
	if(isnull(manual_time))
		var/level = Kernel.current_runlevel
		runlevel = level ? (1 << (level - 1)) : 0
	pass_avail = max(tick_limit - pass_start, 0)
	pass_done = TRUE
	if(world_pass_delivered)
		for(var/lane in 1 to OM_LANE_COUNT)
			world_pass_delivered[lane] = 0

/// 1. Deadlines, within OM_DEADLINE_SHARE of the pass's budget.
/datum/time_scheduler/proc/pass_deadlines(tick_limit)
	limit = pass_start + pass_avail * OM_DEADLINE_SHARE
	cap = harness_deadline_cap
	calls = 0
	if(!run_deadlines(pass_t))
		pass_done = FALSE

/// 2. Borrow pass for rings near their staleness bound.
/datum/time_scheduler/proc/pass_borrow(tick_limit)
	limit = tick_limit
	for(var/lane in 1 to OM_LANE_COUNT)
		cap = harness_caps ? harness_caps[lane] : 0
		calls = 0
		for(var/datum/cadence_ring/R as anything in lane_rings[lane])
			try
				if(ring_urgent(R, pass_t))
					run_ring(R, pass_t)
			catch(var/exception/borrow_e)
				report_caught(borrow_e, "lane [lane] borrow pass ([R.behaviour()?.name]): [borrow_e] ([borrow_e.file]:[borrow_e.line])")

/// 3. Lanes with guaranteed shares.
/datum/time_scheduler/proc/pass_lanes(tick_limit)
	for(var/lane in 1 to OM_LANE_COUNT)
		pass_lane(lane, tick_limit)

/// One lane's share of the pass.
/datum/time_scheduler/proc/pass_lane(lane, tick_limit)
	// L3 lanes are shed under an overrun streak (kernel/latency.dm); the borrow pass above still
	// serves any ring near its staleness bound, and the floor admits one pass a second.
	if(!kernel_admit_lane(lane))
		return
	limit = min(TICK_USAGE + pass_avail * lane_share[lane], tick_limit)
	cap = harness_caps ? harness_caps[lane] : 0
	calls = 0
	if(!run_lane_guarded(lane, pass_t))
		pass_done = FALSE

/// 4. Leftover budget.
/datum/time_scheduler/proc/pass_leftovers(tick_limit)
	if(!pass_done && TICK_USAGE < tick_limit && !harness_caps)
		pass_done = TRUE
		limit = tick_limit
		cap = 0
		if(!run_deadlines(pass_t))
			pass_done = FALSE
		var/datum/kernel_latency/latency = kernel_latency()
		for(var/lane in 1 to OM_LANE_COUNT)
			if(latency.shedding && latency.sheds_lane(lane))
				continue
			if(!run_lane_guarded(lane, pass_t))
				pass_done = FALSE

/// Closes the pass. Returns TRUE if all due work finished.
/datum/time_scheduler/proc/pass_end()
	last_run_ms = TICK_USAGE_TO_MS(pass_start)
	return pass_done

/datum/time_scheduler/proc/out_of_budget()
	if(TICK_USAGE > limit)
		return TRUE
	if(cap && ++calls >= cap)
		return TRUE
	return FALSE

/// run_lane() behind a lane-level guard. Hooks are already isolated per behaviour
/// (run_slot, call_hook, services, world wakes, derived values); this catches what
/// escapes them (scheduler bookkeeping, a ring's behaviour lookup), so one lane's
/// runtime is logged and that lane resumes next pass while the other lanes still run.
/datum/time_scheduler/proc/run_lane_guarded(lane, t)
	try
		return run_lane(lane, t)
	catch(var/exception/e)
		lane_faults++
		report_caught(e, "lane [lane] aborted: [e] ([e.file]:[e.line])")
		return FALSE

/datum/time_scheduler/proc/run_lane(lane, t)
	. = TRUE
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if(harness_lane_fault && harness_lane_fault[lane])
		CRASH("deliberate lane fault (lane [lane])")
#endif
	// Eager derived values are inputs to wakes in every lane: a behaviour in
	// an earlier lane observing a derived channel must see the change this
	// pass, not the next. The queue is empty (one length check) almost always.
	if(length(derived_queue))
		var/derived_start = TICK_USAGE
		var/derived_done = run_derived_queue()
		meter.charge(KM_SYS_OM_CORE, TICK_USAGE_TO_MS(derived_start))
		if(!derived_done)
			return FALSE
	if(lane == LANE_DERIVED)
		if(length(service_queue))
			var/services_start = TICK_USAGE
			var/services_done = run_services()
			meter.charge(KM_SYS_OM_CORE, TICK_USAGE_TO_MS(services_start))
			if(!services_done)
				return FALSE
	if(length(world_q?[lane]))
		var/native_start = TICK_USAGE
		var/native_done = run_world_wakes(lane)
		meter.charge(KM_SYS_OM_NATIVE, TICK_USAGE_TO_MS(native_start))
		if(!native_done)
			return FALSE
	// The appearance and refresh queues are the world's (globals), not this scheduler's: only the live scheduler drains them. A test
	// harness (manual time, a per-lane call cap) draining them spent its whole presentation cap on the live world's churn and starved its own
	// presentation rings (om/regression_lanes_do_not_starve).
	if(lane == LANE_PRESENTATION && isnull(manual_time))
		// Declared appearances whose watched fields state_changed (code/datums/sys/appearance.dm).
		var/appearance_start = TICK_USAGE
		var/appearance_done = drain_presentation()
		meter.charge(KM_SYS_OM_APPEARANCE, TICK_USAGE_TO_MS(appearance_start))
		if(!appearance_done)
			return FALSE
	var/world_start = TICK_USAGE
	var/world_done = run_world_wakes(lane)
	meter.charge(KM_SYS_OM_NATIVE, TICK_USAGE_TO_MS(world_start))
	if(!world_done)
		return FALSE
	if(!run_wakes(lane))
		return FALSE
	for(var/datum/cadence_ring/R as anything in lane_rings[lane])
		if(!run_ring(R, t))
			return FALSE

/datum/time_scheduler/proc/ring_urgent(datum/cadence_ring/R, t)
	if(R.dormant || R.next_abs > round(t / R.slot_ds))
		return FALSE
	var/s = (R.next_abs % R.size) + 1
	if(!length(R.slots[s]))
		return FALSE
	return (t - R.last_run[s]) >= R.behaviour().compiled_max_interval * borrow_fraction

/// Processes every due slot of `R` in order. Never skips a slot: a slot not
/// reached this run is processed next run with its real elapsed dt.
/datum/time_scheduler/proc/run_ring(datum/cadence_ring/R, t)
	var/now_abs = round(t / R.slot_ds)
	var/datum/scheduled_behaviour/B = R.behaviour()
	if(B.runlevels)
		if(!(runlevel & B.runlevels))
			// Dormant: nothing runs and nothing accumulates, so resuming is no catch-up.
			R.dormant = TRUE
			R.cur_slot = 0
			R.next_abs = now_abs + 1
			return TRUE
		if(R.dormant)
			R.dormant = FALSE
			for(var/s in 1 to R.size)
				R.last_run[s] = t
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
			var/late = t - R.next_abs * R.slot_ds
			if(late > S[OM_STAT_LATE_MAX])
				S[OM_STAT_LATE_MAX] = late
			if(late > 0)
				meter.note_late(B.system_idx, late)
			if(dt_ds > B.compiled_max_interval)
				S[OM_STAT_BREACHES]++
		if(!run_slot(R, L))
			stat_inc(B.id, OM_STAT_DEFERRALS)
			return FALSE
		R.cur_slot = 0
		if(R.tombstones)
			R.compact(L)
		R.next_abs++
	return TRUE

/// Runs one slot's entities from R.cur_i. FALSE when the budget ran out.
/// The index is a local: an entity leaving the slot mid-run leaves a null
/// tombstone (ring.remove()), so positions never shift under the loop, and
/// the per-entity cost is one list read, one proc call and one budget check.
/// An entity whose step alone takes over OM_SLOW_STEP_USAGE is noted (note_slow_step()).
///
/// Three loops: plain cadence (tick), fixed-step (the accumulator at the
/// behaviour's step_idx, on_step called directly; hooks go through call_hook
/// only when the behaviour has a fixed step), and everything else (tick_slow()).
/datum/time_scheduler/proc/run_slot(datum/cadence_ring/R, list/L)
	var/datum/scheduled_behaviour/B = R.behaviour()
	var/dt = R.cur_dt
	var/mode = OM_SLOT_SLOW
	if(!(B.clock_idx || B.max_dt))
		if(B.step_interval)
			mode = OM_SLOT_STEP
		else
			mode = OM_SLOT_FAST
	// Pipelines are called straight into their runner (one dispatch per entity).
	var/datum/work_pipeline/pipe = istype(B, /datum/work_pipeline) ? B : null
	var/lim = limit
	var/cp = cap
	var/n_calls = calls
	var/ran = 0
	var/t0 = TICK_USAGE
	var/prev = t0 // the budget check's own reading, reused to spot one entity's step taking far too long
	var/out = FALSE
	var/i = R.cur_i
	while(TRUE)
		try
			switch(mode)
				if(OM_SLOT_FAST)
					while(i <= length(L))
						var/datum/E = L[i++]
						if(!E)
							continue
#ifdef OM_PROFILE_CALLS
						var/c0 = TICK_USAGE
#endif
						if(pipe)
							pipe.run_frame(E, dt)
						else
							B.tick(E, dt)
#ifdef OM_PROFILE_CALLS
						var/list/PS = stat_for(B.id)
						PS[OM_STAT_CALL_MAX] = max(PS[OM_STAT_CALL_MAX], TICK_USAGE_TO_MS(c0))
#endif
						ran++
						var/now = TICK_USAGE
						if(type_costs)
							note_type_cost(B, E, now - prev)
						if(now - prev > OM_SLOW_STEP_USAGE)
							note_slow_step(B, E, now - prev)
						prev = now
						if(now > lim || (cp && ++n_calls >= cp))
							out = TRUE
							break
				if(OM_SLOT_STEP)
					var/si = B.step_idx
					var/step = B.step_interval
					var/catchup = B.max_catchup
					while(i <= length(L))
						var/datum/E = L[i++]
						if(!E)
							continue
						var/datum/scheduler_record/rec = E.om_rec
						if(!rec)
							continue
						var/list/A = rec.steps
						if(length(A) < si)
							if(!A)
								A = list()
								rec.steps = A
							A.len = si
						var/acc = A[si] + dt
						var/n = round(acc / step)
						if(n > catchup)
							stat_inc(B.id, OM_STAT_BREACHES)
							n = catchup
							acc = n * step
						A[si] = acc - n * step
						while(n-- > 0)
							if(pipe)
								pipe.run_frame(E, step)
							else
								B.on_step(E)
							if(rec.torn_down)
								break
						ran++
						var/now = TICK_USAGE
						if(type_costs)
							note_type_cost(B, E, now - prev)
						if(now - prev > OM_SLOW_STEP_USAGE)
							note_slow_step(B, E, now - prev)
						prev = now
						if(now > lim || (cp && ++n_calls >= cp))
							out = TRUE
							break
				else
					while(i <= length(L))
						var/datum/E = L[i++]
						if(!E)
							continue
						tick_slow(B, E, dt)
						ran++
						var/now = TICK_USAGE
						if(type_costs)
							note_type_cost(B, E, now - prev)
						if(now - prev > OM_SLOW_STEP_USAGE)
							note_slow_step(B, E, now - prev)
						prev = now
						if(now > lim || (cp && ++n_calls >= cp))
							out = TRUE
							break
			break
		catch(var/exception/e)
			// i is already past the entity that raised: the loop resumes at the next.
			// i is past the entity that raised; name it, so a runtime says which thing failed.
			var/datum/failed = (i > 1 && i - 1 <= length(L)) ? L[i - 1] : null
			report_caught(e, "[B.name] tick ([failed?.type]): [e] ([e.file]:[e.line])")
			stat_inc(B.id, OM_STAT_ERRORS)
	R.cur_i = i
	calls = n_calls
	var/list/S = stat_for(B.id)
	S[OM_STAT_RUNS] += ran
	var/slot_usage = TICK_USAGE - t0
	var/spent = TICK_DELTA_TO_MS(slot_usage)
	S[OM_STAT_MS] += spent
	meter.charge(B.system_idx, spent)
	// A pass that ran far over without any one entity being slow: name the pass and how many it ran.
	if(slot_usage > OM_SLOW_STEP_USAGE * 4 && (!slow_step || slow_step["world_time"] != world.time))
		note_slow_step(B, src, slot_usage, "pass of [ran] entities")
	return !(out && i <= length(L))

/// Clocked, substepped, or holding behaviours (fixed-step ones only when clocked).
/datum/time_scheduler/proc/tick_slow(datum/scheduled_behaviour/B, datum/E, dt)
	var/datum/scheduler_record/rec = E.om_rec
	if(!rec)
		return
	if(B.clock_idx)
		dt *= clock_rate(rec, B.clock_idx)
	if(B.step_interval)
		var/si = B.step_idx
		var/list/A = rec.steps
		if(length(A) < si)
			if(!A)
				A = list()
				rec.steps = A
			A.len = si
		var/acc = A[si] + dt
		var/n = round(acc / B.step_interval)
		if(n > B.max_catchup)
			stat_inc(B.id, OM_STAT_BREACHES)
			n = B.max_catchup
			acc = n * B.step_interval
		A[si] = acc - n * B.step_interval
		for(var/i in 1 to n)
			call_hook(rec, B, OM_HOOK_STEP)
			if(rec.torn_down)
				return
		return
	if(B.max_dt && dt > B.max_dt)
		var/n = min(CEILING(dt / B.max_dt, 1), OM_MAX_SUBSTEPS)
		var/sub = dt / n
		for(var/i in 1 to n)
			call_hook(rec, B, OM_HOOK_TICK, sub)
		return
	call_hook(rec, B, OM_HOOK_TICK, dt)

/// Every hook except the fast cadence path goes through here: runtimes are
/// caught (no flag or depth can stick) and return values are ignored.
/datum/time_scheduler/proc/call_hook(datum/scheduler_record/rec, datum/scheduled_behaviour/B, kind, arg)
	var/datum/E = rec.owner
	if(!E)
		return
	var/failed = FALSE
	try
		switch(kind)
			if(OM_HOOK_TICK)
				B.tick(E, arg)
			if(OM_HOOK_WAKE)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
				if(GLOB.om_traced[E])
					GLOB.om_traced[E]++
					GLOB.om_traced_bits[E] |= arg
#endif
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
			if(OM_HOOK_KEYED)
				B.on_keyed_deadline(E, arg)
			if(OM_HOOK_DESTROY)
				B.on_entity_destroy(E)
	catch(var/exception/e)
		failed = TRUE
		report_caught(e, "[B.name] hook [kind]: [e] ([e.file]:[e.line])")
		stat_inc(B.id, OM_STAT_ERRORS)

/// Runs `B`'s tick on `E` now, outside its ring (Life's run-this-system-now
/// path). dt is the caller's; the ring's own schedule is unchanged.
/proc/scheduler_tick_now(datum/E, B, dt)
	var/datum/scheduler_record/rec = E?.om_rec
	if(!rec)
		return FALSE
	var/datum/scheduled_behaviour/def = definition_registry().behaviour(B)
	if(!rec.att.Find(def))
		return FALSE
	rec.sched.call_hook(rec, def, OM_HOOK_TICK, dt)
	return TRUE

// ---------------------------------------------------------------- wakes

/datum/time_scheduler/proc/enqueue(datum/scheduler_record/rec, lane)
	var/bit = 1 << lane
	if(rec.queued & bit)
		return
	rec.queued |= bit
	var/list/Q = wake_q[lane]
	Q += rec

/// One on_wake per behaviour per entity per run, with the union of bits.
/// Changes raised while draining go to the next run, except to behaviours
/// later in the same entity's run order, which see them this run.
/// The queue is double-buffered: the drained list is emptied and becomes the
/// spare, so a pass allocates nothing.
/datum/time_scheduler/proc/run_wakes(lane)
	var/list/Q = wake_q[lane]
	if(!length(Q))
		return TRUE
	var/list/spare = wake_spare[lane]
	wake_q[lane] = spare
	wake_spare[lane] = Q
	var/bit = 1 << lane
	var/idx = 0
	while(idx < length(Q))
		idx++
		var/datum/scheduler_record/rec = Q[idx]
		rec.queued &= ~bit
		if(rec.torn_down)
			continue
		var/i = 1
		while(i <= length(rec.att))
			var/datum/scheduled_behaviour/B = rec.att[i]
			var/bits = rec.att_pend[i]
			if(B.lane != lane || !bits)
				i++
				continue
			rec.att_pend[i] = 0
			// Conservative: another behaviour pending the same bits just takes the full
			// dispatch path on its next change (entity_dispatch_change()).
			rec.pend_union &= ~bits
			// The gate is behaviour code too: a runtime in wake_if or the throttle drops
			// this one wake (logged, counted) instead of unwinding the lane's drain.
			var/gated = FALSE
			try
				if(B.compiled_wake_if && !isnull(B.compiled_wake_if.why_not(rec.owner, null)))
					gated = TRUE
				else if(B.min_interval && scheduler_throttled(rec, B, i, bits))
					gated = TRUE
			catch(var/exception/gate_e)
				gated = TRUE
				report_caught(gate_e, "[B.name] wake gate ([rec.owner?.type]): [gate_e] ([gate_e.file]:[gate_e.line])")
				stat_inc(B.id, OM_STAT_ERRORS)
			if(gated)
				i++
				continue
			stat_inc(B.id, OM_STAT_WAKES)
			var/ver = rec.att_ver
			var/wake_start = TICK_USAGE
			call_hook(rec, B, OM_HOOK_WAKE, bits)
			var/wake_usage = TICK_USAGE - wake_start
			meter.charge(B.system_idx, TICK_DELTA_TO_MS(wake_usage))
			if(type_costs)
				note_type_cost(B, rec.owner, wake_usage)
			if(wake_usage > OM_SLOW_STEP_USAGE)
				note_slow_step(B, rec.owner, wake_usage, "wake")
			if(rec.torn_down)
				break
			if(rec.att_ver != ver)
				// The hook attached or detached behaviours: find B again.
				var/at = rec.att.Find(B)
				i = (at ? at : i - 1) + 1
			else
				i++
		if(out_of_budget() && idx < length(Q))
			// Unprocessed recs keep their queued bit, so none of them was queued again
			// meanwhile: they go first, then whatever this pass queued.
			Q.Cut(1, idx + 1)
			var/list/fresh = wake_q[lane]
			Q += fresh
			fresh.Cut()
			wake_q[lane] = Q
			wake_spare[lane] = fresh
			return FALSE
	Q.Cut()
	return TRUE

/datum/time_scheduler/proc/run_services()
	if(!length(service_queue))
		return TRUE
	// Double-buffered: services queued while this pass runs go to the spare list.
	var/list/Q = service_queue
	service_queue = service_spare
	service_spare = Q
	for(var/idx in 1 to length(Q))
		var/datum/scheduler_record/rec = Q[idx]
		var/bits = rec.service_pend
		rec.service_pend = 0
		if(rec.torn_down || !bits)
			continue
		var/datum/E = rec.owner
		var/list/services = rec.table.services
		var/list/masks = rec.table.service_masks
		for(var/s in 1 to length(services))
			var/mine = masks[s] & bits
			if(!mine)
				continue
			var/datum/service_definition/S = services[s]
			try
				S.on_changes(E, mine)
			catch(var/exception/e)
				report_caught(e, "[S.type] on_changes: [e]")
		if(out_of_budget() && idx < length(Q))
			// Unprocessed recs go first next pass, then whatever this pass queued.
			Q.Cut(1, idx + 1)
			Q += service_queue
			service_queue.Cut()
			service_spare = service_queue
			service_queue = Q
			return FALSE
	Q.Cut()
	return TRUE

// ---------------------------------------------------------------- deadlines

/datum/time_scheduler/proc/insert_deadline(datum/scheduler_record/rec, bid, gen, due)
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

/datum/time_scheduler/proc/run_deadlines(t)
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
		report_caught(e, "deadline wheel: [e]")
	dl_processing = FALSE

/datum/time_scheduler/proc/run_bucket(b, t)
	var/list/L = buckets[b]
	if(!length(L))
		return TRUE
	// Entries a firing deadline inserts into this bucket land in the spare list; the bucket
	// itself is compacted in place (kept entries slide down over fired ones). No allocation.
	var/list/added = bucket_spare
	buckets[b] = added
	var/datum/definition_registry/reg = definition_registry()
	var/n = length(L)
	var/i = 1
	var/w = 1
	var/ok = TRUE
	while(i <= n)
		var/due = L[i + 3]
		if(!ok || due > t)
			if(w != i)
				L[w] = L[i]
				L[w + 1] = L[i + 1]
				L[w + 2] = L[i + 2]
				L[w + 3] = due
			w += 4
			i += 4
			continue
		var/datum/scheduler_record/rec = L[i]
		var/bid = L[i + 1]
		var/gen_i = L[i + 2]
		i += 4
		fire_deadline(rec, bid, gen_i, t, reg)
		if(i <= n && out_of_budget())
			ok = FALSE
	L.len = w - 1
	if(length(added))
		L += added
		added.Cut()
	bucket_spare = added
	buckets[b] = L
	return ok

/datum/time_scheduler/proc/fire_deadline(datum/scheduler_record/rec, key, gen_i, t, datum/definition_registry/reg)
	if(rec.torn_down || !rec.deadlines)
		return
	var/list/D = rec.deadlines
	var/k = 0
	for(var/j in 1 to length(D) step 3)
		if(D[j] == key)
			k = j
			break
	if(!k || D[k + 1] != gen_i)
		return
	var/bid = key % OM_DL_SUB
	var/sub = (key - bid) / OM_DL_SUB
	var/datum/scheduled_behaviour/B = reg.behaviours[bid]
	var/local_target = D[k + 2]
	if(!isnull(local_target))
		var/local_now = clock_local(rec, B.clock_idx)
		if(local_now < local_target - 0.001)
			var/rate = clock_rate(rec, B.clock_idx)
			if(rate > 0)
				insert_deadline(rec, key, gen_i, t + (local_target - local_now) / rate)
			return
	D.Cut(k, k + 3)
	if(!length(D))
		rec.deadlines = null
	stat_inc(bid, OM_STAT_DEADLINES)
	var/deadline_start = TICK_USAGE
	switch(sub)
		if(0)
			call_hook(rec, B, OM_HOOK_DEADLINE)
		if(OM_DL_THROTTLE)
			scheduler_throttle_release(rec, B)
		else
			call_hook(rec, B, OM_HOOK_KEYED, sub)
	var/deadline_usage = TICK_USAGE - deadline_start
	meter.charge(B.system_idx, TICK_DELTA_TO_MS(deadline_usage))
	if(type_costs)
		note_type_cost(B, rec.owner, deadline_usage)
	if(deadline_usage > OM_SLOW_STEP_USAGE)
		note_slow_step(B, rec.owner, deadline_usage, "deadline")

// ---------------------------------------------------------------- min_interval throttle

/// A min_interval behaviour's wake arriving too soon: its bits stay pending (later changes
/// coalesce into them) and one deadline delivers them when the interval ends. Returns TRUE
/// when the wake was deferred.
/proc/scheduler_throttled(datum/scheduler_record/rec, datum/scheduled_behaviour/B, i, bits)
	var/t = rec.sched.now()
	var/list/T = rec.throttle
	var/k = 0
	for(var/j in 1 to length(T) step 2)
		if(T[j] == B.id)
			k = j
			break
	if(k)
		var/wait = T[k + 1] + B.min_interval - t
		if(wait > 0)
			// Held behind the throttle deadline, not queued: kept out of pend_union, whose repeat
			// short cut (entity_dispatch_change()) assumes every interested behaviour already pends
			// the bits. Counting these there made a later change skip behaviours that had
			// already taken their wake (a stage raising mid-frame never woke the later stage).
			rec.att_pend[i] |= bits
			if(!deadline_deadline_pending(rec.owner, B, OM_DL_THROTTLE))
				deadline_deadline(rec.owner, wait, B, OM_DL_THROTTLE)
			return TRUE
		T[k + 1] = t
	else
		LAZYADD(rec.throttle, list(B.id, t))
	return FALSE

/// The throttle interval ended: queue the coalesced wake.
/proc/scheduler_throttle_release(datum/scheduler_record/rec, datum/scheduled_behaviour/B)
	var/i = rec.att.Find(B)
	if(i && rec.att_pend[i] && (rec.att_state[i] & OM_ATT_STARTED))
		rec.sched.enqueue(rec, B.lane)

// ---------------------------------------------------------------- harness

/// Test harness: advance injected time slot by slot, running each slot.
/datum/time_scheduler/proc/advance(seconds)
	if(isnull(manual_time))
		CRASH("om: advance() on the live scheduler")
	var/target = manual_time + seconds * 10
	while(manual_time < target)
		manual_time = min(manual_time + OM_SLOT_DS, target)
		run_pass(1e9)

/// Test harness: jump time without running (simulates skipped ticks).
/datum/time_scheduler/proc/jump(seconds)
	manual_time += seconds * 10

// ---------------------------------------------------------------- diagnostics

/// Admin-readable snapshot: per behaviour type counters, ring sizes, queue lengths.
/proc/scheduler_diagnostics(datum/time_scheduler/sched)
	sched = sched || GLOB.om_live_sched || time_scheduler()
	var/datum/definition_registry/reg = definition_registry()
	. = list()
	var/list/types = list()
	for(var/bid in 1 to length(sched.stats))
		var/list/S = sched.stats[bid]
		if(!S)
			continue
		var/datum/scheduled_behaviour/B = bid <= length(reg.behaviours) ? reg.behaviours[bid] : null
		var/population = 0
		if(bid <= length(sched.rings))
			for(var/datum/cadence_ring/R as anything in sched.rings[bid])
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
	.["io"] = io_diagnostics()
	.["pools"] = pool_diagnostics()
	.["kernel"] = km_diagnostics(sched)

/// The behaviour this ring runs.
/datum/cadence_ring/proc/behaviour() as /datum/scheduled_behaviour
	return definition_registry().behaviours[behaviour_id]

/// One entity's step (or wake, or deadline: `kind`) took `usage` percent of a tick (over OM_SLOW_STEP_USAGE): kept as the tick's slowest step,
/// which the MC's overrun record reports (Kernel.record_performance_tick()). Rare, so it may allocate.
/// Adds `usage` (tick usage) to `B`'s cost for entities of E's type, while a profile capture collects type_costs.
/datum/time_scheduler/proc/note_type_cost(datum/scheduled_behaviour/B, datum/E, usage)
	type_costs["[B.name || B.type]|[E?.type]"] += usage

/datum/time_scheduler/proc/note_slow_step(datum/scheduled_behaviour/B, datum/E, usage, kind = "step")
	if(slow_step && slow_step["world_time"] == world.time && slow_step["usage"] >= usage)
		return
	slow_step = list("kind" = kind, "behaviour" = "[B.name || B.type]", "entity" = (E ? "[E.type]" : "none"), "name" = "[E]", "usage" = usage, "ms" = round(TICK_DELTA_TO_MS(usage), 0.1), "world_time" = EXPIRY_AT(null, CLOCK_WORLD, 0))

GLOBAL_DATUM(time_scheduler_factory, /datum/time_scheduler_factory)

/proc/time_scheduler_factory()
	RETURN_TYPE(/datum/time_scheduler_factory)
	if(!GLOB.time_scheduler_factory)
		GLOB.time_scheduler_factory = new /datum/time_scheduler_factory
	return GLOB.time_scheduler_factory

/datum/time_scheduler_factory/proc/make()
	return new /datum/time_scheduler
