// World services on the object-model scheduler (doc/rewrite/completion_plan.md §3.6, fold wave F1).
//
// A world service is the global state a former subsystem held (the machine power and pump queues,
// the death report queue, the seed tables), kept on a singleton /datum/world_service in GLOB. Its
// world-level periodic work is a cadence behaviour attached to the scheduler's global owner
// (om_global_owner(), timer.dm), so SSbehaviours runs it inside its lane budget: there is no
// subsystem fire() loop. Per-object work stays on the entities' own pipelines (machines, Life,
// periodic lanes); this is only what belongs to no entity.
//
// A lane's step may yield (a long gas wake batch): it returns FALSE and the lane resumes on the
// next tick through a one-tick deadline, instead of waiting for its next cadence frame.

/datum/world_service
	var/name = "world service"
	/// The /datum/om/behaviour/world type that runs step(), or null for a data-only service.
	var/lane
	/// Milliseconds spent in service_step() since boot, and the number of completed steps.
	var/total_ms = 0
	var/steps = 0
	/// EMA of one completed step's cost (all resumed slices combined), ms.
	var/cost = 0
	/// In-flight step accumulator; survives yields.
	var/current_ms = 0
	/// TRUE while a yielded step is waiting to resume.
	var/resuming = FALSE

/// One-time setup, called by whatever used to be this service's Initialize() dependency slot.
/datum/world_service/proc/initialize()
	return

/// World-level periodic work. `resumed`: continuing a step that yielded. Return FALSE to yield
/// (the lane resumes next tick), TRUE when the step is complete.
/datum/world_service/proc/service_step(resumed)
	SHOULD_NOT_SLEEP(TRUE)
	return TRUE

/// One line for the admin status/profiler readouts (was the subsystem's stat_entry()).
/datum/world_service/proc/stat_line()
	return ""

/// Runs service_step() with the service's cost accounting. Returns what service_step() returned.
/datum/world_service/proc/run_step()
	SHOULD_NOT_SLEEP(TRUE)
	var/started = TICK_USAGE
	var/resumed = resuming
	if(!resumed)
		current_ms = 0
	var/done = service_step(resumed)
	var/ms = TICK_USAGE_TO_MS(started)
	total_ms += ms
	current_ms += ms
	resuming = !done
	if(done)
		steps++
		cost = MC_AVERAGE(cost, current_ms)
	return done

/// Every world service with a lane, for the profiler and the admin readouts.
/proc/world_services()
	return list(GLOB.machine_service, GLOB.mob_service, GLOB.plant_service)

/// Attaches every world service's lane to the live scheduler's global owner (SSbehaviours init).
/proc/om_start_world_lanes()
	var/datum/om/global_owner/owner = om_global_owner()
	for(var/datum/world_service/S as anything in world_services())
		if(!S?.lane)
			continue
		if(!om_attached(owner, S.lane))
			om_attach(owner, S.lane)
		log_world("OM world lane started: [S.name] ([S.lane])")

// ---------------------------------------------------------------- lanes

/// A world service's cadence on the global owner. `service` names the GLOB var of the service.
/datum/om/behaviour/world
	abstract_type = /datum/om/behaviour/world
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

/// The service whose service_step() this lane runs.
/datum/om/behaviour/world/proc/service()
	RETURN_TYPE(/datum/world_service)
	return null

/datum/om/behaviour/world/tick(datum/E, dt)
	var/datum/world_service/S = service()
	if(!S || S.resuming) // a yielded step owns the next tick's deadline
		return
	if(!S.run_step())
		om_deadline(E, world.tick_lag, src)

/// A yielded step resumes here, one tick later.
/datum/om/behaviour/world/on_deadline(datum/E)
	var/datum/world_service/S = service()
	if(!S?.resuming)
		return
	if(!S.run_step())
		om_deadline(E, world.tick_lag, src)

/// Gas watch dispatch, the batched pump commit and the power step (was SSmachines, 2 s).
/datum/om/behaviour/world/machines
	name = "world: machines"
	every = MACHINE_SERVICE_INTERVAL

/datum/om/behaviour/world/machines/service()
	return GLOB.machine_service

/// Death reports and the two-minute Life profile (was SSmobs, 2 s).
/datum/om/behaviour/world/mobs
	name = "world: mobs"
	every = 2 SECONDS

/datum/om/behaviour/world/mobs/service()
	return GLOB.mob_service
