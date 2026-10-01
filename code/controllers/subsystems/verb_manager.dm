/**
 * SSverb_manager, a subsystem that runs every tick and runs through its entire queue without yielding like SSinput.
 * this exists because of how the byond tick works and where user inputted verbs are put within it.
 *
 * see TICK_ORDER.md for more info on how the byond tick is structured.
 *
 * The way the MC allots its time is via TICK_LIMIT_RUNNING (80% of the tick, see _tick.dm). It does not subtract the cost of SendMaps
 * (MAPTICK_LAST_INTERNAL_TICK_USAGE) from that: the ~20% it leaves is what verbs, clicks, SendMaps and any overrun all share.
 * The tick meter (code/controllers/measure/) measures how much of a tick SendMaps recently took (TICK_BYOND_RESERVE), names what
 * caused each overrun, and records how long every queued verb and every click waited.
 *
 * Without this subsystem, verbs are likely to cause overtime if the MC uses all of the time it has allotted for itself in the tick, and SendMaps
 * uses as much as its expected to, and an expensive verb ends up executing that tick. This is because the MC is completely blind to the cost of
 * verbs, it can't account for it at all.
 *
 * With this subsystem, the MC can account for the cost of verbs and thus stop major overruns of ticks. This means that the most important subsystems
 * like SSinput can start at the same time they were supposed to, leading to a smoother experience for the player since ticks aren't riddled with
 * minor hangs over and over again.
 */
/// One verb queue: the state and the rules of a host that runs delayed verbs (SSverb_manager, SSspeech_controller). The host
/// owns the lane and calls run_verb_queue() every tick; _queue_verb() finds the lane of whatever host it is handed.
/datum/verb_lane
	var/name = "verb lane"
	/// Ticks between runs of the host (the verbs-per-second average reads it).
	var/wait = 1
	/// RUNLEVEL_* bits the lane queues in.
	var/runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	///list of callbacks to procs called from verbs or verblike procs that were executed when the server was overloaded and had to delay to the next tick.
	///this list is ran through every tick, and the host does not yield until this queue is finished.
	var/list/datum/callback/verb_callback/verb_queue = list() // ALLOW(instance_list): a lane is a singleton per host

	///running average of how many verb callbacks are executed every second. used for the stat entry
	var/verbs_executed_per_second = 0

	///if TRUE we treat usr's with holders just like usr's without holders. otherwise they always execute immediately
	var/can_queue_admin_verbs = FALSE

	///if this is true all verbs immediately execute and don't queue. in case the mc is fucked or something
	var/FOR_ADMINS_IF_VERBS_FUCKED_immediately_execute_all_verbs = FALSE

	///if TRUE this will... message admins every time a verb is queued to this lane for the next tick with stats.
	///for obvious reasons don't make this be TRUE on the code level this is for admins to turn on
	var/message_admins_on_queue = FALSE

	///always queue if possible. overrides can_queue_admin_verbs but not FOR_ADMINS_IF_VERBS_FUCKED_immediately_execute_all_verbs
	var/always_queue = FALSE

/**
 * queue a callback for the given verb/verblike proc and any given arguments to the specified verb host (SSverb_manager or
 * SSspeech_controller), so that they process in the next tick.
 * intended to only work with verbs or verblike procs called directly from client input, use as part of TRY_QUEUE_VERB() and co.
 *
 * returns TRUE if the queuing was successful, FALSE otherwise.
 */
/proc/_queue_verb(datum/callback/verb_callback/incoming_callback, tick_check, datum/host = SSverb_manager, ...)
	if(QDELETED(incoming_callback))
		var/destroyed_string
		if(!incoming_callback)
			destroyed_string = "callback is null."
		else
			destroyed_string = "callback was deleted [DS2TICKS(world.time - incoming_callback.gc_destroyed)] ticks ago. callback was created [DS2TICKS(world.time) - incoming_callback.creation_time] ticks ago."

		stack_trace("_queue_verb() returned false because it was given a deleted callback! [destroyed_string]")
		return FALSE

	var/datum/callback_target = incoming_callback.target_object()
	if(!callback_target) //GLOBAL_PROC reads as itself
		var/destroyed_string = "callback.object is null or deleted. callback was created [DS2TICKS(world.time) - incoming_callback.creation_time] ticks ago."

		stack_trace("_queue_verb() returned false because it was given a callback acting on a qdeleted object! [destroyed_string]")
		return FALSE

	//we want unit tests to be able to directly call verbs that attempt to queue, and since unit tests should test internal behavior, we want the queue
	//to happen as if it was actually from player input if its called on a mob.
#ifdef UNIT_TESTS
	if(QDELETED(usr) && ismob(callback_target))
		rel_set(incoming_callback, nameof(/datum/callback::user), callback_target)
		var/datum/callback/new_us = CALLBACK(arglist(list(GLOBAL_PROC, GLOBAL_PROC_REF(_queue_verb)) + args.Copy()))
		return world.push_usr(callback_target, new_us)

#else

	if(QDELETED(usr) || isnull(usr.client))
		stack_trace("_queue_verb() returned false because it wasn't called from player input!")
		return FALSE

#endif

	var/datum/verb_lane/lane = verb_lane_of(host)
	if(!lane)
		stack_trace("_queue_verb() returned false because it was given an invalid host to queue for!")
		return FALSE

	if((TICK_USAGE < tick_check) && !lane.always_queue)
		km_meter().verb_direct()
		return FALSE

	var/list/args_to_check = args.Copy()
	args_to_check.Cut(2, 4)//cut out tick_check and host

	//any lane can use the additional arguments to refuse queuing
	if(!lane.can_queue_verb(arglist(args_to_check)))
		return FALSE

	return lane.queue_verb(incoming_callback)

/// The verb lane a host owns: SSverb_manager's or SSspeech_controller's, or the lane itself.
/proc/verb_lane_of(datum/host)
	RETURN_TYPE(/datum/verb_lane)
	if(istype(host, /datum/verb_lane))
		return host
	if(istype(host, /datum/controller/subsystem/verb_manager))
		var/datum/controller/subsystem/verb_manager/manager = host
		return manager.lane
	if(istype(host, /datum/system/speech_controller))
		var/datum/system/speech_controller/speech = host
		return speech.lane
	return null

/**
 * lane-specific check for whether a callback can be queued.
 * intended so that lanes can verify whether
 *
 * lanes may include additional arguments here if they need them! you just need to include them properly
 * in TRY_QUEUE_VERB() and co.
 */
/datum/verb_lane/proc/can_queue_verb(datum/callback/verb_callback/incoming_callback)
	if(always_queue && !FOR_ADMINS_IF_VERBS_FUCKED_immediately_execute_all_verbs)
		return TRUE

	if((usr.client?.holder && !can_queue_admin_verbs) \
	|| FOR_ADMINS_IF_VERBS_FUCKED_immediately_execute_all_verbs \
	|| !(runlevels & (1 << (Master.current_runlevel - 1))))
		return FALSE

	return TRUE

/**
 * queue a callback for the given proc, so that it is invoked in the next tick.
 * intended to only work with verbs or verblike procs called directly from client input, use as part of TRY_QUEUE_VERB()
 *
 * returns TRUE if the queuing was successful, FALSE otherwise.
 */
/datum/verb_lane/proc/queue_verb(datum/callback/verb_callback/incoming_callback)
	. = FALSE //errored
	if(message_admins_on_queue)
		message_admins("[name] verb queuing: tick usage: [TICK_USAGE]%, proc: [incoming_callback.delegate], object: [incoming_callback.target_object()], usr: [usr]")
	incoming_callback.enqueue_time = world.time
	incoming_callback.enqueue_usage = TICK_USAGE
	verb_queue += incoming_callback
	km_meter().verb_queued(length(verb_queue))
	return TRUE

/// runs through all of this lane's queue of verb callbacks.
/// goes through the entire verb queue without yielding.
/// used so you can flush the queue outside of the host's run without interfering with anything else it does.
/datum/verb_lane/proc/run_verb_queue()
	var/executed_verbs = 0

	for(var/datum/callback/verb_callback/verb_callback as anything in verb_queue)
		if(!istype(verb_callback))
			stack_trace("non /datum/callback/verb_callback inside [name]'s verb_queue!")
			continue

		km_meter().verb_run(verb_callback.enqueue_time, verb_callback.enqueue_usage)
		verb_callback.InvokeAsync()
		executed_verbs++

	verb_queue.Cut()
	verbs_executed_per_second = MC_AVG_SECONDS(verbs_executed_per_second, executed_verbs, wait SECONDS)
	//note that wait SECONDS is incorrect if this is called outside of the host's run but because byond is garbage i need to add a timer to rustg to find a valid solution

/// The stat panel text of the lane.
/datum/verb_lane/proc/stat_text()
	return "V/S: [round(verbs_executed_per_second, 0.01)]"

SUBSYSTEM_DEF(verb_manager)
	name = "Verb Manager"
	wait = 1
	flags = SS_TICKER | SS_NO_INIT | SS_KERNEL_HOSTED
	priority = FIRE_PRIORITY_DELAYED_VERBS
	counts_as_input = TRUE
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	/// The queue SSverb_manager runs every tick.
	var/datum/verb_lane/lane

/datum/controller/subsystem/verb_manager/PreInit()
	lane = new
	lane.name = name

/datum/controller/subsystem/verb_manager/fire(resumed)
	lane.run_verb_queue()

/datum/controller/subsystem/verb_manager/stat_entry(msg)
	. = ..()
	. += lane.stat_text()
