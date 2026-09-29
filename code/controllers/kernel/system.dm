/// A system: one self-contained part of the game (systems design sec 2.1). Plain DM: configuration is
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
	/// The system-level cadence, or null for a purely reactive system.
	var/periodic_cadence = null
	/// Deciseconds between periodic steps, overriding the cadence's interval. 0: the cadence's.
	var/periodic_interval = 0
	/// LATENCY_L0..L3.
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

/// The system-level gate: FALSE parks the system's periodic_step().
/datum/system/proc/should_run()
	return TRUE

/// One system-level step, dt in deciseconds.
/datum/system/periodic_step(dt)
	return PROCESS_KILL

/// Per-member gate.
/datum/system/proc/member_should_run(atom/A)
	return TRUE

/// Per-member work.
/datum/system/proc/member_step(atom/A, dt)
	SHOULD_NOT_SLEEP(TRUE)
	return TRUE

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
	return alist("name" = name, "members" = length(members), "initialized" = initialized)
