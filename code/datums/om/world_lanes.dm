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
	parent_type = /datum/system
	name = "world service"
	abstract_type = /datum/world_service
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
	// `initialized` (kernel/system.dm): TRUE once initialize() has run. A lazy (data-only) service
	// initializes on first use through LAZY_SERVICE(); initialize() sets it first so a re-entrant
	// lookup doesn't recurse.
	/// On-demand lane: parked while has_work() is FALSE, unparked by demand() when work is queued
	/// (a cascade, an explosion, a star move). Idle services then cost the scheduler nothing.
	var/on_demand = FALSE
	// Boot slot: `needs` (kernel/system.dm) names the subsystems and services that must initialize before
	// this one; the boot DAG initializes it right after them. No needs: lazy (LAZY_SERVICE()) or
	// initialized by its owner.

/// One-time setup, called by whatever used to be this service's Initialize() dependency slot, or
/// on first use by ready() for a lazy service. Overrides set `initialized = TRUE` first.
/datum/world_service/initialize()
	initialized = TRUE

/// Server shutdown (MC Shutdown(), after the subsystems): flush whatever must survive the round.
/datum/world_service/on_shutdown()
	return

/// Only a service that declares `needs` boots in the DAG; the rest are lazy or initialized by their owner.
/datum/world_service/boots_in_dag()
	return length(needs) > 0

/// MC shutdown hook.
/proc/shutdown_world_services()
	for(var/datum/world_service/S as anything in world_services())
		if(S.initialized)
			log_world("Shutting down [S.name] world service...")
			S.on_shutdown()

/// Lazy services: initializes on first use and returns the service (LAZY_SERVICE() in __defines/om.dm).
/datum/world_service/proc/ready()
	RETURN_TYPE(/datum/world_service)
	if(!initialized)
		var/started = REALTIMEOFDAY
		initialize()
		log_world("World service [name] initialized lazily in [(REALTIMEOFDAY - started) / 10]s.")
	return src

/// World-level periodic work. `resumed`: continuing a step that yielded. Return FALSE to yield
/// (the lane resumes next tick), TRUE when the step is complete.
/datum/world_service/proc/service_step(resumed)
	SHOULD_NOT_SLEEP(TRUE)
	return TRUE

/// On-demand services: TRUE while there is queued work for the lane.
/datum/world_service/proc/has_work()
	return TRUE

/// On-demand services: call after queueing work; wakes the lane if it was parked. `now`: also run a
/// step at the scheduler's next drain instead of waiting for the lane's next cadence frame.
/datum/world_service/proc/demand(now = FALSE)
	if(!lane)
		return
	var/datum/om/global_owner/owner = om_global_owner()
	if(owner && om_attached(owner, lane))
		om_unpark(owner, lane)
		if(now)
			om_wake(owner, lane)

/// Telemetry (kernel/system.dm metrics()): the cost counters the profiler and the stat panel read.
/datum/world_service/metrics()
	return alist("name" = name, "members" = member_count(), "initialized" = initialized, "total_ms" = total_ms, "steps" = steps, "cost" = cost, "tick_usage" = current_ms, "overran" = resuming, "reactions" = kernel().work_cost_of(type))

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

/// Every world service, for the profiler and the admin readouts, in registration order. Derived from the system
/// registry (system_table()): a service registers itself when its singleton is created, so there is no hand-kept list.
/proc/world_services()
	. = list()
	var/list/table = system_table()
	for(var/path in table)
		if(ispath(path, /datum/world_service))
			. += table[path]
	return .

/// Attaches every world service's lane to the live scheduler's global owner (SSbehaviours init).
/proc/_om_start_world_lanes()
	var/datum/om/global_owner/owner = om_global_owner()
	for(var/datum/world_service/S as anything in world_services())
		if(!S?.lane)
			continue
		if(!om_attached(owner, S.lane))
			om_attach(owner, S.lane)
		if(S.on_demand && !S.has_work())
			om_park(owner, S.lane)
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
	else if(S.on_demand && !S.has_work())
		om_park(E, src)

/// demand(now = TRUE): run a step at the next drain.
/datum/om/behaviour/world/on_wake(datum/E, changes)
	if(changes & CHANGE_EXPLICIT)
		tick(E, 0)

/// A yielded step resumes here, one tick later.
/datum/om/behaviour/world/on_deadline(datum/E)
	var/datum/world_service/S = service()
	if(!S?.resuming)
		return
	if(!S.run_step())
		om_deadline(E, world.tick_lag, src)
	else if(S.on_demand && !S.has_work())
		om_park(E, src)

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

// ---------------------------------------------------------------- fold wave F3 lanes

/// Radiation pulse queue and the shielding flush to the Rust insulation layer (was SSradiation, 0.5 s).
/datum/om/behaviour/world/radiation
	name = "world: radiation"
	every = 0.5 SECONDS
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/radiation/service()
	return GLOB.radiation_service

/// Motion tracker echo drawing (was SSmotiontracker, 1 s).
/datum/om/behaviour/world/motiontracker
	name = "world: motion tracker"
	every = 1 SECOND

/datum/om/behaviour/world/motiontracker/service()
	return GLOB.motiontracker_service

/// pAI candidate list refresh from the observers (was SSpai, 4 s).
/datum/om/behaviour/world/pai
	name = "world: pai candidates"
	every = 4 SECONDS
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/pai/service()
	return GLOB.pai_service

/// Mail accrual for the supply shuttle (was SSmail, 60 s).
/datum/om/behaviour/world/mail
	name = "world: mail"
	every = 60 SECONDS
	lane = LANE_BACKGROUND
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/mail/service()
	return GLOB.mail_service

// ---------------------------------------------------------------- fold wave F4 lanes

/// Sun position and the solar controllers and panels (was SSsun + SSsolars, 1 min).
/datum/om/behaviour/world/solars
	name = "world: solars"
	every = 1 MINUTE

/datum/om/behaviour/world/solars/service()
	return GLOB.solar_service

/// Night shift lighting (was SSnightshift, 60 s).
/datum/om/behaviour/world/nightshift
	name = "world: night shift"
	every = 60 SECONDS
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/nightshift/service()
	return GLOB.nightshift_service

/// Planet sunlight and wall temperatures the planets queued (was SSplanets, 2 s). On demand.
/datum/om/behaviour/world/planets
	name = "world: planets"
	every = 2 SECONDS
	lane = LANE_BACKGROUND

/datum/om/behaviour/world/planets/service()
	return GLOB.planet_service

/// Mid-round POI placement (was SSpoints_of_interest, 1 s). On demand; runs in the lobby too.
/datum/om/behaviour/world/pois
	name = "world: points of interest"
	every = 1 SECOND
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/pois/service()
	return GLOB.poi_service

/// Star movement behind moving overmap ships (was SSstarmover, every tick). On demand.
/datum/om/behaviour/world/starmover
	name = "world: star movement"
	every = 1
	runlevels = RUNLEVELS_DEFAULT

/datum/om/behaviour/world/starmover/service()
	return GLOB.starmover_service

/// A spreading turf conversion (was SSturf_cascade, 0.2 s). On demand.
/datum/om/behaviour/world/turf_cascade
	name = "world: turf cascade"
	every = 2

/datum/om/behaviour/world/turf_cascade/service()
	return GLOB.turf_cascade_service

/// Explosion epochs (was SSexplosions, 0.5 s). On demand; explosion() wakes it at once.
/datum/om/behaviour/world/explosions
	name = "world: explosions"
	every = 0.5 SECONDS

/datum/om/behaviour/world/explosions/service()
	return GLOB.explosion_service

/// AFK kicks (was SSinactivity, 1 min).
/datum/om/behaviour/world/inactivity
	name = "world: inactivity"
	every = 1 MINUTE
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/inactivity/service()
	return GLOB.inactivity_service

/// Automatic crew transfer votes and the shift's hard end (was SStransfer, 1 s).
/datum/om/behaviour/world/transfer
	name = "world: crew transfer"
	every = 1 SECOND
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/transfer/service()
	return GLOB.transfer_service
