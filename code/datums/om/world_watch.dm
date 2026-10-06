// Rust world subscriptions on the OM scheduler (doc/rewrite/object_model_core.md §4.8).
//
// The Rust world (verdigris/ffi/src/sched.rs) holds the rate models and the watches on Rust-owned state (gas, heat, probe
// cells). It holds no DM timers and no DM-owned keys: a DM timer is the kernel's after(), and a DM-owned fact is an OM change
// channel (or a rule key, code/datums/rules/world_adapter.dm).
// The kernel steps it once per tick (phase N: native_frame() -> the native system's frame);
// each wake it returns names a subscriber, which is a /datum/native_watch/world:
// one subscription, its own SSvg handle. The wake is queued on the watch's
// OM lane and, when that lane runs, the owner's declared proc is called:
//
//   call(owner, callback)(watch, reason, source, source_kind)
//
// `reason` is WORLD_REASON_* class bits OR-ed with channel bits (a change
// watch) or the key's mask (a key); wakes of one watch in one tick are merged
// by Rust. `source` is the first reason's source: the cell, the key id (with
// `source_kind` its kind), or the rate model. Read the current state; never
// count wakes. Cancel with qdel(watch) (or watch.cancel()). A watch holds its
// owner weakly, so an owner that forgets to cancel costs one dropped wake (the
// watch is cancelled then); owners that keep watches (rule bindings) delete
// them in Destroy().
//
//   om_world_on_change(owner, handle, mask, proc, lane) a channel change on a Rust entity
//   om_world_when(owner, condition, proc, lane)       a COND_* condition
//   om_world_on_rate(owner, model, cmp, level, proc, lane) a rate model crossing a level
//
// Periodic work is not a world watch: it is a periodic lane (om_task_periodic(),
// §4.10) or a clock (§4.6).

/// Ticks of world budget one late step may take (skipped MC ticks carry over up to this).
#define OM_WORLD_MAX_CATCHUP 8
/// World wakes a non-urgent lane delivers per pass even when its budget share is spent.
#define OM_WORLD_MIN_PER_PASS 16

/// OM lane -> Rust wake lane (0 urgent, drained in full; 1 normal; 2 background).
/proc/om_world_rust_lane(lane)
	switch(lane)
		if(LANE_URGENT)
			return 0
		if(LANE_PRESENTATION, LANE_BACKGROUND)
			return 2
	return 1

/// The wheel tick for world.time `time`: the first tick at or after it.
/proc/om_world_tick_of(time)
	return CEILING(time / world.tick_lag, 1)

/datum/native_watch/world
	delivery_source = NATIVE_SRC_WORLD_WATCH
	/// OM lane the owner's proc runs on.
	var/lane = LANE_SIMULATION
	/// The Rust subscription token (a watch or rate watch).
	var/token

/datum/native_watch/world/New(datum/owner, callback, lane = LANE_SIMULATION)
	..(owner, callback)
	src.lane = lane

/datum/native_watch/world/unregister()
	if(handle)
		vg_world_clear(handle)
	token = null

/// A native record for this watch: queue it on the owner's lane (the world_q the scheduler drains).
/datum/native_watch/world/crossed(band, list/detail)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(!sched)
		return FALSE
	sched.world_enqueue(src, detail[2], detail[3], detail[4])
	return TRUE

/// TRUE while the Rust subscription is live.
/datum/native_watch/world/proc/is_live()
	return handle && vg_world_subscriptions(handle) > 0

/proc/om_world_new_watch(datum/owner, callback, lane)
	RETURN_TYPE(/datum/native_watch/world)
	if(!owner || !callback)
		CRASH("om_world watch needs an owner and a proc")
	return new /datum/native_watch/world(owner, callback, isnull(lane) ? LANE_SIMULATION : lane)

/// `proc` runs when any channel in `mask` of the Rust entity `handle` (WORLD_HANDLE) changes.
/proc/om_world_on_change(datum/owner, list/handle, mask, callback, lane)
	var/datum/native_watch/world/W = om_world_new_watch(owner, callback, lane)
	W.token = vg_world_watch_changed(handle[1], W.handle, om_world_rust_lane(W.lane), handle[2], mask)
	return W

/// `proc` runs when a COND_* condition becomes true. Rust checks the condition
/// (channel, unit, levels) and raises a runtime if it is invalid.
/proc/om_world_when(datum/owner, list/condition, callback, lane)
	var/datum/native_watch/world/W = om_world_new_watch(owner, callback, lane)
	var/rust_lane = om_world_rust_lane(W.lane)
	try
		switch(condition[1])
			if(WORLD_COND_THRESHOLD)
				var/list/handle = condition[2]
				W.token = vg_world_watch_threshold(handle[1], W.handle, rust_lane, handle[2], condition[3], condition[4], condition[5], condition[6], condition[7])
			if(WORLD_COND_BAND)
				var/list/handle = condition[2]
				W.token = vg_world_watch_band(handle[1], W.handle, rust_lane, handle[2], condition[3], condition[4], condition[5])
			if(WORLD_COND_DIFFERENCE)
				var/list/handle_a = condition[2]
				var/list/handle_b = condition[3]
				if(handle_a[1] != handle_b[1])
					CRASH("om_world_when: a difference across watch codes")
				W.token = vg_world_watch_difference(handle_a[1], W.handle, rust_lane, handle_a[2], handle_b[2], condition[4], condition[5], condition[6], condition[7], condition[8])
			else
				CRASH("om_world_when: unknown condition [condition[1]]")
	catch(var/exception/e)
		W.cancel()
		throw e
	return W

/// Threshold watch on a gas mixture's pressure or temperature: `callback` runs on `owner`
/// at the exact crossing of `level` (`cmp` WORLD_CMP_ABOVE or WORLD_CMP_BELOW) and again only
/// after the value has left the band `hysteresis` wide (-1: the channel's own), so a sensor
/// needs no polling. `channel` is a CH_GAS_* id. Cancel with qdel(watch). For a mixture with no
/// arena handle (a deleted one) the watch is not created and null is returned.
/proc/om_watch_gas(datum/owner, datum/gas_mixture/mixture, channel, cmp, level, callback, hysteresis = -1, lane)
	if(!mixture)
		return null
	var/list/condition = list(WORLD_COND_THRESHOLD, WORLD_GAS_HANDLE(mixture), channel, cmp, level, hysteresis, FALSE)
	return om_world_when(owner, condition, callback, lane)

/// `proc` runs at the exact tick rate model `model` enters `cmp level` (at once if it holds).
/proc/om_world_on_rate(datum/owner, model, cmp, level, callback, lane)
	var/datum/native_watch/world/W = om_world_new_watch(owner, callback, lane)
	W.token = vg_world_rate_watch(model, W.handle, om_world_rust_lane(W.lane), cmp, level)
	return W

// ---------------------------------------------------------------- rate models
// Quantities changing at a known rate, held in Rust (rust_core.md §7). Rates are per second.

/proc/om_world_per_tick(per_second)
	return per_second * world.tick_lag / 10

/// A quantity changing at `per_second` from `v0`, clamped to [lo, hi] (null: unbounded).
/proc/om_rate_linear(v0, per_second, lo, hi)
	return vg_world_rate_linear(v0, om_world_per_tick(per_second), lo, hi)

/// A store with named inflow/outflow terms (om_rate_set_term()).
/proc/om_rate_sum(v0, lo, hi)
	return vg_world_rate_sum(v0, lo, hi)

/proc/om_rate_read(model)
	return vg_world_rate_read(model)

/proc/om_rate_set_rate(model, per_second)
	return vg_world_rate_set_rate(model, om_world_per_tick(per_second))

/proc/om_rate_set_term(model, term, per_second)
	return vg_world_rate_set_term(model, term, om_world_per_tick(per_second))

/proc/om_rate_remove(model)
	return vg_world_rate_remove(model)

// ---------------------------------------------------------------- the step, on the scheduler

/datum/om/scheduler
	/// Normal plus background world wakes taken per tick (urgent wakes are never limited).
	var/world_budget = 2000
	/// The wheel tick of the last world step, and of the one before it (tests check precision).
	var/world_step_tick = -1
	var/world_previous_step_tick = -1
	/// lane -> flat list of (watch, reason, source, source_kind) waiting for that lane.
	var/list/world_q
	/// lane -> world wakes delivered this pass (run_pass() zeroes it). The OM_WORLD_MIN_PER_PASS
	/// floor counts against this, so run_pass()'s leftover round doesn't grant a second floor.
	var/list/world_pass_delivered
	/// Counters: wakes delivered, dropped (watch or owner gone), last step's wakes and ms.
	var/world_wakes = 0
	var/world_dropped = 0
	var/world_last_wakes = 0
	var/world_last_ms = 0
	/// Wakes by owner type, bounded at OM_MAX_STAT_TYPES types (the rest under "other").
	var/list/world_wakes_by_type = list() // ALLOW(instance_list): d: one live scheduler (plus test ones); counted on every world wake
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	/// Tests: owner -> wakes delivered + 1 (om_world_trace()).
	var/list/world_traced
#endif

/// Opens the world side of the native frame for wheel tick `tick`: the lane queues, the step ticks tests read
/// and the wake count. FALSE when this tick already had its frame (exactly one frame per tick) or the scheduler
/// runs on injected time.
/datum/om/scheduler/proc/world_frame_begin(tick)
	if(!isnull(manual_time) || tick <= world_step_tick)
		return FALSE
	world_previous_step_tick = world_step_tick
	world_step_tick = tick
	if(!world_q)
		world_q = new /list(OM_LANE_COUNT)
		for(var/lane in 1 to OM_LANE_COUNT)
			world_q[lane] = list()
	world_last_wakes = 0
	return TRUE

/// Queues a world watch's wake on its lane (the native system's CHANGED/CROSSED delivery).
/datum/om/scheduler/proc/world_enqueue(datum/native_watch/world/W, reason, source, source_kind)
	if(!world_q)
		world_q = new /list(OM_LANE_COUNT)
		for(var/lane in 1 to OM_LANE_COUNT)
			world_q[lane] = list()
	world_last_wakes++
	var/list/Q = world_q[W.lane]
	Q.Add(W, reason, source, source_kind)

/// A record named a watch that is gone: counted like any dropped wake.
/proc/om_world_dropped()
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched)
		sched.world_dropped++

/// Runs `lane`'s queued world wakes. FALSE when the budget ran out (resumed next run).
/datum/om/scheduler/proc/run_world_wakes(lane)
	var/list/Q = world_q?[lane]
	if(!length(Q))
		return TRUE
	var/i = 1
	if(!world_pass_delivered)
		world_pass_delivered = new /list(OM_LANE_COUNT)
	var/delivered = world_pass_delivered[lane] || 0
	while(i <= length(Q))
		var/datum/native_watch/world/W = Q[i]
		var/list/arguments = list(Q[i + 1], Q[i + 2], Q[i + 3])
		i += 4
		if(QDELETED(W) || !W.handle)
			world_dropped++
			continue
		var/datum/owner = om_resolve(W.owner_ref)
		if(!owner)
			world_dropped++
			W.cancel()
			continue
		world_wakes++
		world_count(owner.type)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
		if(world_traced && world_traced[owner])
			world_traced[owner]++
#endif
		try
			W.fire(arguments)
		catch(var/exception/e)
			report_caught(e, "world wake [owner.type] [W.callback]: [e] ([e.file]:[e.line])")
		// Urgent wakes drain in full, like Rust's urgent lane. The rest yield to the budget, but
		// only after OM_WORLD_MIN_PER_PASS wakes: a lane whose share is already spent when it
		// starts (a pass behind on other work) still moves, so its wakes can't starve. The floor
		// is per lane per pass, not per call: run_pass() calls each lane twice (its share, then
		// the leftover round).
		delivered++
		if(lane != LANE_URGENT && delivered >= OM_WORLD_MIN_PER_PASS && out_of_budget() && i <= length(Q))
			Q.Cut(1, i)
			world_pass_delivered[lane] = delivered
			return FALSE
	Q.Cut()
	world_pass_delivered[lane] = delivered
	return TRUE

/datum/om/scheduler/proc/world_count(type)
	var/key = type
	if(!world_wakes_by_type[key] && length(world_wakes_by_type) >= OM_MAX_STAT_TYPES)
		key = "other"
	world_wakes_by_type[key]++

/// Rust-side counters (vg_world_sched_stats) by name.
/proc/om_world_rust_stats()
	var/list/v = vg_world_sched_stats()
	var/static/list/names = list("timers_pending", "crossings_fired", "models", "subscriptions", "wakes_received", "wakes_merged", "wakes_delivered", "wakes_deferred", "watch_wakes", "backlog_urgent", "backlog_normal", "backlog_background", "step_us")
	. = list()
	for(var/i in 1 to min(length(v), length(names)))
		.[names[i]] = v[i]

/// World-wake counters for the profiler and the benchmarks.
/proc/om_world_diagnostics(datum/om/scheduler/sched)
	sched = sched || GLOB.om_live_sched || om_scheduler()
	var/list/by_type = list()
	for(var/type in sched.world_wakes_by_type)
		by_type["[type]"] = sched.world_wakes_by_type[type]
	var/list/queued = list()
	for(var/lane in 1 to OM_LANE_COUNT)
		queued += length(sched.world_q?[lane]) / 4
	return list(
		"total_wakes" = sched.world_wakes,
		"dropped" = sched.world_dropped,
		"last_wakes" = sched.world_last_wakes,
		"step_ms" = sched.world_last_ms,
		"queued" = queued,
		"wakes_by_type" = by_type,
		"rust" = om_world_rust_stats(),
	)

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Tests: start counting world wakes delivered to `owner`.
/proc/om_world_trace(datum/owner)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	LAZYINITLIST(sched.world_traced)
	if(!sched.world_traced[owner])
		sched.world_traced[owner] = 1

/proc/om_world_traced_wakes(datum/owner)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	return (sched.world_traced && sched.world_traced[owner]) ? sched.world_traced[owner] - 1 : 0

/proc/om_world_untrace(datum/owner)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched.world_traced)
		sched.world_traced -= owner
		if(!length(sched.world_traced))
			sched.world_traced = null
#endif
