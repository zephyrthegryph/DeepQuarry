// Rust world subscriptions (doc/rewrite/object_model_core.md §4.8).
//
// The Rust world (verdigris/ffi/src/sched.rs) holds the watches on Rust-owned state (gas, heat, probe cells). It holds no DM timers and no DM-owned
// keys: a DM timer is the kernel's after() (a rule's hold_for is one), and a DM-owned fact is a tracked var or a rule key (code/datums/rules/world_adapter.dm).
// The kernel steps it once per tick (phase N: native_frame() -> the native system's frame); each wake it returns names a subscriber, which is a
// /datum/native_watch/world (code/engine/time/native_wakes.dm): one subscription, its own SSvg handle. The wake is queued on the watch's lane and,
// when that lane runs, the owner's declared proc is called:
//
//   call(owner, callback)(watch, reason, source, source_kind)
//
// `reason` is WORLD_REASON_* class bits OR-ed with channel bits (a change watch) or the key's mask; wakes of one watch in one tick are merged by Rust.
// `source` is the first reason's source: the cell or the key id (with `source_kind` its kind). Read the current state; never count wakes. Cancel with
// qdel(watch) (or watch.cancel()). A watch holds its owner weakly, so an owner that forgets to cancel costs one dropped wake (the watch is cancelled
// then); owners that keep watches delete them in their teardown (an owned var, `kind = RELK_OWNED`).
//
//   world_watch_changed(owner, handle, mask, proc, lane)   a channel change on a Rust entity
//   world_watch_when(owner, condition, proc, lane)         a COND_* condition
//
// Periodic work is not a world watch: it is a periodic lane (every()) or the kernel clock.

/// Lane -> Rust wake lane (0 urgent, drained in full; 1 normal; 2 background).
/proc/world_rust_lane(lane)
	switch(lane)
		if(LANE_URGENT)
			return 0
		if(LANE_PRESENTATION, LANE_BACKGROUND)
			return 2
	return 1

/// The wheel tick for world.time `time`: the first tick at or after it.
/proc/world_tick_of(time)
	return CEILING(time / world.tick_lag, 1)

/proc/world_watch_new(datum/owner, callback, lane)
	RETURN_TYPE(/datum/native_watch/world)
	if(!owner || !callback)
		CRASH("a world watch needs an owner and a proc")
	return new /datum/native_watch/world(owner, callback, isnull(lane) ? LANE_SIMULATION : lane)

/// `callback` runs when any channel in `mask` of the Rust entity `handle` (WORLD_HANDLE) changes.
/proc/world_watch_changed(datum/owner, list/handle, mask, callback, lane)
	var/datum/native_watch/world/W = world_watch_new(owner, callback, lane)
	W.token = vg_world_watch_changed(handle[1], W.handle, world_rust_lane(W.lane), handle[2], mask)
	return W

/// `callback` runs when a COND_* condition becomes true. Rust checks the condition (channel, unit, levels) and raises a runtime if it is invalid.
/proc/world_watch_when(datum/owner, list/condition, callback, lane)
	var/datum/native_watch/world/W = world_watch_new(owner, callback, lane)
	var/rust_lane = world_rust_lane(W.lane)
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
					CRASH("world_watch_when: a difference across watch codes")
				W.token = vg_world_watch_difference(handle_a[1], W.handle, rust_lane, handle_a[2], handle_b[2], condition[4], condition[5], condition[6], condition[7], condition[8])
			else
				CRASH("world_watch_when: unknown condition [condition[1]]")
	catch(var/exception/e)
		W.cancel()
		throw e
	return W

// ---------------------------------------------------------------- the step, on the scheduler

/// Rust-side counters (vg_world_sched_stats) by name.
/proc/world_rust_stats()
	var/list/v = vg_world_sched_stats()
	var/static/list/names = list("timers_pending", "crossings_fired", "models", "subscriptions", "wakes_received", "wakes_merged", "wakes_delivered", "wakes_deferred", "watch_wakes", "backlog_urgent", "backlog_normal", "backlog_background", "step_us")
	. = list()
	for(var/i in 1 to min(length(v), length(names)))
		.[names[i]] = v[i]

/// World-wake counters for the profiler and the benchmarks: the scheduler's delivery counters and Rust's own.
/proc/world_diagnostics(datum/time_scheduler/sched)
	sched = sched || GLOB.om_live_sched || time_scheduler()
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
		"rust" = world_rust_stats(),
	)

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Tests: start counting world wakes delivered to `owner`.
/proc/world_wake_trace(datum/owner)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	LAZYINITLIST(sched.world_traced)
	if(!sched.world_traced[owner])
		sched.world_traced[owner] = 1

/proc/world_wake_traced(datum/owner)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	return (sched.world_traced && sched.world_traced[owner]) ? sched.world_traced[owner] - 1 : 0

/proc/world_wake_untrace(datum/owner)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	if(sched.world_traced)
		sched.world_traced -= owner
		if(!length(sched.world_traced))
			sched.world_traced = null
#endif
