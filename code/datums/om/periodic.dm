// Periodic work on the kernel (doc/rewrite/scheduling_and_kernel.md; roadmap S4).
//
// This replaces the polling processing subsystems (SSobj, SSprocessing, SSfastprocess, SSturfs,
// SSburning, SSprojectiles, SSinstruments, SSpriority_effects, SSobj_tab_items). A datum with
// periodic work defines periodic_step(delta) -- the body its old process() had -- and is started on
// one of the cadences below with om_task_periodic(E, cadence). Its membership of that cadence IS the
// work: the kernel sweeps the cadence's members every interval (one work item per cadence, phase P,
// on the cadence's lane), calling periodic_step(). periodic_step() returning PROCESS_KILL, or
// om_task_periodic_stop(E), ends the membership and the entity costs nothing until the next
// om_task_periodic(). That call is the type's wake rule: whatever made the work possible (lighting a
// cigarette, arming a grenade, a mob stepping on a trap) starts it; the work itself says when it
// is done.
//
// A cadence used to be an object-model pipeline with one stage. It is a plain definition now: the work item
// (/datum/work_item/cadence, the stage adapter's successor) carries the old stage body in perform(), and
// membership replaces the ring, parking and the idle bits. The rule stays exact: a member is stepped iff its
// entity is started on that cadence (E.periodic_pipe).
//
// Cadences, by what they used to replace:
//   /datum/cadence/slow       every 2 s   (SSobj, SSturfs)          periodic_step(20)
//   /datum/cadence/second     every 1 s   (SSprocessing, SSburning) periodic_step(10)
//   /datum/cadence/fast       every 0.2 s (SSfastprocess)           periodic_step(2)
//   /datum/cadence/plants     every 7.5 s (SSplants' vines)         periodic_step(75)
//   /datum/cadence/reflectors every 0.5 s (SSreflector; machine clock) periodic_step(5)
//   /datum/cadence/loot_icons every 0.5 s (SSlooting)               periodic_step(5)
// Also on the slow lane now: alarm handlers, random events and their containers, working
// shuttles, the game mode and planets (their subsystems schedule nothing any more).
// Declared continuous lanes (each says why it must tick at frame rate):
//   /datum/cadence/continuous/projectiles, .../throwing, .../instruments, .../status_effects, .../tab_items

/// The cadence `E` is started on (a /datum/cadence type), or null when it has no periodic work.
/// DF_ISPROCESSING mirrors it for code that only asks "is this running".
/datum/var/tmp/periodic_pipe

/proc/_om_periodic_start(datum/E, P)
	if(!E || QDELETED(E))
		return FALSE
	if(E.periodic_pipe == P)
		return TRUE
	// A DECLARE_PERIODIC_WHILE on this cadence whose state doesn't hold refuses (code/datums/sys/periodic.dm).
	if(!sys_periodic_allows(E, P))
		return FALSE
	// So does a type whose periodic work is a gated type-level every(when = ...) none of whose gates holds.
	if(!sys_every_allows(E))
		return FALSE
	// Moving to another cadence leaves the first one.
	if(E.periodic_pipe)
		member_leave(E.periodic_pipe, E, PERIODIC_SOURCE)
	E.periodic_pipe = P
	E.datum_flags |= DF_ISPROCESSING
	member_join(P, E, PERIODIC_SOURCE)
	return TRUE

/proc/_om_periodic_stop(datum/E)
	if(!E)
		return
	if(E.periodic_pipe)
		member_leave(E.periodic_pipe, E, PERIODIC_SOURCE)
	E.periodic_pipe = null
	E.datum_flags &= ~DF_ISPROCESSING

/// One frame of periodic work: the body a process() override used to have. `delta` is the
/// cadence's nominal step in the units the old subsystem passed (deciseconds for most; see the
/// table above). Return PROCESS_KILL when there is nothing left to do until the next
/// om_task_periodic(). Like the old process(), a body that sleeps doesn't hold up the frame.
/datum/proc/periodic_step(delta)
	set waitfor = FALSE // ALLOW(scheduler): core dispatch hook: guards the frame against a periodic_step() override that still sleeps
	return PROCESS_KILL

/// The core's own per-datum hook, kept for tgui windows and database queries (SStgui, SSdbcore).
/// No gameplay type defines it any more (tools/ci/pollers_lint.py counts the overrides).
/datum/proc/process()
	return PROCESS_KILL

// ---------------------------------------------------------------- cadences

/// A periodic cadence: how often its members step, what they are told the step was, and the lane that pays for it.
/datum/cadence
	abstract_type = /datum/cadence
	var/name
	/// Deciseconds between sweeps. Below one tick: every tick.
	var/every = 0
	/// What periodic_step() receives each step.
	var/delta = 0
	var/lane = LANE_SIMULATION
	/// RUNLEVEL_* bits the cadence sweeps in.
	var/runlevels = RUNLEVELS_DEFAULT
	/// CLOCK_WORLD, or CLOCK_BIO (stasis slows or stops the member's steps).
	var/clock = CLOCK_WORLD
	/// Continuous lanes only: why this work has to tick at (near) frame rate.
	var/continuous_why

/datum/cadence/slow
	name = "periodic (2 s)"
	every = 2 SECONDS
	delta = 20

/datum/cadence/second
	name = "periodic (1 s)"
	every = 1 SECOND
	delta = 10

/// Every minute: slow housekeeping that has no reason to run more often.
/datum/cadence/minute
	name = "periodic (1 min)"
	every = 1 MINUTES
	delta = 600

/// Spreading plants (was SSplants' loop): one growth step every 7.5 s while a vine can grow.
/datum/cadence/plants
	name = "periodic (plants, 7.5 s)"
	every = 7.5 SECONDS
	delta = 75

/// Reflectors (was SSreflector, 0.5 s): a reflector re-fires the beams it caught. It starts when
/// it catches one (redirect_projectile()) and stops once it has fired.
/datum/cadence/reflectors
	name = "periodic (reflectors, 0.5 s)"
	every = 0.5 SECONDS
	delta = 5

/// Loot panel icon generation (was SSlooting, 0.5 s): a panel with icons left to draw starts here and
/// stops when its queue is empty. Lobby included, like the subsystem.
/datum/cadence/loot_icons
	name = "periodic (loot icons, 0.5 s)"
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	every = 0.5 SECONDS
	delta = 5

/datum/cadence/fast
	name = "periodic (0.2 s)"
	every = 2
	delta = 2

/// Declared continuous lanes: movement and audio that visibly stutter at a coarser cadence.
/datum/cadence/continuous
	abstract_type = /datum/cadence/continuous
	lane = LANE_URGENT

/datum/cadence/continuous/projectiles
	name = "continuous: projectiles"
	continuous_why = "a projectile moves in pixel steps every server tick; a coarser cadence changes its speed and hit timing"
	every = 0.1 // below one tick: every tick
	delta = 1

/datum/cadence/continuous/throwing
	name = "continuous: throwing"
	continuous_why = "a thrown atom moves `speed` tiles per server tick; a coarser cadence changes its flight and hit timing"
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	every = 0.1 // below one tick: every tick
	delta = 1

/datum/cadence/continuous/instruments
	name = "continuous: instruments"
	continuous_why = "a playing song schedules its notes at sub-tenth-second resolution"
	every = 0.5
	delta = 0.5

/datum/cadence/continuous/status_effects
	name = "continuous: priority status effects"
	continuous_why = "priority status effects (movement-affecting ones) tick every other server tick"
	every = 0.5
	delta = 2

/datum/cadence/continuous/tab_items
	name = "continuous: stat tab items"
	continuous_why = "stat-panel items refresh at 10 Hz for the viewer, lobby included"
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	every = 1
	delta = 0.1

/// The shared definition of a cadence type (one instance per type, never written).
/proc/cadence_def(path)
	RETURN_TYPE(/datum/cadence)
	// A memoized per-type table built once on first call
	var/static/list/defs = list()
	var/datum/cadence/C = defs[path]
	if(!C)
		C = new path
		defs[path] = C
	return C

/// Every concrete cadence type.
/proc/cadence_types()
	. = list()
	for(var/path in subtypesof(/datum/cadence))
		if(!is_abstract(path))
			. += path

// ---------------------------------------------------------------- the work item

/// One cadence's sweep, on the kernel: runs periodic_step() on every member of the cadence, in join order, once per
/// `every`, spread across the interval (run_item_spread()). The stage adapter for the periodic stage: it owns itself (no system), asks the old stage's questions
/// (is the entity still started here, is a yielded step pending) and does its work (the step, its result, the
/// derived mark).
/datum/work_item/cadence
	/// The cadence type; also the membership key.
	var/datum/cadence/def

/datum/work_item/cadence/New(path)
	def = cadence_def(path)
	..("periodic_step", def.every, null, path, KERNEL_PHASE_P, null, 0, def.lane, FALSE, def.clock)
	name = def.name
	// A cadence slower than the tick spreads its sweep across the interval, as the old ring did: each member keeps its
	// phase, and a big cadence costs a slice per tick instead of a spike once per interval.
	spread = def.every > world.tick_lag

/datum/work_item/cadence/owner()
	return src

/// The cadence sweeps only in its run levels.
/datum/work_item/cadence/admitted_now()
	return !!(def.runlevels & (1 << (Kernel.current_runlevel - 1)))

/// The old stage's idle rule, inverted: a member runs iff its entity is started on this cadence and no yielded step
/// is waiting to resume (periodic_step_result()).
/datum/work_item/cadence/runnable(datum/owner, datum/member)
	if(!member)
		return TRUE
	if(member.periodic_pipe != members)
		return FALSE
	return !om_timer_slot_pending(member, "step_yield")

/// The old stage's perform().
/datum/work_item/cadence/perform(datum/owner, datum/member, dt)
	var/datum/E = member
	if(!E || E.periodic_pipe != members)
		return STEP_DONE
	if(periodic_step_result(E, E.periodic_step(def.delta), def.delta) && E.periodic_pipe == members)
		_om_periodic_stop(E)
	// A step on a should_run() type is a dispatched call (dx_conventions.md §1): its derived procs re-run.
	// A type that declares its dependencies needs no blanket mark: what it reads is written through
	// tracked setters, which mark exactly the outputs that read it.
	if(E.periodic_cadence && !derived_is_exact(E))
		refresh_dispatched(E)
	return STEP_DONE

/// Registers a work item per cadence with the kernel. Called when the kernel is created.
/proc/kernel_register_cadences(datum/controller/kernel/K)
	for(var/path in cadence_types())
		var/datum/work_item/cadence/W = new(path)
		K.register_work(path, W)
		K.cadence_items[path] = W

/// Steps `E` once on cadence `P` now, whatever the clock says (content that must see a step at once, and tests). The
/// same questions and work as a sweep. Returns TRUE when it stepped.
/proc/periodic_run_now(datum/E, P)
	var/datum/work_item/cadence/W = kernel().cadence_items[P]
	if(!W || !W.runnable(W, E))
		return FALSE
	W.perform(W, E, W.def.delta)
	return TRUE

/// Profiler counts: members on each periodic cadence.
/proc/periodic_diagnostics()
	. = list()
	for(var/P in cadence_types())
		var/datum/cadence/def = cadence_def(P)
		.["[def.name]"] = list("members" = members_total(P))

/// A timer target that restarts periodic work on the slow lane (om_after(src, delay, /datum/proc/periodic_resume)).
/datum/proc/periodic_resume()
	om_task_periodic(src, PERIODIC_SLOW)

/// A mob moved into a chunk a proximity-gated sleeper watches (sleep_until_mob_near(), code/modules/mob/mob_chunks.dm): its
/// periodic work restarts on its lane.
/atom/movable/proc/proximity_woke(datum/mob_chunk/C, bits)
	if(QDELETED(src) || !proximity_chunks)
		return
	proximity_chunks = unwatch_mob_chunks(src, proximity_chunks, proximity_mask)
	om_task_periodic(src, proximity_lane)
