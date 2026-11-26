/// A system: one self-contained part of the game (doc/rewrite/kernel.md sec 2.1). Plain DM: configuration is
/// type vars, behaviour is overrides. The kernel registers every non-abstract subtype once: a system registers itself
/// in system_table() when created (SYSTEM_DEF, or system(path)).
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

	/// The membership roles this system accepts (join(system, E, source, role)): empty accepts any. A role that is not in
	/// a non-empty list is a CRASH in join().
	var/list/roles
	/// The kernel phase (KERNEL_PHASE_*) the system's every() items run in when the declaration names none: a host system
	/// sets KERNEL_PHASE_K or KERNEL_PHASE_N, the rest keep phase P.
	var/phase = KERNEL_PHASE_P
	/// TRUE: the boot passes (kernel_create_systems(), kernel_systems()) never create it; only system(path), on demand, does.
	/// A test fixture system sets it so it does not boot with the live kernel.
	var/lazy_only = FALSE

	// ---- time
	/// RUNLEVEL_* bits the system's every() work runs in, or 0 for every runlevel.
	var/periodic_runlevels = 0
	/// The one place a system's latency class lives (LATENCY_L0..L3): what sheds its work under overload.
	var/latency_class = LATENCY_L1

	/// The init stage the system boots in at the earliest (INITSTAGE_*): a gameplay system converted from a subsystem keeps
	/// the stage it had. kernel_system_stage() takes the later of this and the stages of its needs.
	var/init_stage = INITSTAGE_FIRST

	// ---- periodic work accounting (the kernel keeps it for every memberless every() item the system declares)
	/// FALSE parks the system's periodic work (an admin toggle, an init that failed): its every() items carry
	/// `when = PROC_REF(work_ready)`.
	var/can_fire = TRUE
	/// Deciseconds between runs of the system's main every() (code that counts time per run reads it).
	var/wait = 20
	/// Completed runs of the system's work items, the last one's world.time, an EMA of one run's cost in ms, and the last
	/// run's cost.
	var/times_fired = 0
	var/last_fire = 0
	var/fire_cost = 0
	var/run_ms = 0
	/// Milliseconds initialize() took at boot (benchmarks).
	var/init_time_ms = 0
	/// Passes one completed run took, and the tick share it ran past its budget (always 0: work is budgeted).
	var/ticks = 1
	var/tick_overrun = 0

	// ---- contract
	/// Event types this system raises.
	var/list/emits

	// ---- members (kernel_join / kernel_leave; the store is controllers/kernel/membership.dm, MEMBER relations)
	/// TRUE once the boot pass has run on_members_ready(). Members joining before it wait for that pass.
	var/members_ready = FALSE

/// The table of registered systems, type -> instance. A static so a GLOBAL_DATUM_INIT service can
/// register during global init regardless of GLOB var order.
/proc/system_table()
	var/static/list/table = list() // ALLOW(sys_static_getter): the registry of live systems, written as systems register; a mutable static because a GLOB var may not exist yet during global init
	return table

/datum/system/New()
	..()
	if(type != abstract_type)
		var/list/table = system_table()
		if(!table[type])
			table[type] = src
		preinit()

/// TRUE when the kernel may instantiate `path` itself.
/proc/system_instantiable(path)
	if(!ispath(path, /datum/system))
		return FALSE
	return !is_abstract(path)

/// TRUE when `path` is a system the boot passes leave to system(path) (its `lazy_only`).
/proc/system_lazy_only(path)
	var/datum/system/proto = path
	return initial(proto.lazy_only)

/// The singleton of a system type. A non-abstract pure system that does not exist yet is created.
/// Hot paths cache the result in a local.
/proc/system(path)
	var/list/table = system_table()
	. = table[path]
	if(!. && system_instantiable(path))
		. = new path
	return .

/// Every registered system, in registry order (subtypesof() order). Systems are created here when missing.
/proc/kernel_systems()
	. = list()
	var/list/table = system_table()
	for(var/path in subtypesof(/datum/system))
		if(!system_instantiable(path))
			continue
		if(!table[path] && system_lazy_only(path))
			continue
		var/datum/system/S = system(path)
		if(S)
			. += S
	return .

// ---- boot

/// Called once when this system's needs are ready, by the boot DAG. May block (boot only).
/datum/system/proc/initialize()
	initialized = TRUE

/// TRUE when the boot DAG initializes this system. A system with no needs still boots at "early".
/datum/system/proc/boots_in_dag()
	return TRUE

/// A lazy system (boots_in_dag() FALSE) initializes on first use: `SSx.ready()` returns the system, initializing it when
/// it is not yet. initialize() sets `initialized` first, so a re-entrant call does not recurse.
PROC_SUMMARY(/datum/system/proc/ready) // a lazy system initializes once, on first use (the timing in its log is not an input); what a draw reads off it is its built data
/datum/system/proc/ready()
	RETURN_TYPE(/datum/system)
	if(!initialized)
		var/started = REALTIMEOFDAY
		initialize()
		initialized = TRUE
		log_world("System [name] initialized lazily in [(REALTIMEOFDAY - started) / 10]s.")
	return src

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

/// A map is about to load (Kernel.StartLoadingMap): a system that defers work while one loads overrides these.
/datum/system/proc/StartLoadingMap()
	return

/// The map load finished (Kernel.StopLoadingMap).
/datum/system/proc/StopLoadingMap()
	return

// ---- periodic work

/// The `when` of a system's periodic every(): the system is booted, allowed to run and in a runlevel it runs in.
/datum/system/proc/work_ready()
	return can_fire && initialized && periodic_runlevel_ok()

/// Wakes the system's parked work item for `handler` (a PROC_REF): work that returned STEP_PARK for lack of anything to do
/// runs again at the next pass. Cheap when the item is not parked. A fault-parked item stays parked (work_item/reset_fault() revives it).
/datum/system/proc/wake_work_item(handler)
	var/datum/work_item/W = kernel().work_by_key["[type]:[handler]"]
	if(W?.parked)
		W.wake()

/// Sets the interval of the system's work item for `handler` (a PROC_REF): a cadence read from config at boot. The item is
/// due again one new interval after its last run.
/datum/system/proc/set_work_interval(handler, interval)
	var/datum/work_item/W = kernel().work_by_key["[type]:[handler]"]
	if(!W || W.interval == interval)
		return
	W.set_interval(interval)
	W.next_run = min(W.next_run, world.time + interval)
	kernel().work_due_reset()

/// Skips the next `cycles` runs of the system's work items: a pass that cost a lot buys the tick a rest.
/datum/system/proc/postpone(cycles = 1)
	if(!can_fire || cycles < 1)
		return
	for(var/datum/work_item/W as anything in kernel().work_by_owner[type])
		W.next_run = max(W.next_run, world.time) + W.interval * cycles
	kernel().work_due_reset()

/// The kernel calls this after each memberless run of one of the system's work items: `ms` is its cost, `yielded` TRUE
/// when it ran out of budget and will run again ahead of its interval (a yielded run is not a completed one).
/datum/system/proc/note_run(ms, yielded)
	run_ms = ms
	if(yielded)
		return
	set_times_fired(times_fired + 1)
	// ALLOW(sys_world_time_write): the kernel clock: a per-run timestamp of the scheduler itself, not a per-entity expiry
	last_fire = world.time
	fire_cost = fire_cost ? KERNEL_AVERAGE_FAST(fire_cost, ms) : ms

/// Called when the config has been loaded or reloaded: a system that reads config at boot re-reads what changed.
/datum/system/proc/OnConfigLoad()
	return

/// Called from New(), before the globals exist: the system's own tables that nothing else needs to be up for (what a
/// subsystem's PreInit() did).
/datum/system/proc/preinit()
	return

/// The stat panel line (was the subsystem's stat_entry()): override and append to `msg`.
/datum/system/proc/stat_entry(msg)
	return msg

// ---- time

/// TRUE when the current runlevel is in periodic_runlevels (0: every runlevel). A system's every() items ask it.
/datum/system/proc/periodic_runlevel_ok()
	if(!periodic_runlevels || !Kernel?.current_runlevel)
		return TRUE
	return !!(periodic_runlevels & (1 << (Kernel.current_runlevel - 1)))

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
