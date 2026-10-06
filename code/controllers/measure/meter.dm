// Kernel measurement: the tick meter.
//
// Every unit of work is charged to a system (systems.dm) as it finishes: OM behaviours from inside
// SSbehaviours (slots, wakes, deadlines), each firing MC subsystem from Kernel.RunQueue(), and clicks from
// atom/Click. The meter adds the charges up for the tick in fixed lists (nothing is allocated per tick), and
// Kernel.record_performance_tick() closes the tick with end_tick(), which
//  - folds every touched system's ms into each active stats set (histogram, totals, lateness),
//  - picks the tick's top KM_TOP_N systems by ms,
//  - writes one entry of the flight recorder (a ring of the last KM_RING_LEN ticks: usage, maptick, input cost,
//    top systems),
//  - and, when the tick overran, attributes it: counts the streak, credits the top systems and writes one
//    admin-log line that names them ("air 21ms, life 18ms"), instead of "Behaviours 40ms".
//
// Stats sets: sets[1] is the live set (since boot or the profiler's reset). A benchmark window or scenario opens
// its own with open_set() and closes it with close_set(), so windows nest without clearing each other.
//
// Nothing here decides what runs; it only reads TICK_USAGE.

/// One set of accumulators: the live one, or a benchmark window.
/datum/km_stats_set
	/// System index -> /datum/system_stats, null until the system is first charged.
	var/list/systems
	var/ticks = 0
	var/overruns = 0
	var/max_streak = 0
	/// REALTIMEOFDAY (ds) and world.time when the set opened, for per-second rates. Null until the world runs:
	/// the live set is built during global init, before REALTIMEOFDAY can be read.
	var/started_real
	var/started_time = 0
	var/datum/input_stats/input
	/// The OM per-behaviour counters rolled up per system when the set opened; reports subtract it (km_rollup()).
	var/list/rollup_base

/datum/km_stats_set/New()
	systems = new /list(KM_MAX_SYSTEMS)
	input = new

/// Stamps the moment the set started recording.
/datum/km_stats_set/proc/mark_start()
	started_real = REALTIMEOFDAY
	started_time = world.time // ALLOW(sys_world_time_write): the tick meter's own wall-clock stamp for rates and log spacing, not an entity expiry

/// Seconds since the set started recording (at least 0.1, so a rate never divides by zero).
/datum/km_stats_set/proc/elapsed_seconds()
	if(isnull(started_real))
		return 0.1
	return max((REALTIMEOFDAY - started_real) * 0.1, 0.1)

/datum/km_stats_set/on_destroy(force)
	for(var/datum/system_stats/S as anything in systems)
		ended_with(S, src)
	systems = null
	QDEL_NULL(input)
	rollup_base = null
	..()

/// Clears every accumulator (the profiler's reset, and the start of a fresh window).
/datum/km_stats_set/proc/reset()
	for(var/i in 1 to KM_MAX_SYSTEMS)
		var/datum/system_stats/S = systems[i]
		if(S)
			spent(S)
			systems[i] = null
	ticks = 0
	overruns = 0
	max_streak = 0
	mark_start()
	input.reset()
	rollup_base = null

/datum/km_stats_set/proc/stats_for(idx)
	RETURN_TYPE(/datum/system_stats)
	var/datum/system_stats/S = systems[idx]
	if(!S)
		var/datum/km_systems/registry = km_systems()
		S = new(registry.key_of(idx), registry.kinds[idx])
		systems[idx] = S
	return S

/// What a player-input record holds: the wait between a click or verb being received and being handled, where in
/// the tick it ran, and how deep the verb queue got.
/datum/input_stats
	/// Wait in ms, all input and per kind.
	var/datum/km_hist/wait
	var/datum/km_hist/click_wait
	var/datum/km_hist/verb_wait
	/// TICK_USAGE (percent of a tick) at the moment input ran.
	var/datum/km_depth_hist/depth
	var/clicks = 0
	/// Verbs that were queued (waited for a later tick) vs. ran on the spot (TRY_QUEUE_VERB declined to queue).
	var/verbs_queued = 0
	var/verbs_direct = 0
	var/verbs_run = 0
	var/queue_hwm = 0

/datum/input_stats/New()
	wait = new
	click_wait = new
	verb_wait = new
	depth = new

/datum/input_stats/on_destroy(force)
	QDEL_NULL(wait)
	QDEL_NULL(click_wait)
	QDEL_NULL(verb_wait)
	QDEL_NULL(depth)
	..()

/datum/input_stats/proc/reset()
	wait.reset()
	click_wait.reset()
	verb_wait.reset()
	depth.reset()
	clicks = 0
	verbs_queued = 0
	verbs_direct = 0
	verbs_run = 0
	queue_hwm = 0

/datum/input_stats/proc/record(kind, wait_ms, depth_percent)
	wait.add(wait_ms)
	depth.add(depth_percent)
	if(kind == KM_INPUT_CLICK)
		click_wait.add(wait_ms)
		clicks++
	else
		verb_wait.add(wait_ms)
		verbs_run++

// ---------------------------------------------------------------- the meter

/datum/tick_meter
	/// This tick's charges per system, and the worst OM lateness (ds) a slot of each started with.
	var/list/tick_ms
	var/list/tick_late
	/// Indices charged this tick, in the order they were first charged; the first n_touched are live.
	var/list/touched
	var/n_touched = 0
	/// Everything charged this tick, for SSbehaviours to work out its own remainder.
	var/tick_charged = 0
	/// ms of input work (clicks handled outside the MC, plus the input subsystems) since the last end_tick().
	var/input_ms = 0
	/// Active stats sets; sets[1] is the live one.
	var/list/sets
	var/datum/km_stats_set/live

	// The flight recorder: flat fixed lists of ring_len entries (top systems: KM_TOP_N per entry).
	var/ring_len = KM_RING_LEN
	/// Index of the entry written last, and how many entries hold data.
	var/ring_pos = 0
	var/ring_count = 0
	var/list/fr_tick
	var/list/fr_time
	var/list/fr_usage
	var/list/fr_maptick
	var/list/fr_input
	var/list/fr_streak
	var/list/fr_top_sys
	var/list/fr_top_ms

	/// Consecutive overrun ticks so far, and the totals since boot.
	var/streak = 0
	var/total_ticks = 0
	var/total_overruns = 0
	/// Spike-following peak of world.map_cpu in percent of a tick: the measured BYOND reserve.
	var/map_peak = 0

	/// Whether an overrun writes its admin-log line. Off in test and benchmark builds, where overruns are the
	/// harness's own doing and would fill the log; a test sets it to exercise the line.
#ifdef UNIT_TESTS
	var/log_overruns = FALSE
#else
	var/log_overruns = TRUE
#endif
	var/last_log_time = -INFINITY
	var/suppressed_logs = 0
	/// The last overrun's line and top systems as list(list("key", "ms"), ...): built on overruns only.
	var/last_overrun_line
	var/list/last_overrun_top
	var/last_overrun_usage = 0

/datum/tick_meter/New(ring_len = KM_RING_LEN)
	src.ring_len = ring_len
	tick_ms = new /list(KM_MAX_SYSTEMS)
	tick_late = new /list(KM_MAX_SYSTEMS)
	touched = new /list(KM_MAX_SYSTEMS)
	for(var/i in 1 to KM_MAX_SYSTEMS)
		tick_ms[i] = 0
		tick_late[i] = 0
	fr_tick = new /list(ring_len)
	fr_time = new /list(ring_len)
	fr_usage = new /list(ring_len)
	fr_maptick = new /list(ring_len)
	fr_input = new /list(ring_len)
	fr_streak = new /list(ring_len)
	fr_top_sys = new /list(ring_len * KM_TOP_N)
	fr_top_ms = new /list(ring_len * KM_TOP_N)
	live = new
	sets = list(live)

/datum/tick_meter/on_destroy(force)
	for(var/datum/km_stats_set/S as anything in sets)
		ended_with(S, src)
	sets = null
	live = null
	..()

/// Opens a stats set that records alongside the live one until close_set().
/datum/tick_meter/proc/open_set(datum/om/scheduler/sched)
	var/datum/km_stats_set/S = new
	S.mark_start()
	if(sched)
		S.rollup_base = km_rollup(sched)
	sets += S
	return S

/// Stops feeding `S` (its numbers stay readable). The caller qdels it when done.
/datum/tick_meter/proc/close_set(datum/km_stats_set/S)
	if(S != live)
		sets -= S

/// The measured BYOND reserve: how much of a tick SendMaps has recently taken, in percent (see TICK_BYOND_RESERVE).
/datum/tick_meter/proc/byond_reserve()
	return map_peak

// ---------------------------------------------------------------- charging

/// Charges `ms` of work finished this tick to system `idx`. The hot call: fixed lists, no allocation.
/datum/tick_meter/proc/charge(idx, ms)
	if(idx <= 0)
		idx = KM_SYS_OTHER
	if(ms < KM_MIN_CHARGE_MS)
		ms = KM_MIN_CHARGE_MS
	var/cur = tick_ms[idx]
	if(!cur)
		touched[++n_touched] = idx
	tick_ms[idx] = cur + ms
	tick_charged += ms

/// Notes that an OM slot of system `idx` started `late` deciseconds behind its schedule this tick.
/datum/tick_meter/proc/note_late(idx, late)
	if(idx <= 0)
		idx = KM_SYS_OTHER
	if(late > tick_late[idx])
		tick_late[idx] = late

// ---------------------------------------------------------------- input

/// A click reached atom/Click at `entry_time` / `entry_usage` and is about to be handed to ClickOn(): the wait is
/// how long it took to get there (its event emit), and `entry_usage` is how deep into the tick it ran. Returns
/// the current usage for click_done().
/datum/tick_meter/proc/click_dispatched(entry_time, entry_usage)
	var/now_usage = TICK_USAGE
	record_input(KM_INPUT_CLICK, max((world.time - entry_time) * 100 + TICK_DELTA_TO_MS(now_usage - entry_usage), 0), entry_usage)
	return now_usage

/// The click's ClickOn() returned. Its cost is charged to the input system, unless it slept (the delta is then
/// not its cost).
/datum/tick_meter/proc/click_done(entry_time, dispatch_usage)
	if(world.time != entry_time)
		return
	var/ms = TICK_USAGE_TO_MS(dispatch_usage)
	if(ms <= 0)
		return
	charge(KM_SYS_INPUT, ms)
	input_ms += ms

/// A verb was queued for a later tick; `queue_length` is its queue's length now.
/datum/tick_meter/proc/verb_queued(queue_length)
	for(var/datum/km_stats_set/S as anything in sets)
		var/datum/input_stats/I = S.input
		I.verbs_queued++
		if(queue_length > I.queue_hwm)
			I.queue_hwm = queue_length

/// TRY_QUEUE_VERB declined to queue a verb: it ran on the spot.
/datum/tick_meter/proc/verb_direct()
	for(var/datum/km_stats_set/S as anything in sets)
		S.input.verbs_direct++

/// A queued verb is about to run: it was queued at `enqueue_time` / `enqueue_usage`.
/datum/tick_meter/proc/verb_run(enqueue_time, enqueue_usage)
	var/now_usage = TICK_USAGE
	record_input(KM_INPUT_VERB, max((world.time - enqueue_time) * 100 + TICK_DELTA_TO_MS(now_usage - enqueue_usage), 0), now_usage)

/datum/tick_meter/proc/record_input(kind, wait_ms, depth_percent)
	for(var/datum/km_stats_set/S as anything in sets)
		S.input.record(kind, wait_ms, depth_percent)

// ---------------------------------------------------------------- the tick

/// Closes the tick: `usage` is its percent of a tick at the end of the MC's run, `maptick` is world.map_cpu.
/datum/tick_meter/proc/end_tick(usage, maptick)
	var/overrun = usage > KM_OVERRUN_USAGE
	total_ticks++
	var/top1 = 0
	var/top2 = 0
	var/top3 = 0
	var/ms1 = 0
	var/ms2 = 0
	var/ms3 = 0
	for(var/i in 1 to n_touched)
		var/idx = touched[i]
		var/ms = tick_ms[idx]
		var/late = tick_late[idx]
		if(ms > ms3)
			if(ms > ms2)
				top3 = top2
				ms3 = ms2
				if(ms > ms1)
					top2 = top1
					ms2 = ms1
					top1 = idx
					ms1 = ms
				else
					top2 = idx
					ms2 = ms
			else
				top3 = idx
				ms3 = ms
		// system_stats.record() and km_hist.add() inlined: this runs per touched system per open set every tick.
		var/bin = KM_HIST_BIN(ms)
		for(var/datum/km_stats_set/S as anything in sets)
			var/datum/system_stats/stats = S.systems[idx] || S.stats_for(idx)
			var/datum/km_hist/hist = stats.hist
			hist.bins[bin] = hist.bins[bin] + 1
			if(!hist.count || ms < hist.min_seen)
				hist.min_seen = ms
			if(ms > hist.max_seen)
				hist.max_seen = ms
			hist.count++
			stats.ticks++
			stats.ms_lo += ms
			if(stats.ms_lo >= KM_FLUSH_MS)
				stats.ms_lo -= KM_FLUSH_MS
				stats.ms_hi += KM_FLUSH_MS
			if(overrun)
				stats.overrun_ms += ms
			if(late > stats.late_max)
				stats.late_max = late
	for(var/datum/km_stats_set/S as anything in sets)
		if(isnull(S.started_real))
			S.mark_start()
		S.ticks++

	if(overrun)
		streak++
		total_overruns++
		for(var/datum/km_stats_set/S as anything in sets)
			S.overruns++
			if(streak > S.max_streak)
				S.max_streak = streak
			if(top1)
				S.stats_for(top1).overrun_top_ticks++
			if(top2)
				S.stats_for(top2).overrun_top_ticks++
			if(top3)
				S.stats_for(top3).overrun_top_ticks++
	else
		streak = 0

	// The flight recorder entry.
	ring_pos = ring_pos % ring_len + 1
	if(ring_count < ring_len)
		ring_count++
	fr_tick[ring_pos] = round(world.time / world.tick_lag)
	fr_time[ring_pos] = world.time // ALLOW(sys_world_time_write): the tick meter's own wall-clock stamp for rates and log spacing, not an entity expiry
	fr_usage[ring_pos] = usage
	fr_maptick[ring_pos] = maptick
	fr_input[ring_pos] = input_ms
	fr_streak[ring_pos] = streak
	var/base = (ring_pos - 1) * KM_TOP_N
	fr_top_sys[base + 1] = top1
	fr_top_ms[base + 1] = ms1
	fr_top_sys[base + 2] = top2
	fr_top_ms[base + 2] = ms2
	fr_top_sys[base + 3] = top3
	fr_top_ms[base + 3] = ms3

	map_peak = max(maptick, map_peak * KM_MAP_PEAK_DECAY)

	if(overrun)
		attribute_overrun(usage, maptick, top1, ms1, top2, ms2, top3, ms3)

	for(var/i in 1 to n_touched)
		var/idx = touched[i]
		tick_ms[idx] = 0
		tick_late[idx] = 0
	n_touched = 0
	tick_charged = 0
	input_ms = 0

/// An overrun tick: builds the record of what caused it (allocating is fine here, it is the exception) and, when
/// enabled and not flooding, writes the admin-log line.
/datum/tick_meter/proc/attribute_overrun(usage, maptick, top1, ms1, top2, ms2, top3, ms3)
	var/datum/km_systems/registry = km_systems()
	var/list/top = list()
	var/list/parts = list()
	var/list/entries = list(list(top1, ms1), list(top2, ms2), list(top3, ms3))
	for(var/list/entry as anything in entries)
		var/idx = entry[1]
		if(!idx)
			continue
		var/ms = entry[2]
		var/late = tick_late[idx]
		top += list(list("key" = registry.keys[idx], "ms" = round(ms, 0.01), "label" = registry.lane_label(idx), "late" = late))
		parts += "[registry.keys[idx]] [round(ms, 0.1)]ms ([registry.lane_label(idx)][late > 0 ? ", late [round(late, 0.1)]ds" : ""])"
	var/queue = km_verb_queue_length()
	var/line = "TICK [round(usage)]% (#[fr_tick[ring_pos]]): [length(parts) ? jointext(parts, ", ") : "no system charged"]"
	line += " | BYOND maptick [round(TICK_DELTA_TO_MS(maptick), 0.1)]ms | input [round(input_ms, 0.1)]ms, queue [queue] | streak [streak]"
	last_overrun_line = line
	last_overrun_top = top
	last_overrun_usage = usage
	if(!log_overruns)
		return
	// A sustained overload would write a line every tick: after KM_LOG_FULL_STREAK overruns in a row, one per second.
	if(streak > KM_LOG_FULL_STREAK && world.time - last_log_time < KM_LOG_MIN_GAP) // ALLOW(sys_world_time_expiry): the tick meter's own wall-clock stamp for rates and log spacing, not an entity expiry
		suppressed_logs++
		return
	last_log_time = world.time // ALLOW(sys_world_time_write): the tick meter's own wall-clock stamp for rates and log spacing, not an entity expiry
	if(suppressed_logs)
		line += " (+[suppressed_logs] overrun ticks not logged)"
		suppressed_logs = 0
	log_admin(line)

// ---------------------------------------------------------------- reading the flight recorder

/// Ring index of entry `n` (1 = oldest still held, ring_count = newest).
/datum/tick_meter/proc/ring_index(n)
	return (ring_pos - ring_count + n - 1 + ring_len) % ring_len + 1

/// Every held entry as list(tick, world time, usage, maptick, input ms, streak, list(top keys), list(top ms)),
/// oldest first. Allocates: for admin surfaces and tests, never the tick path.
/datum/tick_meter/proc/recorded_entries(overruns_only = FALSE)
	var/datum/km_systems/registry = km_systems()
	var/list/out = list()
	for(var/n in 1 to ring_count)
		var/at = ring_index(n)
		var/usage = fr_usage[at]
		if(overruns_only && usage <= KM_OVERRUN_USAGE)
			continue
		var/list/keys = list()
		var/list/mss = list()
		var/base = (at - 1) * KM_TOP_N
		for(var/k in 1 to KM_TOP_N)
			var/idx = fr_top_sys[base + k]
			if(!idx)
				continue
			keys += registry.keys[idx]
			mss += fr_top_ms[base + k]
		out += list(list(fr_tick[at], fr_time[at], usage, fr_maptick[at], fr_input[at], fr_streak[at], keys, mss))
	return out

/// The top systems of the tick end_tick() just closed, as list(list("key", "ms"), ...). Allocates; for records built
/// on the rare tick that sets a new worst or overruns.
/datum/tick_meter/proc/latest_top_systems()
	var/list/out = list()
	if(!ring_count)
		return out
	var/datum/km_systems/registry = km_systems()
	var/base = (ring_pos - 1) * KM_TOP_N
	for(var/k in 1 to KM_TOP_N)
		var/idx = fr_top_sys[base + k]
		if(idx)
			out += list(list("key" = registry.keys[idx], "ms" = round(fr_top_ms[base + k], 0.01)))
	return out

/// Total length of every input queue (the inbox: clicks, verbs, Topic, say, tgui actions).
/proc/km_verb_queue_length()
	return SSinput.queued_total()
