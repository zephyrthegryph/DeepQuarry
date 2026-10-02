/// Latency classes, overrun shedding and the input latency record (doc/rewrite/kernel.md sec 1.2 phase K, 1.6;
/// see "Latency classes" in the implementation notes at the end of that document).
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
	/// key (a lane number or a system type) -> world.time of that key's last L3 pass admitted while shedding
	/// (its floor). One floor per key, so a slow L3 system is not starved by a busy one.
	var/list/floor_pass = list() // ALLOW(instance_list): one kernel latency datum; an assoc table written on every admitted pass
	/// Per class (index = LATENCY_L0 + 1): times L3 work was refused.
	var/list/shed_by_class = list(0, 0, 0, 0) // ALLOW(instance_list): one kernel latency datum; a fixed per-class counter table mutated on every shed
	var/shed_events = 0
	/// Input latency: ticks an input waited before it ran (the inbox, code/engine/kernel/inbox.dm). Bin i counts i ticks; the last bin is "or more".
	var/list/input_bins
	var/input_immediate = 0
	var/input_queued = 0
	var/input_dropped = 0
	var/input_over_cap = 0

/datum/kernel_latency/New()
	..()
	input_bins = new /list(KERNEL_LATENCY_BINS)
	for(var/i in 1 to KERNEL_LATENCY_BINS)
		input_bins[i] = 0
#ifdef UNIT_TESTS
	enabled = FALSE
#endif

/proc/kernel_latency()
	RETURN_TYPE(/datum/kernel_latency)
	var/static/datum/kernel_latency/state = new
	return state

/// The latency class of a scheduler lane.
/proc/kernel_lane_class(lane)
	switch(lane)
		if(LANE_URGENT)
			return LATENCY_L1
		if(LANE_SIMULATION, LANE_DERIVED, LANE_WORLD)
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
/// except once per KERNEL_SHED_FLOOR for each `key` (a lane, a system) so none starves and each can catch up.
/datum/kernel_latency/proc/admit(latency_class, key = "l3")
	if(latency_class < LATENCY_L3 || !enabled || !shedding)
		return TRUE
	if(world.time - (floor_pass[key] || -1e9) >= KERNEL_SHED_FLOOR)
		floor_pass[key] = world.time // ALLOW(sys_world_time_write): the kernel clock: a scheduler timestamp of the kernel itself, not a per-entity expiry
		return TRUE
	shed_by_class[latency_class + 1]++
	return FALSE

/// TRUE while `lane` is being shed (does not spend the floor pass).
/datum/kernel_latency/proc/sheds_lane(lane)
	return enabled && shedding && kernel_lane_class(lane) == LATENCY_L3

/// Convenience for a scheduler lane.
/proc/kernel_admit_lane(lane)
	var/datum/kernel_latency/latency = kernel_latency()
	// Every lane is admitted unless shedding: one var read on the scheduler's per-lane path, not two more calls.
	if(!latency.shedding)
		return TRUE
	// A text key: a bare lane number would index floor_pass by position.
	return latency.admit(kernel_lane_class(lane), "lane [lane]")

/// TRUE when this system's work may run now: its own latency class, and its own floor when shedding.
/datum/system/proc/admitted()
	return kernel_latency().admit(latency_class, type)

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

/// Telemetry: shedding state, per-class refusals and the L0 latency percentiles.
/datum/kernel_latency/proc/metrics()
	return alist(
		"shedding" = shedding, "overrun_streak" = overrun_streak, "overruns" = overruns_total,
		"shed_events" = shed_events, "shed_l3" = shed_by_class[LATENCY_L3 + 1],
		"input_p50" = input_percentile(50), "input_p95" = input_percentile(95), "input_p99" = input_percentile(99),
		"input_immediate" = input_immediate, "input_queued" = input_queued, "input_dropped" = input_dropped,
		"input_over_cap" = input_over_cap,
	)

