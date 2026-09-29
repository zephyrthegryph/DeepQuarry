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

	// ---- contract
	/// Event types this system raises.
	var/list/emits

	// ---- members (kernel_join / kernel_leave)
	/// Every member atom, in join order. Membership is O(1) to add and remove (swap-remove).
	var/list/members
	/// member -> index in `members`.
	var/list/member_index
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
		var/datum/om/pipeline/periodic/P = periodic_cadence
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
	return !periodic_parked && length(system.members) && system.periodic_runlevel_ok()

/datum/system_member_driver/periodic_step(delta)
	while(cursor <= length(system.members))
		var/atom/A = system.members[cursor]
		cursor++
		if(!QDELETED(A) && system.member_should_run(A))
			system.member_step(A, delta)
		if(TICK_USAGE > Master.current_ticklimit && cursor <= length(system.members))
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
		_om_periodic_stop(E)

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

/// Adds `A`. Returns TRUE when it was not a member already.
/datum/system/proc/kernel_join(atom/A)
	if(!A || (member_index && member_index[A]))
		return FALSE
	LAZYINITLIST(members)
	LAZYINITLIST(member_index)
	members += A
	member_index[A] = length(members)
	on_join(A)
	return TRUE

/// Removes `A` in O(1): the last member takes its slot. Returns TRUE when it was a member.
/datum/system/proc/kernel_leave(atom/A)
	var/index = member_index?[A]
	if(!index)
		return FALSE
	var/last = length(members)
	var/atom/moved = members[last]
	members[index] = moved
	member_index[moved] = index
	members.len = last - 1
	member_index -= A
	if(!length(members))
		members = null
		member_index = null
	on_leave(A)
	return TRUE

/datum/system/proc/is_member(atom/A)
	return !!member_index?[A]

// ---- telemetry

/// Telemetry for the profiler, the stat panel and time_track: an alist of numbers and short strings.
/// The only channel other code reads a system's cost through.
/datum/system/proc/metrics()
	return alist("name" = name, "members" = length(members), "initialized" = initialized, "cost" = 0, "tick_usage" = 0, "overran" = 0)
