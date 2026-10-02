/// The one ordering-graph validator. The boot DAG (systems and their `needs`) and the
/// work-item graph (`after` edges inside a phase) both go through graph_validate(), so a missing edge target or
/// a cycle is reported the same way in both, on the same sorter (boot_dependency_order(), boot_dependencies.dm).

/// The result of graph_validate().
/datum/graph_check
	/// The nodes in dependency order (a node comes after everything it depends on). Nodes caught in a cycle are left out.
	var/list/order
	/// One cycle's members in cycle order (text), or empty.
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/cycle = list()
	/// Human-readable problems: an edge that names nothing, a cycle.
	// ALLOW(instance_list): singleton or per-registration table, one instance per system; not a per-entity list
	var/list/errors = list()

/// TRUE when the graph has no problem.
/datum/graph_check/proc/ok()
	return !length(errors)

/// Orders `nodes` by `deps` (node -> list of nodes it must follow) and reports every problem.
/// `missing` is a list of problems the caller found while resolving its edges (an edge naming no node); they
/// are carried into the result so one report covers both kinds.
/proc/graph_validate(list/nodes, list/deps, list/missing = null)
	var/datum/graph_check/G = new
	if(length(missing))
		G.errors += missing
	G.order = boot_dependency_order(nodes, deps, G.cycle)
	if(length(G.order) != length(nodes))
		G.errors += "dependency cycle: [jointext(G.cycle, " -> ")]"
	return G
