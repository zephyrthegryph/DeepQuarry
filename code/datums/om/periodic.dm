// Periodic work on object-model pipelines (doc/rewrite/object_model_core.md §4.10; roadmap S4).
//
// This replaces the polling processing subsystems (SSobj, SSprocessing, SSfastprocess, SSturfs,
// SSburning, SSprojectiles, SSinstruments, SSpriority_effects, SSobj_tab_items). A datum with
// periodic work defines periodic_step(delta) -- the body its old process() had -- and is woken
// onto one of the pipelines below with om_task_periodic(E, pipeline). Its stage runs every frame of
// that pipeline while it has work; periodic_step() returning PROCESS_KILL, or om_task_periodic_stop(E),
// idles the stage and the entity parks (off the ring, costing nothing) until the next
// om_task_periodic(). That call is the type's wake rule: whatever made the work possible (lighting a
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
//   /datum/om/pipeline/periodic/plants   every 7.5 s (SSplants' vines)          periodic_step(75)
//   /datum/om/pipeline/periodic/reflectors every 0.5 s (SSreflector; machine clock) periodic_step(5)
//   /datum/om/pipeline/periodic/loot_icons every 0.5 s (SSlooting)            periodic_step(5)
// Also on the slow lane now: alarm handlers, random events and their containers, working
// shuttles, the game mode and planets (their subsystems schedule nothing any more).
// Declared continuous lanes (each says why it must tick at frame rate):
//   /datum/om/pipeline/periodic/continuous/projectiles, .../throwing, .../instruments, .../status_effects,
//   .../tab_items

/// The pipeline `E` is started on (a /datum/om/pipeline/periodic type), or null when it has no
/// periodic work. DF_ISPROCESSING mirrors it for code that only asks "is this running".
/datum/var/tmp/periodic_pipe

/proc/_om_periodic_start(datum/E, P)
	if(!E || QDELETED(E))
		return FALSE
	if(E.periodic_pipe == P)
		return TRUE
	// A DECLARE_PERIODIC_WHILE on this cadence whose state doesn't hold refuses (code/datums/sys/periodic.dm).
	if(!sys_periodic_allows(E, P))
		return FALSE
	E.periodic_pipe = P
	E.datum_flags |= DF_ISPROCESSING
	if(om_attached(E, P))
		om_wake(E, P)
	else
		om_attach(E, P)
	return TRUE

/proc/_om_periodic_stop(datum/E)
	if(!E)
		return
	E.periodic_pipe = null
	E.datum_flags &= ~DF_ISPROCESSING

/// One frame of periodic work: the body a process() override used to have. `delta` is the
/// pipeline's nominal step in the units the old subsystem passed (deciseconds for most; see the
/// table above). Return PROCESS_KILL when there is nothing left to do until the next
/// om_task_periodic(). Like the old process(), a body that sleeps doesn't hold up the frame.
/datum/proc/periodic_step(delta)
	set waitfor = FALSE // ALLOW(scheduler): core dispatch hook: guards the frame against a periodic_step() override that still sleeps
	return PROCESS_KILL

/// The core's own per-datum hook, kept for tgui windows and database queries (SStgui, SSdbcore).
/// No gameplay type defines it any more (tools/ci/pollers_lint.py counts the overrides).
/datum/proc/process()
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

/// Spreading plants (was SSplants' loop): one growth step every 7.5 s while a vine can grow.
/datum/om/pipeline/periodic/plants
	name = "periodic (plants, 7.5 s)"
	every = 7.5 SECONDS
	delta = 75
	stages = list(/datum/om/stage/periodic/plants)

/// Reflectors (was SSreflector, 0.5 s): a reflector re-fires the beams it caught. It starts when
/// it catches one (redirect_projectile()) and parks once it has fired. Clocked, so stasis and
/// machine-clock effects pause it.
/datum/om/pipeline/periodic/reflectors
	name = "periodic (reflectors, 0.5 s)"
	every = 0.5 SECONDS
	delta = 5
	clock = CLOCK_MACHINE
	stages = list(/datum/om/stage/periodic/reflectors)

/// Loot panel icon generation (was SSlooting, 0.5 s): a panel with icons left to draw starts here and
/// parks when its queue is empty. Lobby included, like the subsystem.
/datum/om/pipeline/periodic/loot_icons
	name = "periodic (loot icons, 0.5 s)"
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	every = 0.5 SECONDS
	delta = 5
	stages = list(/datum/om/stage/periodic/loot_icons)

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

/datum/om/pipeline/periodic/continuous/throwing
	name = "continuous: throwing"
	continuous_why = "a thrown atom moves `speed` tiles per server tick; a coarser cadence changes its flight and hit timing"
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	every = 0.1 // below one tick: every tick
	delta = 1
	stages = list(/datum/om/stage/periodic/throwing)

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
	woken_by = "om_task_periodic()"

/datum/om/stage/periodic/perform(datum/E, datum/om/frame/F)
	if(E.periodic_pipe != pipeline)
		return STAGE_IDLE
	var/datum/om/pipeline/periodic/P = F.pipeline
	if(E.periodic_step(P.delta) == PROCESS_KILL && E.periodic_pipe == pipeline)
		_om_periodic_stop(E)
	// A step on a should_run() type is a dispatched call (dx_conventions.md §1): its derived procs re-run.
	// A type that declares its dependencies needs no blanket mark: what it reads is written through
	// tracked setters, which mark exactly the outputs that read it.
	if(E.periodic_cadence && !derived_is_exact(E))
		changed(E)
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

/datum/om/stage/periodic/plants
	pipeline = /datum/om/pipeline/periodic/plants

/datum/om/stage/periodic/projectiles
	pipeline = /datum/om/pipeline/periodic/continuous/projectiles

/datum/om/stage/periodic/throwing
	pipeline = /datum/om/pipeline/periodic/continuous/throwing

/datum/om/stage/periodic/reflectors
	pipeline = /datum/om/pipeline/periodic/reflectors

/datum/om/stage/periodic/loot_icons
	pipeline = /datum/om/pipeline/periodic/loot_icons

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



/// A timer target that restarts periodic work on the slow lane (om_after(src, delay, /datum/proc/periodic_resume)).
/datum/proc/periodic_resume()
	om_task_periodic(src, PERIODIC_SLOW)
