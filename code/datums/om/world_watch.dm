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

/proc/om_world_dropped()
	return world_wake_dropped()
