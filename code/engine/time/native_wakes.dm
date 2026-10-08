// Native subscription delivery queues belong to the generic time scheduler.
/// Ticks of world budget one late step may take (skipped MC ticks carry over up to this).
#define OM_WORLD_MAX_CATCHUP 8
/// World wakes a non-urgent lane delivers per pass even when its budget share is spent.
#define OM_WORLD_MIN_PER_PASS 16

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
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	if(!sched)
		return FALSE
	sched.world_enqueue(src, detail[2], detail[3], detail[4])
	return TRUE

/// TRUE while the Rust subscription is live.
/datum/native_watch/world/proc/is_live()
	return handle && vg_world_subscriptions(handle) > 0

/datum/time_scheduler
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
/datum/time_scheduler/proc/world_frame_begin(tick)
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
/datum/time_scheduler/proc/world_enqueue(datum/native_watch/world/W, reason, source, source_kind)
	if(!world_q)
		world_q = new /list(OM_LANE_COUNT)
		for(var/lane in 1 to OM_LANE_COUNT)
			world_q[lane] = list()
	world_last_wakes++
	var/list/Q = world_q[W.lane]
	Q.Add(W, reason, source, source_kind)

/// A record named a watch that is gone: counted like any dropped wake.
/proc/world_wake_dropped()
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	if(sched)
		sched.world_dropped++

/// Runs `lane`'s queued world wakes. FALSE when the budget ran out (resumed next run).
/datum/time_scheduler/proc/run_world_wakes(lane)
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
		var/datum/owner = resolve_handle(W.owner_ref)
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

/datum/time_scheduler/proc/world_count(type)
	var/key = type
	if(!world_wakes_by_type[key] && length(world_wakes_by_type) >= OM_MAX_STAT_TYPES)
		key = "other"
	world_wakes_by_type[key]++
