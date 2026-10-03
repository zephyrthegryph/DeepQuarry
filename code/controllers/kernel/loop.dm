/// The kernel's host loop (doc/rewrite/scheduling_and_kernel.md sec 1). It wakes every tick, measures drift, decides how much
/// of the tick it may take and runs kernel.tick() (phases K S N U D P R G). There is no subsystem queue: what runs is the
/// systems' work items. The loop keeps the values the rest of the game reads off `Kernel` (iteration, last_run, sleep_delta,
/// tickdrift, current_ticklimit, current_runlevel, processing, ...).

/datum/controller/kernel
	/// The generation of the live loop. A loop that wakes to find another generation has superseded it exits.
	var/loop_gen = 0
	/// Detects a stack overflow that killed the loop's stack (the failsafe asks it).
	var/datum/stack_end_detector/stack_end_detector
	/// Rate limit of Recreate_kernel(): not before this world.time, the window it is forgiven after, how often it ran.
	var/static/restart_clear = 0
	var/static/restart_timeout = 0
	var/static/restart_count = 0

CAPABILITIES(/datum/controller/kernel)
	owns_one(nameof(stack_end_detector), /datum/stack_end_detector)

/// Starts the loop after `delay`, and sticks around to restart it if it ever ends: it runs once per init stage (a later
/// stage completing ends a loop with KERNEL_LOOP_RTN_NEWSTAGES and the next one takes up the new stage's hosts).
/datum/controller/kernel/proc/start_loop(delay)
	set waitfor = 0 // ALLOW(scheduler): kernel code (the host loop)
	if(delay)
		sleep(delay) // ALLOW(scheduler): the kernel's own loop: it is the scheduler, so it sleeps between ticks
	testing("Kernel starting processing")
	var/generation = ++loop_gen
	var/started_stage
	var/rtn = -2
	do
		started_stage = Kernel.init_stage_completed
		rtn = loop(generation, started_stage)
	while (rtn == KERNEL_LOOP_RTN_NEWSTAGES && Kernel.processing > 0 && started_stage < Kernel.init_stage_completed)

	if(generation != loop_gen)
		return // a newer loop replaced this one
	if (rtn >= KERNEL_LOOP_RTN_GRACEFUL_EXIT || Kernel.processing < 0)
		return //this was suppose to happen.
	//loop ended, restart it
	log_game("Kernel loop crashed or runtimed, restarting")
	message_admins("Kernel loop crashed or runtimed, restarting")
	var/rtn2 = Recreate_kernel()
	if (rtn2 <= 0)
		log_game("Failed to restart the kernel loop (Error code: [rtn2]), it's up to the watchdog now")
		message_admins("Failed to restart the kernel loop (Error code: [rtn2]), it's up to the watchdog now")
		watchdog?.defcon = 2

/// Restarts the kernel loop: the old loop (if it is still alive) is superseded and a fresh loop starts from the stage
/// boot reached. Returns 1 when restarted, 0 when one ran too recently, -1 on a runtime.
/// A restart does not touch the systems: their state carries over, which is why it is cheap.
/proc/Recreate_kernel()
	. = -1 //so if we runtime, things know we failed
	var/datum/controller/kernel/K = kernel()
	if (world.time < K.restart_timeout) // ALLOW(sys_world_time_expiry): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
		return 0
	if (world.time < K.restart_clear) // ALLOW(sys_world_time_expiry): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
		K.restart_count *= 0.5
	var/delay = 50 * ++K.restart_count
	K.restart_timeout = world.time + delay // ALLOW(sys_world_time_write): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
	K.restart_clear = world.time + (delay * 2) // ALLOW(sys_world_time_write): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
	try
		K.restart_loop()
	catch(var/exception/e)
		dq_report_caught(e, "Kernel loop restart")
		return -1
	return 1

/// Supersedes the running loop and starts a new one.
/datum/controller/kernel/proc/restart_loop()
	loop_gen++ // the old loop sees a stale generation at its next wake and exits
	Kernel.processing = max(Kernel.processing, 1)
	start_loop(10)

/// Drops every work item's in-flight run (a yielded sweep, an open cursor), so the next loop starts them clean.
/datum/controller/kernel/proc/reset_work()
	for(var/datum/work_item/W as anything in work_all)
		W.cursor = 0
		W.yielded = FALSE
		W.next_run = 0
	work_due_reset()

/// One generation of the loop, for init stage `init_stage`. Returns KERNEL_LOOP_RTN_NEWSTAGES when a later stage completed
/// (so start_loop() takes it up), KERNEL_LOOP_RTN_GRACEFUL_EXIT when superseded, or falls out with a negative number when it
/// must be restarted. The kernel carries the values the rest of the game reads.
/datum/controller/kernel/proc/loop(generation, init_stage)
	. = -1
	Kernel.init_timeofday = REALTIMEOFDAY
	Kernel.init_time = world.time // ALLOW(sys_world_time_write): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
	Kernel.iteration = 1
	var/sleep_delta = 1

	//setup the stack overflow detector
	rel_set(src, nameof(stack_end_detector), new /datum/stack_end_detector())
	var/datum/stack_canary/canary = stack_end_detector.prime_canary()
	canary.use_variable()
	//the actual loop.
	while (1)
		if(generation != loop_gen)
			return KERNEL_LOOP_RTN_GRACEFUL_EXIT
		var/newdrift = ((REALTIMEOFDAY - Kernel.init_timeofday) - (world.time - Kernel.init_time)) / world.tick_lag
		Kernel.tickdrift = max(0, KERNEL_AVERAGE_FAST(Kernel.tickdrift, newdrift))
		var/starting_tick_usage = TICK_USAGE
		Kernel.perf_tick_top_name = "None"
		Kernel.perf_tick_top_usage = 0
		Kernel.perf_tick_peak_usage = starting_tick_usage
		Kernel.perf_tick_start_usage = starting_tick_usage
		LAZYCLEARLIST(Kernel.perf_tick_breakdown)

		if (init_stage != Kernel.init_stage_completed)
			// Initialization deliberately blocks for long stretches. Establish the
			// drift baseline without treating boot work as a gameplay outlier.
			Kernel.olddrift = newdrift
			return KERNEL_LOOP_RTN_NEWSTAGES

		if(newdrift - Kernel.olddrift >= CONFIG_GET(number/drift_dump_threshold))
			Kernel.AttemptProfileDump(CONFIG_GET(number/drift_profile_delay))
		Kernel.olddrift = newdrift
		if (Kernel.processing <= 0)
			Kernel.current_ticklimit = TICK_LIMIT_RUNNING
			sleep(1 SECONDS) // ALLOW(scheduler): the kernel's own loop: it is the scheduler, so it sleeps between ticks
			continue

		//Anti-tick-contention heuristics:
		if (init_stage == INITSTAGE_MAX)
			//if there are multiple sleeping procs running before us hogging the cpu, we have to run later.
			// (because sleeps are processed in the order received, longer sleeps are more likely to run first)
			if (starting_tick_usage > TICK_LIMIT_MC) //if there isn't enough time to bother doing anything this tick, sleep a bit.
				sleep_delta *= 2
				Kernel.current_ticklimit = TICK_LIMIT_RUNNING * 0.5
				sleep(world.tick_lag * (Kernel.processing * sleep_delta)) // ALLOW(scheduler): the kernel's own loop: it is the scheduler, so it sleeps between ticks
				continue

			//Byond resumed us late. assume it might have to do the same next tick
			if (Kernel.last_run + CEILING(world.tick_lag * (Kernel.processing * sleep_delta), world.tick_lag) < world.time) // ALLOW(sys_world_time_expiry): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
				sleep_delta += 1

			sleep_delta = KERNEL_AVERAGE_FAST(sleep_delta, 1) //decay sleep_delta

			if (starting_tick_usage > (TICK_LIMIT_MC*0.75)) //we ran 3/4 of the way into the tick
				sleep_delta += 1
		else
			sleep_delta = 1

		//debug
		if (Kernel.make_runtime)
			var/datum/system/SS
			SS.can_fire = 0

		if (!watchdog || (watchdog.processing_interval > 0 && (watchdog.lasttick+(watchdog.processing_interval*5)) < world.time)) // ALLOW(sys_world_time_expiry): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
			start_watchdog() // (re)start the watchdog

		//now do the actual stuff: a laggy map update ahead (skip_ticks) runs only the input phase this tick
		tick(Kernel.current_ticklimit, init_stage, light = !!Kernel.skip_ticks)

		Kernel.iteration++
		Kernel.last_run = world.time // ALLOW(sys_world_time_write): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
		if (Kernel.skip_ticks)
			Kernel.skip_ticks--
		Kernel.sleep_delta = KERNEL_AVERAGE_FAST(Kernel.sleep_delta, sleep_delta)

// Force any verbs into overtime, to test how they perfrom under load
// For local ONLY
#ifdef VERB_STRESS_TEST
		/// Target enough tick usage to only allow time for our maptick estimate and verb processing, and nothing else
		var/overtime_target = TICK_LIMIT_RUNNING
// This will leave just enough cpu time for maptick, forcing verbs to run into overtime
// Use this for testing the worst case scenario, when maptick is spiking and usage is otherwise completely consumed
#ifdef FORCE_VERB_OVERTIME
		overtime_target += TICK_BYOND_RESERVE
#endif
		CONSUME_UNTIL(overtime_target)
#endif

		if (init_stage != INITSTAGE_MAX)
			Kernel.current_ticklimit = TICK_LIMIT_RUNNING * 2
		else
			Kernel.current_ticklimit = TICK_LIMIT_RUNNING
			if (Kernel.processing * sleep_delta <= world.tick_lag)
				Kernel.current_ticklimit -= (TICK_LIMIT_RUNNING * 0.25) //reserve the tail 1/4 of the next tick for the loop if we plan on running next tick

		Kernel.check_and_perform_fast_update()
		Kernel.record_performance_tick(max(Kernel.perf_tick_peak_usage, TICK_USAGE))
		sleep(world.tick_lag * (Kernel.processing * sleep_delta)) // ALLOW(scheduler): the kernel's own loop: it is the scheduler, so it sleeps between ticks
