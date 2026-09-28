// Feature subsystems on the object-model scheduler (doc/rewrite/completion_plan.md §3.6).
//
// These subsystems stay as named services (GLOB.vote_service, SSsupply, ...) holding their state and procs,
// but they are SS_NO_FIRE: their periodic work is a cadence behaviour on the global owner
// (om_global_owner()), run by SSbehaviours inside its lane budget like the world lanes
// (world_lanes.dm). The old fire() is the subsystem's lane_step(resumed).
//
// A step that runs out of budget returns FALSE (TICK_CHECK) and resumes one tick later through
// a deadline, the same mechanism /datum/om/behaviour/world uses. Steps must not sleep.

/// TRUE while a yielded lane_step() is waiting to resume.
/datum/controller/subsystem/var/lane_resuming = FALSE

/// The feature subsystem's periodic work (was fire()). `resumed`: continuing a step that
/// yielded. Return FALSE to yield (resumes next tick), TRUE when the step is complete.
/datum/controller/subsystem/proc/lane_step(resumed)
	SHOULD_NOT_SLEEP(TRUE)
	return TRUE

/// Runs lane_step() with resume bookkeeping. Returns what lane_step() returned.
/datum/controller/subsystem/proc/run_lane_step()
	SHOULD_NOT_SLEEP(TRUE)
	var/resumed = lane_resuming
	var/done = lane_step(resumed)
	lane_resuming = !done
	return done

/// Feature lane types attached at SSbehaviours init.
/proc/om_feature_lanes()
	return list(
	)

/// Attaches every feature lane to the live scheduler's global owner (SSbehaviours init).
/proc/om_start_feature_lanes()
	var/datum/om/global_owner/owner = om_global_owner()
	for(var/lane_type in om_feature_lanes())
		if(!om_attached(owner, lane_type))
			om_attach(owner, lane_type)
		log_world("OM feature lane started: [lane_type]")

// ---------------------------------------------------------------- lanes

/// A feature subsystem's cadence on the global owner.
/datum/om/behaviour/world/feature
	abstract_type = /datum/om/behaviour/world/feature
	runlevels = RUNLEVELS_DEFAULT

/// The subsystem whose lane_step() this lane runs.
/datum/om/behaviour/world/feature/proc/subsystem()
	RETURN_TYPE(/datum/controller/subsystem)
	return null

/datum/om/behaviour/world/feature/tick(datum/E, dt)
	var/datum/controller/subsystem/S = subsystem()
	if(!S || S.lane_resuming) // a yielded step owns the next tick's deadline
		return
	if(!S.run_lane_step())
		om_deadline(E, world.tick_lag, src)

/datum/om/behaviour/world/feature/on_deadline(datum/E)
	var/datum/controller/subsystem/S = subsystem()
	if(!S?.lane_resuming)
		return
	if(!S.run_lane_step())
		om_deadline(E, world.tick_lag, src)

