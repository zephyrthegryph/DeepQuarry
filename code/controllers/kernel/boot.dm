/// The boot DAG over mixed nodes (systems design sec 1.5). Nodes are subsystems and systems; a system's
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
	. = INITSTAGE_FIRST
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
	S.initialize()
	S.initialized = TRUE
	log_world("System [S.name] initialized in [(REALTIMEOFDAY - started) / 10]s.")

/// Runs the bulk first-evaluation pass of every system, after the whole DAG has initialized.
/proc/kernel_members_ready()
	for(var/datum/system/S as anything in kernel_systems())
		S.kernel_members_ready()
