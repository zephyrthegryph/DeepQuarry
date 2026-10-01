/// The boot DAG over mixed nodes (doc/rewrite/kernel.md sec 1.5). Nodes are subsystems and systems; a system's
/// `needs` names other nodes by typepath. Ordering is boot_dependency_order() (boot_dependencies.dm),
/// which keeps the MC's newest-ready tie-break, so a system that needs subsystem X boots directly after X.

/// The systems the boot DAG initializes, in a stable order.
/proc/kernel_boot_systems()
	. = list()
	for(var/datum/system/S as anything in kernel_systems())
		if(S.boots_in_dag())
			. += S
	// The sorter pops the newest ready node, so the reversed list boots siblings in registry order.
	reverse_range(.)

/// Resolves every system's `needs` into node instances. `type_to_node` maps a typepath to the node that
/// is that type (subsystems and systems). A need that names no node is appended to `errors` and dropped.
/// Returns system -> list of nodes it must follow.
/proc/kernel_system_deps(list/systems, list/type_to_node, list/errors)
	. = list()
	for(var/datum/system/S as anything in systems)
		var/list/resolved = list()
		for(var/need in S.needs)
			var/node = type_to_node[need]
			if(!node)
				errors += "[S.type] needs [need], which is not a boot node"
				continue
			resolved += node
		.[S] = resolved
	return .

/// The init stage a system boots in: the latest stage among its subsystem needs, else INITSTAGE_FIRST.
/proc/kernel_system_stage(datum/system/S, list/deps)
	. = S.init_stage
	for(var/node in deps[S])
		if(istype(node, /datum/controller/subsystem))
			var/datum/controller/subsystem/SS = node
			. = max(., SS.init_stage)
		else
			. = max(., kernel_system_stage(node, deps))
	return .

/// Boots one system: its initialize(), timed and logged. A system already initialized (a hand boot got
/// there first, or a lazy first use) is left alone.
/proc/kernel_boot_system(datum/system/S)
	if(S.initialized)
		return
	var/started = REALTIMEOFDAY
	// The system's declared work (every() in reactions()) registers with the kernel as its reaction table is built.
	rx_table_of(S)
	S.initialize()
	S.initialized = TRUE
	S.init_time_ms = (REALTIMEOFDAY - started) * 100
	log_world("System [S.name] initialized in [(REALTIMEOFDAY - started) / 10]s.")

/// Runs the bulk first-evaluation pass of every system, after the whole DAG has initialized.
/proc/kernel_members_ready()
	for(var/datum/system/S as anything in kernel_systems())
		S.kernel_members_ready()
	kernel_start_periodic()

/// The registered systems that are not world services (the converted subsystems and the other pure systems), in
/// registry order. Systems already created only: nothing here instantiates.
/proc/kernel_pure_systems()
	. = list()
	var/list/table = system_table()
	for(var/path in table)
		if(ispath(path, /datum/world_service))
			continue
		. += table[path]

/// Server shutdown for the pure systems: on_shutdown() of each one that booted, in reverse registry order.
/proc/kernel_shutdown_systems()
	var/list/systems = kernel_pure_systems()
	reverse_range(systems)
	for(var/datum/system/S as anything in systems)
		if(S.initialized)
			log_world("Shutting down [S.name] system...")
			S.on_shutdown()

/// Creates every pure system, so the SS<X> globals (SYSTEM_DEF) exist before anything reads them. Called once the GLOB is up
/// (Master.New); creating a system twice is harmless, the registry keeps the first.
/proc/kernel_create_systems()
	for(var/path in subtypesof(/datum/system))
		if(system_instantiable(path) && !ispath(path, /datum/world_service))
			system(path)
