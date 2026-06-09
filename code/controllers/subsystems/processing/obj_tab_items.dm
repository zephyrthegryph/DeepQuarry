PROCESSING_SUBSYSTEM_DEF(obj_tab_items)
	name = "Obj Tab Items"
	flags = SS_NO_INIT
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	wait = 0.1 SECONDS
	// process() on obj_tab_items expects seconds_per_tick (not raw deciseconds).
	// scale = 0.1 converts: wait=1ds * 0.1 = 0.1s per tick at 1 SECOND wait.
	process_wait_scale = 0.1

// Custom fire loop: decrements current_run.len AFTER the tick check so that
// on a tick overrun the current item is retried next fire() rather than
// advanced past. This preserves tighter fairness for this 10Hz subsystem.
/datum/controller/subsystem/processing/obj_tab_items/fire(resumed = FALSE)
	if (!resumed)
		currentrun = processing.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/current_run = currentrun
	var/process_delta = SCALE_PROCESS_DELTA(wait, process_wait_scale)

	while(length(current_run))
		var/datum/thing = current_run[length(current_run)]
		if(QDELETED(thing))
			processing -= thing
		else if(thing.process(process_delta) == PROCESS_KILL)
			// fully stop so that a future START_PROCESSING will work
			STOP_PROCESSING(src, thing)
		if (MC_TICK_CHECK)
			return
		current_run.len--
