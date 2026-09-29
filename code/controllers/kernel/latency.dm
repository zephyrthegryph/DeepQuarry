/// Latency classes, overrun shedding and the kernel click queue (systems design sec 1.2 phase K, 1.6;
/// gap_latency_profiling proposal (a)).
///
///   L0 input       runs first every tick, never deferred or shed, capped at KERNEL_INPUT_CAP and measured
///   L1 deadline    runs on time or counts as a breach; never shed
///   L2 defer       runs late with real dt and never skips
///   L3 shed        skipped under an overrun streak, with a floor of one pass per KERNEL_SHED_FLOOR, then catches up
///
/// A tick "overruns" when its usage passes 100. After KERNEL_SHED_STREAK overruns in a row the kernel
/// sheds L3 until KERNEL_SHED_RECOVER ticks pass without one.

/datum/kernel_latency
	/// Shedding only acts when enabled (unit-test builds leave it off so a slow test boot cannot change lane behaviour).
	var/enabled = TRUE
	var/overrun_streak = 0
	var/calm_streak = 0
	var/shedding = FALSE
	var/overruns_total = 0
	/// world.time of the last L3 pass admitted while shedding (the floor).
	var/last_floor_pass = -1e9
	/// Per class (index = LATENCY_L0 + 1): times L3 work was refused.
	var/list/shed_by_class = list(0, 0, 0, 0)
	var/shed_events = 0
	/// Input latency: ticks a click waited before it ran. Bin i counts i ticks; the last bin is "or more".
	var/list/input_bins
	var/input_immediate = 0
	var/input_queued = 0
	var/input_dropped = 0
	var/input_over_cap = 0
	/// The click queue: list(user, target, location, control, params, enqueue world.time).
	var/list/click_queue

/datum/kernel_latency/New()
	..()
	input_bins = new /list(KERNEL_LATENCY_BINS)
	for(var/i in 1 to KERNEL_LATENCY_BINS)
		input_bins[i] = 0
#ifdef UNIT_TESTS
	enabled = FALSE
#endif

/proc/kernel_latency()
	var/static/datum/kernel_latency/state = new
	return state

/// The latency class of a scheduler lane.
/proc/kernel_lane_class(lane)
	switch(lane)
		if(LANE_URGENT)
			return LATENCY_L1
		if(LANE_SIMULATION, LANE_DERIVED)
			return LATENCY_L2
	return LATENCY_L3

/// One finished tick's usage, from the MC loop. Drives the overrun streak and the shed switch.
/datum/kernel_latency/proc/note_tick(usage)
	if(usage > 100)
		overruns_total++
		overrun_streak++
		calm_streak = 0
		if(!shedding && overrun_streak >= KERNEL_SHED_STREAK)
			shedding = TRUE
			shed_events++
			log_world("Kernel: shedding L3 after [overrun_streak] overrun ticks (tick usage [round(usage)]%).")
	else
		overrun_streak = 0
		calm_streak++
		if(shedding && calm_streak >= KERNEL_SHED_RECOVER)
			shedding = FALSE
			log_world("Kernel: L3 shedding ended after [calm_streak] calm ticks.")

/// TRUE when work of `latency_class` may run this pass. L0-L2 always run. L3 is refused while shedding,
/// except once per KERNEL_SHED_FLOOR so it never starves and can catch up.
/datum/kernel_latency/proc/admit(latency_class)
	if(latency_class < LATENCY_L3 || !enabled || !shedding)
		return TRUE
	if(world.time - last_floor_pass >= KERNEL_SHED_FLOOR)
		last_floor_pass = world.time
		return TRUE
	shed_by_class[latency_class + 1]++
	return FALSE

/// TRUE while `lane` is being shed (does not spend the floor pass).
/datum/kernel_latency/proc/sheds_lane(lane)
	return enabled && shedding && kernel_lane_class(lane) == LATENCY_L3

/// Convenience for a scheduler lane.
/proc/kernel_admit_lane(lane)
	return kernel_latency().admit(kernel_lane_class(lane))

/datum/system/proc/admitted()
	return kernel_latency().admit(latency_class)

// ---- input

/// Records a click that waited `ticks` ticks (0: it ran on arrival).
/datum/kernel_latency/proc/record_input(ticks)
	var/bin = clamp(round(ticks) + 1, 1, KERNEL_LATENCY_BINS)
	input_bins[bin]++

/// The tick count at percentile `pct` (0-100) of recorded input latency, from one pass over the bins.
/datum/kernel_latency/proc/input_percentile(pct)
	var/total = 0
	for(var/n in input_bins)
		total += n
	if(!total)
		return 0
	var/target = total * pct / 100
	var/seen = 0
	for(var/i in 1 to KERNEL_LATENCY_BINS)
		seen += input_bins[i]
		if(seen >= target)
			return i - 1
	return KERNEL_LATENCY_BINS - 1

/// TRUE when a click arriving now should wait for the next tick: the server is near overtime, the
/// clicker is a real player, and the click is not already inside the queue drain.
/datum/kernel_latency/proc/should_queue_click(mob/user)
	if(!enabled || !user?.client)
		return FALSE
	return TICK_USAGE >= VERB_HIGH_PRIORITY_QUEUE_THRESHOLD

/// Queues a click for the next tick's drain. Returns TRUE when it was queued.
/datum/kernel_latency/proc/enqueue_click(mob/user, atom/target, location, control, params)
	LAZYINITLIST(click_queue)
	if(length(click_queue) >= KERNEL_CLICK_QUEUE_MAX)
		click_queue.Cut(1, 2)
		input_dropped++
	click_queue += list(list(user, target, location, control, params, world.time))
	input_queued++
	return TRUE

/// Runs every queued click as its own clicker, oldest first, and records how long each waited. Called first
/// in the tick by SSinput (phase K). A clicker or target deleted meanwhile drops the click.
/datum/kernel_latency/proc/drain_clicks()
	if(!length(click_queue))
		return 0
	var/list/batch = click_queue
	click_queue = null
	var/started = TICK_USAGE
	var/ran = 0
	for(var/list/entry as anything in batch)
		var/mob/user = entry[1]
		var/atom/target = entry[2]
		if(QDELETED(user) || QDELETED(target))
			input_dropped++
			continue
		record_input((world.time - entry[6]) / world.tick_lag)
		world.push_usr(user, CALLBACK(target, TYPE_PROC_REF(/atom, kernel_click_run), user, entry[3], entry[4], entry[5]))
		ran++
	if(TICK_USAGE - started > KERNEL_INPUT_CAP)
		input_over_cap++
	return ran

/// Telemetry: shedding state, per-class refusals and the L0 latency percentiles.
/datum/kernel_latency/proc/metrics()
	return alist(
		"shedding" = shedding, "overrun_streak" = overrun_streak, "overruns" = overruns_total,
		"shed_events" = shed_events, "shed_l3" = shed_by_class[LATENCY_L3 + 1],
		"input_p50" = input_percentile(50), "input_p95" = input_percentile(95), "input_p99" = input_percentile(99),
		"input_immediate" = input_immediate, "input_queued" = input_queued, "input_dropped" = input_dropped,
		"input_over_cap" = input_over_cap,
	)

/// A click, as its clicker: the event, then the mob's click handling.
/atom/proc/kernel_click_run(mob/user, location, control, params)
	OM_EMIT(src, /datum/om/event/click, location, control, params, user)
	user.ClickOn(src, params)
