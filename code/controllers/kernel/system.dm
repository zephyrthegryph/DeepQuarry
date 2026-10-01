/// A system: one self-contained part of the game (doc/rewrite/kernel.md sec 2.1). Plain DM: configuration is
/// type vars, behaviour is overrides. The kernel registers every non-abstract subtype once; a
/// /datum/world_service is a system whose singleton the GLOB machinery creates, and it registers itself.
/datum/system
	var/name = "system"
	// A type whose abstract_type equals its own path (/datum abstract_type, is_abstract()) is never
	// instantiated or registered by the kernel.
	abstract_type = /datum/system

	// ---- boot
	/// Nodes (subsystem or system typepaths) whose initialize() must have finished before ours. The boot DAG.
	var/list/needs
	/// TRUE once initialize() has run. A lazy (data-only) service initializes on first use.
	var/initialized = FALSE

	// ---- time
	// periodic_cadence (a CADENCE_* pipeline) and periodic_interval are /datum vars (capabilities/refresh.dm).
	/// RUNLEVEL_* bits the periodic step runs in, or 0 for the cadence's own runlevels.
	var/periodic_runlevels = 0
	/// The cadence (a CADENCE_* pipeline) for per-member work (member_step), or null for none.
	var/member_cadence = null
	/// TRUE while the system has parked itself (STEP_PARK, park_periodic()); wake_periodic() clears it. should_run()
	/// answers FALSE meanwhile, so the refresh that follows every step does not put it straight back.
	var/periodic_parked = FALSE
	/// The driver that steps the members on member_cadence (kernel-owned).
	var/datum/system_member_driver/member_driver
	/// The one place a system's latency class lives (LATENCY_L0..L3): what sheds its work under overload.
	var/latency_class = LATENCY_L1

	/// The init stage the system boots in at the earliest (INITSTAGE_*): a gameplay system converted from a subsystem keeps
	/// the stage it had. kernel_system_stage() takes the later of this and the stages of its subsystem needs.
	var/init_stage = INITSTAGE_FIRST

	// ---- the fire() shim (a gameplay system converted from a subsystem keeps its fire(resumed) body)
	/// FALSE parks the system's fire work (an admin toggle, an init that failed), as /datum/controller/subsystem can_fire.
	var/can_fire = TRUE
	/// Deciseconds between runs of a fire() body: the interval its every() declares (code that counts time per run reads it).
	var/wait = 20
	/// SS_* run state: fire() bodies test it through MC_TICK_CHECK, which pauses the run when the tick budget is spent.
	var/state = SS_IDLE
	/// TRUE while a fire() run paused and waits to be resumed (fire(resumed = TRUE)).
	var/fire_resumed = FALSE
	/// Completed fire() runs, the last one's world.time, and an EMA of one run's cost in ms.
	var/times_fired = 0
	var/last_fire = 0
	var/fire_cost = 0
	var/run_ms = 0
	/// Milliseconds initialize() took at boot (benchmarks).
	var/init_time_ms = 0
	/// Passes one completed run took (an EMA), and the tick share it ran past its budget (always 0: work is budgeted).
	var/ticks = 1
	var/tick_overrun = 0
	var/run_slices = 0

	// ---- contract
	/// Event types this system raises.
	var/list/emits

	// ---- members (kernel_join / kernel_leave; the store is controllers/kernel/membership.dm, MEMBER relations)
	/// TRUE once the boot pass has run on_members_ready(). Members joining before it wait for that pass.
	var/members_ready = FALSE

/// The table of registered systems, type -> instance. A static so a GLOBAL_DATUM_INIT service can
/// register during global init regardless of GLOB var order.
/proc/system_table()
	var/static/list/table = list()
	return table

/datum/system/New()
	..()
	if(type != abstract_type)
		var/list/table = system_table()
		if(!table[type])
			table[type] = src

/// TRUE when the kernel may instantiate `path` itself.
/proc/system_instantiable(path)
	if(!ispath(path, /datum/system))
		return FALSE
	return !is_abstract(path)

/// The singleton of a system type. A non-abstract pure system that does not exist yet is created.
/// Hot paths cache the result in a local.
/proc/system(path)
	var/list/table = system_table()
	. = table[path]
	if(!. && system_instantiable(path))
		. = new path
	return .

/// Every registered system, in registry order: the pure systems in subtypesof() order, then the
/// world services that registered themselves. Pure systems are created here when missing.
/proc/kernel_systems()
	. = list()
	var/list/table = system_table()
	for(var/path in subtypesof(/datum/system))
		if(!system_instantiable(path))
			continue
		if(ispath(path, /datum/world_service))
			continue
		var/datum/system/S = system(path)
		if(S)
			. += S
	// World services keep the hand roster's order (world_services()), then any others that registered.
	var/list/seen = list()
	for(var/datum/world_service/W as anything in world_services())
		if(W && table[W.type] == W)
			. += W
			seen[W] = TRUE
	for(var/path in table)
		if(!ispath(path, /datum/world_service))
			continue
		if(!seen[table[path]])
			. += table[path]
	return .

// ---- boot

/// Called once when this system's needs are ready, by the boot DAG. May block (boot only).
/datum/system/proc/initialize()
	initialized = TRUE

/// TRUE when the boot DAG initializes this system. A system with no needs still boots at "early".
/datum/system/proc/boots_in_dag()
	return TRUE

/// Called once, after every DAG node has initialized: the bulk first evaluation of the members that
/// joined during boot (machine first wakes, and so on). Override and do the work; the kernel marks the
/// system ready around it.
/datum/system/proc/on_members_ready()
	return

/// Kernel-side wrapper of on_members_ready(). Runs it once.
/datum/system/proc/kernel_members_ready()
	if(members_ready)
		return
	members_ready = TRUE
	on_members_ready()

/// Server shutdown, reverse boot order.
/datum/system/proc/on_shutdown()
	return

/// A map is about to load (Master.StartLoadingMap): a system that defers work while one loads overrides these.
/datum/system/proc/StartLoadingMap()
	return

/// The map load finished (Master.StopLoadingMap).
/datum/system/proc/StopLoadingMap()
	return

// ---- the fire() shim

/// The legacy body of a system that used to be a subsystem: called every `wait` by its every() work item with the
/// previous run's state in `resumed`. A body that runs out of tick budget pauses through MC_TICK_CHECK and is called
/// again, resumed, on the next pass. Override it; a system without a body never declares the every().
/datum/system/proc/fire(resumed = FALSE)
	return

/// MC_TICK_CHECK's pause: the run stops here and resumes next pass.
/datum/system/proc/pause()
	. = 1
	if(state == SS_RUNNING)
		state = SS_PAUSED

/// The `when` of a fire() work item: the system is booted, allowed to fire and in a runlevel it runs in.
/datum/system/proc/fire_ready()
	return can_fire && initialized && periodic_runlevel_ok()

/// The work item handler of a fire() system: one run (or one resumed slice) of fire(), with the subsystem's accounting.
/// `dt` is unused: a fire() body keeps its own clock.
/datum/system/proc/fire_step(dt)
	SHOULD_NOT_SLEEP(TRUE)
	var/resumed = fire_resumed
	var/started = TICK_USAGE
	state = SS_RUNNING
	run_slices++
	fire(resumed)
	run_ms += TICK_USAGE_TO_MS(started)
	if(state == SS_PAUSED || state == SS_PAUSING)
		state = SS_IDLE
		fire_resumed = TRUE
		return STEP_YIELD
	state = SS_IDLE
	fire_resumed = FALSE
	times_fired++
	// ALLOW(sys_world_time_write): the kernel clock: a per-run timestamp of the scheduler itself, not a per-entity expiry
	last_fire = world.time
	fire_cost = fire_cost ? MC_AVERAGE_FAST(fire_cost, run_ms) : run_ms
	ticks = MC_AVERAGE(ticks, run_slices)
	run_ms = 0
	run_slices = 0
	return STEP_DONE

/// The stat panel line (was the subsystem's stat_entry()): override and append to `msg`.
/datum/system/proc/stat_entry(msg)
	return msg

// ---- time

// should_run() and periodic_step(dt) are the /datum procs (capabilities/refresh.dm, om/periodic.dm): a
// system overrides them like any datum on a cadence. periodic_step returns STEP_DONE (stay on the cadence),
// STEP_YIELD (resume next tick) or STEP_PARK / PROCESS_KILL (leave until wake_periodic()).

/// A system with a cadence runs while the current runlevel is one it accepts. Override and call ..().
/datum/system/should_run()
	return !periodic_parked && periodic_runlevel_ok()

/// TRUE when the current runlevel is in periodic_runlevels (0: the cadence's own gate applies).
/datum/system/proc/periodic_runlevel_ok()
	if(!periodic_runlevels || !Master?.current_runlevel)
		return TRUE
	return !!(periodic_runlevels & (1 << (Master.current_runlevel - 1)))

/// Puts the system (and its member driver) on its cadence when should_run() holds, and takes it off when
/// it does not. Call after anything that changes should_run() outside a dispatched call, and to restart a
/// system that parked itself (STEP_PARK, can_fire, an admin toggle).
/datum/system/proc/wake_periodic()
	periodic_parked = FALSE
	if(member_driver)
		member_driver.periodic_parked = FALSE
	if(periodic_cadence || periodic_interval)
		refresh_periodic(src)
	if(member_cadence)
		if(!member_driver)
			member_driver = new /datum/system_member_driver(src)
		refresh_periodic(member_driver)

/// Takes the system and its member driver off their cadences and drops any yielded resume. wake_periodic()
/// undoes it.
/datum/system/proc/park_periodic()
	periodic_parked = TRUE
	om_task_periodic_stop(src)
	om_cancel_timer_slot(src, "step_yield")
	if(member_driver)
		member_driver.periodic_parked = TRUE
		om_task_periodic_stop(member_driver)
		om_cancel_timer_slot(member_driver, "step_yield")

/// Deciseconds between this system's periodic steps: its own periodic_interval, else its cadence's step
/// (0 for a purely reactive system).
/datum/system/proc/step_interval()
	if(periodic_interval)
		return periodic_interval
	if(periodic_cadence)
		var/datum/cadence/P = periodic_cadence
		return initial(P.delta)
	return 0

/// Per-member gate, asked by the member driver before each member_step().
/datum/system/proc/member_should_run(atom/A)
	return TRUE

/// Per-member work on member_cadence. The result is ignored; a member that should stop being stepped makes
/// member_should_run() answer FALSE.
/datum/system/proc/member_step(atom/A, dt)
	SHOULD_NOT_SLEEP(TRUE)
	return STEP_DONE

/// Steps a system's members on its member_cadence: every member that member_should_run() accepts gets
/// member_step(), in join order, and a pass that runs out of budget yields and resumes where it stopped. A
/// member leaving mid-pass (swap-remove) can be skipped once; membership never blocks the pass.
/datum/system_member_driver
	var/datum/system/system
	var/cursor = 1
	/// As /datum/system periodic_parked, for the driver's own cadence.
	var/periodic_parked = FALSE

/datum/system_member_driver/New(datum/system/S)
	..()
	system = S
	periodic_cadence = S.member_cadence

/datum/system_member_driver/should_run()
	return !periodic_parked && system.member_count() && system.periodic_runlevel_ok()

/datum/system_member_driver/periodic_step(delta)
	var/list/members = system.member_list()
	while(cursor <= length(members))
		var/atom/A = members[cursor]
		cursor++
		if(!QDELETED(A) && system.member_should_run(A))
			system.member_step(A, delta)
		if(TICK_USAGE > Master.current_ticklimit && cursor <= length(members))
			return STEP_YIELD
	cursor = 1
	return STEP_DONE

// ---- the step protocol (om/periodic.dm calls these for every periodic step)

// Only systems and their member drivers yield; the slot is declared on those types.
OWN_TIMER(/datum/system, step_yield)
OWN_TIMER(/datum/system_member_driver, step_yield)

/// Reads one periodic_step() result. TRUE: the step asked to leave the cadence. A yield schedules its own
/// resume on the next tick.
/proc/periodic_step_result(datum/E, result, delta)
	switch(result)
		if(PROCESS_KILL, STEP_PARK)
			// A system that parks itself stays parked: without the flag its should_run() would restart it
			// with the refresh that follows this step.
			if(result == STEP_PARK)
				if(istype(E, /datum/system))
					var/datum/system/S = E
					S.periodic_parked = TRUE
				else if(istype(E, /datum/system_member_driver))
					var/datum/system_member_driver/D = E
					D.periodic_parked = TRUE
			return TRUE
		if(STEP_YIELD)
			after_slot(E, "step_yield", world.tick_lag, GLOBAL_PROC_REF(periodic_step_resume), E, delta)
	return FALSE

/// Resumes a yielded step next tick, unless the datum left the cadence meanwhile.
/proc/periodic_step_resume(datum/E, delta)
	if(QDELETED(E) || !E.periodic_pipe)
		return
	if(periodic_step_result(E, E.periodic_step(delta), delta))
		om_task_periodic_stop(E)

/// Runlevel changed: every started system re-evaluates should_run() (its runlevels may now exclude it).
/proc/kernel_runlevel_changed()
	var/list/table = system_table()
	for(var/path in table)
		var/datum/system/S = table[path]
		if(S.initialized && (S.periodic_runlevels || S.member_cadence))
			S.wake_periodic()

/// Puts every system that has a cadence on it, after boot (the last step of the kernel's members pass).
/proc/kernel_start_periodic()
	for(var/datum/system/S as anything in kernel_systems())
		if(S.periodic_cadence || S.periodic_interval || S.member_cadence)
			S.wake_periodic()

/// Event table: list(event_type = PROC_REF(handler)).
/datum/system/proc/events()
	return null

// ---- membership

/// Hooks: a member joined or left.
/datum/system/proc/on_join(atom/A)
	return

/datum/system/proc/on_leave(atom/A)
	return

/// Adds `A` (held by `source`; null is the anonymous source), optionally under `role`. Returns TRUE when it was not a
/// member already. A second source on an existing member only records the source.
/datum/system/proc/kernel_join(atom/A, source = null, role = null)
	return join(src, A, source || A, role)

/// Removes `source`'s hold on `A` (null: the anonymous source; `all`: every source) in O(1): the last member takes
/// its slot. Returns TRUE when `A` left the system. Wraps leave().
/datum/system/proc/kernel_leave(atom/A, source = null, all = FALSE)
	return leave(src, A, source || A, all)

/datum/system/proc/is_member(atom/A)
	return member_is(type, A)

/// The members, in join order. The store's own list: read it, never write it.
/datum/system/proc/member_list()
	return members_of(type)

/// How many members the system has.
/datum/system/proc/member_count()
	return members_total(type)

// ---- telemetry

/// Telemetry for the profiler, the stat panel and time_track: an alist of numbers and short strings.
/// The only channel other code reads a system's cost through.
/datum/system/proc/metrics()
	return alist("name" = name, "members" = member_count(), "initialized" = initialized, "cost" = fire_cost, "tick_usage" = 0, "overran" = 0, "times_fired" = times_fired, "reactions" = kernel().work_cost_of(type))
