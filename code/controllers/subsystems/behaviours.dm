/**
 * # SSbehaviours
 *
 * Runs the live object-model scheduler (doc/rewrite/object_model_core.md): deadlines,
 * wakes, derived values and cadence rings, each lane with a guaranteed share of the
 * budget Master gives this subsystem. All state lives in the scheduler, so a fire that
 * runs out of budget simply continues next fire; nothing here pauses mid-loop.
 */
SUBSYSTEM_DEF(behaviours)
	name = "Behaviours"
	wait = 1 // SS_TICKER: in ticks
	priority = FIRE_PRIORITY_BEHAVIOURS
	flags = SS_TICKER|SS_KEEP_TIMING
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT
	var/last_done = TRUE

/datum/controller/subsystem/behaviours/Initialize()
	om_registry()
	om_scheduler()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/behaviours/fire(resumed)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(!sched)
		return
	last_done = sched.run_pass(Master.current_ticklimit)

/datum/controller/subsystem/behaviours/stat_entry(msg)
	var/datum/om/scheduler/sched = GLOB.om_live_sched
	if(sched)
		msg = "[round(sched.last_run_ms, 0.01)]ms[last_done ? "" : " (behind)"] E:[length(sched.errors)]"
	return ..()

/datum/controller/subsystem/behaviours/Recover()
	last_done = SSbehaviours.last_done
