// Periodic work on object-model pipelines (doc/rewrite/object_model_core.md §4.10; roadmap S4).
//
// This replaces the polling processing subsystems (SSobj, SSprocessing, SSfastprocess, SSturfs,
// SSburning, SSprojectiles, SSinstruments, SSpriority_effects, SSobj_tab_items). A datum with
// periodic work defines periodic_step(delta) -- the body its old process() had -- and is woken
// onto one of the pipelines below with PERIODIC_START(E, pipeline). Its stage runs every frame of
// that pipeline while it has work; periodic_step() returning PROCESS_KILL, or PERIODIC_STOP(E),
// idles the stage and the entity parks (off the ring, costing nothing) until the next
// PERIODIC_START. That call is the type's wake rule: whatever made the work possible (lighting a
// cigarette, arming a grenade, a mob stepping on a trap) starts it; the work itself says when it
// is done.
//
// The idle rule is exact: a stage is idle iff its entity is not started on its pipeline
// (E.periodic_pipe), so the OM missed-wake audit reports an entity that was started but parked.
//
// Cadence pipelines, by what they used to replace:
//   /datum/om/pipeline/periodic/slow     every 2 s   (SSobj, SSturfs)          periodic_step(20)
//   /datum/om/pipeline/periodic/second   every 1 s   (SSprocessing, SSburning) periodic_step(10)
//   /datum/om/pipeline/periodic/fast     every 0.2 s (SSfastprocess)           periodic_step(2)
// Declared continuous lanes (each says why it must tick at frame rate):
//   /datum/om/pipeline/periodic/continuous/projectiles, .../instruments, .../status_effects,
//   .../tab_items

/// The pipeline `E` is started on (a /datum/om/pipeline/periodic type), or null when it has no
/// periodic work. DF_ISPROCESSING mirrors it for code that only asks "is this running".
/datum/var/tmp/periodic_pipe

/proc/periodic_start(datum/E, P)
	if(!E || QDELETED(E))
		return FALSE
	if(E.periodic_pipe == P)
		return TRUE
	E.periodic_pipe = P
	E.datum_flags |= DF_ISPROCESSING
	if(om_attached(E, P))
		om_wake(E, P)
	else
		om_attach(E, P)
	return TRUE

/proc/periodic_stop(datum/E)
	if(!E)
		return
	E.periodic_pipe = null
	E.datum_flags &= ~DF_ISPROCESSING

/// One frame of periodic work: the body a process() override used to have. `delta` is the
/// pipeline's nominal step in the units the old subsystem passed (deciseconds for most; see the
/// table above). Return PROCESS_KILL when there is nothing left to do until the next
/// PERIODIC_START. Like the old process(), a body that sleeps doesn't hold up the frame.
/datum/proc/periodic_step(delta)
	set waitfor = FALSE
	return PROCESS_KILL

/// What the subsystems that still own their own schedule call on their datums (SSevents,
/// SSplanets, SSshuttles, SSticker's game mode, tgui windows, database queries). Nothing on a
/// periodic lane uses it (tools/ci/pollers_lint.py counts the overrides).
/datum/proc/process()
	set waitfor = FALSE
	return PROCESS_KILL

// ---------------------------------------------------------------- pipelines

/datum/om/pipeline/periodic
	abstract_type = /datum/om/pipeline/periodic
	lane = LANE_SIMULATION
	runlevels = RUNLEVELS_DEFAULT
	wake_all = CHANGE_EXPLICIT
	/// What periodic_step() receives each frame.
	var/delta = 0
	/// Continuous lanes only: why this work has to tick at (near) frame rate.
	var/continuous_why

/datum/om/pipeline/periodic/slow
	name = "periodic (2 s)"
	every = 2 SECONDS
	delta = 20
	stages = list(/datum/om/stage/periodic/slow)

/datum/om/pipeline/periodic/second
	name = "periodic (1 s)"
	every = 1 SECOND
	delta = 10
	stages = list(/datum/om/stage/periodic/second)

/datum/om/pipeline/periodic/fast
	name = "periodic (0.2 s)"
	every = 2
	delta = 2
	stages = list(/datum/om/stage/periodic/fast)

/// Declared continuous lanes: movement and audio that visibly stutter at a coarser cadence.
/datum/om/pipeline/periodic/continuous
	abstract_type = /datum/om/pipeline/periodic/continuous
	lane = LANE_URGENT

/datum/om/pipeline/periodic/continuous/projectiles
	name = "continuous: projectiles"
	continuous_why = "a projectile moves in pixel steps every server tick; a coarser cadence changes its speed and hit timing"
	every = 0.1 // below one tick: every tick
	delta = 1
	stages = list(/datum/om/stage/periodic/projectiles)

/datum/om/pipeline/periodic/continuous/instruments
	name = "continuous: instruments"
	continuous_why = "a playing song schedules its notes at sub-tenth-second resolution"
	every = 0.5
	delta = 0.5
	stages = list(/datum/om/stage/periodic/instruments)

/datum/om/pipeline/periodic/continuous/status_effects
	name = "continuous: priority status effects"
	continuous_why = "priority status effects (movement-affecting ones) tick every other server tick"
	every = 0.5
	delta = 2
	stages = list(/datum/om/stage/periodic/status_effects)

/datum/om/pipeline/periodic/continuous/tab_items
	name = "continuous: stat tab items"
	continuous_why = "stat-panel items refresh at 10 Hz for the viewer, lobby included"
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	every = 1
	delta = 0.1
	stages = list(/datum/om/stage/periodic/tab_items)

// ---------------------------------------------------------------- the stage

/// One stage per pipeline (a stage's position belongs to one pipeline); all share this body.
/datum/om/stage/periodic
	category = /datum/om/stage/periodic
	name = "periodic step"
	woken_by = "PERIODIC_START()"

/datum/om/stage/periodic/perform(datum/E, datum/om/frame/F)
	if(E.periodic_pipe != pipeline)
		return STAGE_IDLE
	var/datum/om/pipeline/periodic/P = F.pipeline
	if(E.periodic_step(P.delta) == PROCESS_KILL && E.periodic_pipe == pipeline)
		periodic_stop(E)
	if(E.periodic_pipe != pipeline)
		return STAGE_IDLE

/datum/om/stage/periodic/idle(datum/E)
	return E.periodic_pipe != pipeline

/datum/om/stage/periodic/slow
	pipeline = /datum/om/pipeline/periodic/slow

/datum/om/stage/periodic/second
	pipeline = /datum/om/pipeline/periodic/second

/datum/om/stage/periodic/fast
	pipeline = /datum/om/pipeline/periodic/fast

/datum/om/stage/periodic/projectiles
	pipeline = /datum/om/pipeline/periodic/continuous/projectiles

/datum/om/stage/periodic/instruments
	pipeline = /datum/om/pipeline/periodic/continuous/instruments

/datum/om/stage/periodic/status_effects
	pipeline = /datum/om/pipeline/periodic/continuous/status_effects

/datum/om/stage/periodic/tab_items
	pipeline = /datum/om/pipeline/periodic/continuous/tab_items

/// Profiler counts: entities parked on each periodic pipeline.
/proc/periodic_diagnostics()
	. = list()
	for(var/P in subtypesof(/datum/om/pipeline/periodic))
		var/datum/om/pipeline/periodic/def = P
		if(initial(def.abstract_type) == P)
			continue
		.["[initial(def.name)]"] = list("parked" = om_pipeline_parked_count(P))
