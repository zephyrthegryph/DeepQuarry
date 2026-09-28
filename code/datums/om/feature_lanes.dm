// Feature subsystems on the object-model scheduler (doc/rewrite/completion_plan.md §3.6).
//
// These subsystems stay as named services (SSvote, SSsupply, ...) holding their state and procs,
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
		/datum/om/behaviour/world/feature/character_setup,
		/datum/om/behaviour/world/feature/lobby_monitor,
		/datum/om/behaviour/world/feature/player_tips,
		/datum/om/behaviour/world/feature/vote,
		/datum/om/behaviour/world/feature/persist,
		/datum/om/behaviour/world/feature/research,
		/datum/om/behaviour/world/feature/supply,
		/datum/om/behaviour/world/feature/transcore,
		/datum/om/behaviour/world/feature/emergency_shuttle,
		/datum/om/behaviour/world/feature/expedition,
		/datum/om/behaviour/world/feature/flight_operations,
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

/// Preference save queue (was SScharacter_setup, 1 s, background).
/datum/om/behaviour/world/feature/character_setup
	name = "feature: character setup"
	every = 1 SECOND
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/feature/character_setup/subsystem()
	return SScharacter_setup

/// Lobby window watchdog (was SSlobby_monitor, 2 s, every runlevel).
/datum/om/behaviour/world/feature/lobby_monitor
	name = "feature: lobby monitor"
	every = 2 SECONDS
	runlevels = 0

/datum/om/behaviour/world/feature/lobby_monitor/subsystem()
	return SSlobby_monitor

/// Periodic player tips (was SSplayer_tips, 5 min).
/datum/om/behaviour/world/feature/player_tips
	name = "feature: player tips"
	every = 5 MINUTES
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/feature/player_tips/subsystem()
	return SSplayer_tips

/// Active vote countdown (was SSvote, 1 s).
/datum/om/behaviour/world/feature/vote
	name = "feature: vote"
	every = 1 SECOND
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/feature/vote/subsystem()
	return SSvote

/// PTO / playtime accrual (was SSpersist, 15 min, background).
/datum/om/behaviour/world/feature/persist
	name = "feature: persist"
	every = 15 MINUTES
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

/datum/om/behaviour/world/feature/persist/subsystem()
	return SSpersist

/// Techweb point income and research queue (was SSresearch, 1 s).
/datum/om/behaviour/world/feature/research
	name = "feature: research"
	every = 1 SECOND

/datum/om/behaviour/world/feature/research/subsystem()
	return SSresearch

/// Cargo market and department payroll (was SSsupply, 20 s).
/datum/om/behaviour/world/feature/supply
	name = "feature: supply"
	every = 20 SECONDS

/datum/om/behaviour/world/feature/supply/subsystem()
	return SSsupply

/// Resleeving implant scan and backup staleness (was SStranscore, 3 min, background).
/datum/om/behaviour/world/feature/transcore
	name = "feature: transcore"
	every = 3 MINUTES
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/feature/transcore/subsystem()
	return SStranscore

/// Emergency shuttle launch countdown and escape pods (was SSemergency_shuttle, 1 s).
/datum/om/behaviour/world/feature/emergency_shuttle
	name = "feature: emergency shuttle"
	every = 1 SECOND
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/feature/emergency_shuttle/subsystem()
	return SSemergency_shuttle

/// Expedition mission polling and site release (was SSexpedition, 2 s).
/datum/om/behaviour/world/feature/expedition
	name = "feature: expedition"
	every = 2 SECONDS

/datum/om/behaviour/world/feature/expedition/subsystem()
	return SSexpedition

/// Flight plan processing (was SSflight_operations, 1 s).
/datum/om/behaviour/world/feature/flight_operations
	name = "feature: flight operations"
	every = 1 SECOND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

/datum/om/behaviour/world/feature/flight_operations/subsystem()
	return SSflight_operations
