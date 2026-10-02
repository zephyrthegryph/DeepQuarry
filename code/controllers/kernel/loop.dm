/// The kernel's host loop (doc/rewrite/scheduling_and_kernel.md sec 1): the loop the MC used to own. It wakes every tick,
/// measures drift, decides how much of the tick it may take and runs kernel.tick() (phases K N U D P R G). There is no
/// subsystem queue: what the MC queue ran is now host services (phases K and G, SS_KERNEL_HOSTED) and systems' work items.
///
/// /datum/controller/master stays as a compatibility shim. The loop writes the values code reads from it (iteration,
/// last_run, sleep_delta, tickdrift, current_ticklimit, current_runlevel, processing, ...) so `Master.x` means what it did.

/datum/controller/kernel
	/// The generation of the live loop. A loop that wakes to find another generation has superseded it exits.
	var/loop_gen = 0
	/// Detects a stack overflow that killed the loop's stack (the failsafe asks it).
	var/datum/stack_end_detector/stack_end_detector
	/// Rate limit of Recreate_kernel(): not before this world.time, the window it is forgiven after, how often it ran.
	var/static/restart_clear = 0
	var/static/restart_timeout = 0
	var/static/restart_count = 0

/// Starts the loop after `delay`, and sticks around to restart it if it ever ends: it runs once per init stage (a later
/// stage completing ends a loop with MC_LOOP_RTN_NEWSTAGES and the next one takes up the new stage's hosts).
/datum/controller/kernel/proc/start_loop(delay)
	set waitfor = 0 // ALLOW(scheduler): kernel code (the host loop)
	if(delay)
		sleep(delay) // ALLOW(scheduler): kernel
	testing("Kernel starting processing")
	var/generation = ++loop_gen
	var/started_stage
	var/rtn = -2
	do
		started_stage = Master.init_stage_completed
		rtn = loop(generation, started_stage)
	while (rtn == MC_LOOP_RTN_NEWSTAGES && Master.processing > 0 && started_stage < Master.init_stage_completed)

	if(generation != loop_gen)
		return // a newer loop replaced this one
	if (rtn >= MC_LOOP_RTN_GRACEFUL_EXIT || Master.processing < 0)
		return //this was suppose to happen.
	//loop ended, restart it
	log_game("Kernel loop crashed or runtimed, restarting")
	message_admins("Kernel loop crashed or runtimed, restarting")
	var/rtn2 = Recreate_kernel()
	if (rtn2 <= 0)
		log_game("Failed to restart the kernel loop (Error code: [rtn2]), it's up to the failsafe now")
		message_admins("Failed to restart the kernel loop (Error code: [rtn2]), it's up to the failsafe now")
		Failsafe.defcon = 2

/// Restarts the kernel loop: the old loop (if it is still alive) is superseded, the hosted lists are rebuilt and a
/// fresh loop starts from the stage boot reached. Returns 1 when restarted, 0 when one ran too recently, -1 on a runtime.
/// A restart does not touch the systems or the subsystems: their state carries over, which is why it is cheap.
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

/// Supersedes the running loop and starts a new one. A subsystem that was mid-run (a paused hosted run) is reset.
/datum/controller/kernel/proc/restart_loop()
	loop_gen++ // the old loop sees a stale generation at its next wake and exits
	hosted_k = null
	hosted_g = null
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(SS.flags & SS_KERNEL_HOSTED)
			SS.state = SS_IDLE
	Master.processing = max(Master.processing, 1)
	start_loop(10)

/// The hosted subsystems of the given phase, highest priority first (the order the MC queue gave tickers).
/datum/controller/kernel/proc/hosts_of(phase)
	. = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if((SS.flags & SS_KERNEL_HOSTED) && !(SS.flags & SS_NO_FIRE) && SS.host_phase == phase)
			. += SS
	sortTim(., GLOBAL_PROC_REF(cmp_subsystem_priority))

/// One generation of the loop, for init stage `init_stage`. Returns MC_LOOP_RTN_NEWSTAGES when a later stage completed
/// (so start_loop() takes it up), MC_LOOP_RTN_GRACEFUL_EXIT when superseded, or falls out with a negative number when it
/// must be restarted. Master carries the values the rest of the game reads.
/datum/controller/kernel/proc/loop(generation, init_stage)
	. = -1
	hosted_k = hosts_of(KERNEL_PHASE_K)
	hosted_g = hosts_of(KERNEL_PHASE_G)
	for(var/datum/controller/subsystem/SS as anything in hosted_k + hosted_g)
		if(SS.init_stage > init_stage)
			continue
		SS.state = SS_IDLE
		SS.queued_time = 0
		if(!SS.next_fire)
			SS.next_fire = world.time // ALLOW(sys_world_time_write): hosted subsystem timing, as the MC gave it

	Master.init_timeofday = REALTIMEOFDAY
	Master.init_time = world.time // ALLOW(sys_world_time_write): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
	Master.iteration = 1
	var/sleep_delta = 1

	//setup the stack overflow detector
	own_set(src, nameof(stack_end_detector), new /datum/stack_end_detector())
	var/datum/stack_canary/canary = stack_end_detector.prime_canary()
	canary.use_variable()
	//the actual loop.
	while (1)
		if(generation != loop_gen)
			return MC_LOOP_RTN_GRACEFUL_EXIT
		var/newdrift = ((REALTIMEOFDAY - Master.init_timeofday) - (world.time - Master.init_time)) / world.tick_lag
		Master.tickdrift = max(0, MC_AVERAGE_FAST(Master.tickdrift, newdrift))
		var/starting_tick_usage = TICK_USAGE
		Master.perf_tick_top_name = "None"
		Master.perf_tick_top_usage = 0
		Master.perf_tick_peak_usage = starting_tick_usage
		Master.perf_tick_start_usage = starting_tick_usage
		LAZYCLEARLIST(Master.perf_tick_breakdown)

		if (init_stage != Master.init_stage_completed)
			// Initialization deliberately blocks for long stretches. Establish the
			// drift baseline without treating boot work as a gameplay outlier.
			Master.olddrift = newdrift
			return MC_LOOP_RTN_NEWSTAGES

		if(newdrift - Master.olddrift >= CONFIG_GET(number/drift_dump_threshold))
			Master.AttemptProfileDump(CONFIG_GET(number/drift_profile_delay))
		Master.olddrift = newdrift
		if (Master.processing <= 0)
			Master.current_ticklimit = TICK_LIMIT_RUNNING
			sleep(1 SECONDS) // ALLOW(scheduler): kernel
			continue

		//Anti-tick-contention heuristics:
		if (init_stage == INITSTAGE_MAX)
			//if there are multiple sleeping procs running before us hogging the cpu, we have to run later.
			// (because sleeps are processed in the order received, longer sleeps are more likely to run first)
			if (starting_tick_usage > TICK_LIMIT_MC) //if there isn't enough time to bother doing anything this tick, sleep a bit.
				sleep_delta *= 2
				Master.current_ticklimit = TICK_LIMIT_RUNNING * 0.5
				sleep(world.tick_lag * (Master.processing * sleep_delta)) // ALLOW(scheduler): kernel
				continue

			//Byond resumed us late. assume it might have to do the same next tick
			if (Master.last_run + CEILING(world.tick_lag * (Master.processing * sleep_delta), world.tick_lag) < world.time) // ALLOW(sys_world_time_expiry): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
				sleep_delta += 1

			sleep_delta = MC_AVERAGE_FAST(sleep_delta, 1) //decay sleep_delta

			if (starting_tick_usage > (TICK_LIMIT_MC*0.75)) //we ran 3/4 of the way into the tick
				sleep_delta += 1
		else
			sleep_delta = 1

		//debug
		if (Master.make_runtime)
			var/datum/controller/subsystem/SS
			SS.can_fire = 0

		if (!Failsafe || (Failsafe.processing_interval > 0 && (Failsafe.lasttick+(Failsafe.processing_interval*5)) < world.time)) // ALLOW(sys_world_time_expiry): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
			new/datum/controller/failsafe() // (re)Start the failsafe.

		//now do the actual stuff: a laggy map update ahead (skip_ticks) runs only the input phase this tick
		tick(Master.current_ticklimit, init_stage, light = !!Master.skip_ticks)

		Master.iteration++
		Master.last_run = world.time // ALLOW(sys_world_time_write): the kernel loop's own bookkeeping (drift, restart rate limit), not an entity expiry
		if (Master.skip_ticks)
			Master.skip_ticks--
		Master.sleep_delta = MC_AVERAGE_FAST(Master.sleep_delta, sleep_delta)

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
			Master.current_ticklimit = TICK_LIMIT_RUNNING * 2
		else
			Master.current_ticklimit = TICK_LIMIT_RUNNING
			if (Master.processing * sleep_delta <= world.tick_lag)
				Master.current_ticklimit -= (TICK_LIMIT_RUNNING * 0.25) //reserve the tail 1/4 of the next tick for the loop if we plan on running next tick

		Master.check_and_perform_fast_update()
		Master.record_performance_tick(max(Master.perf_tick_peak_usage, TICK_USAGE))
		sleep(world.tick_lag * (Master.processing * sleep_delta)) // ALLOW(scheduler): kernel
