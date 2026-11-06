/// Boot on declared dependencies (completion_plan sec 3.6, K1).
///
/// Subsystems declare `dependencies` (and the inverse, `dependents`) as typepaths;
/// there are no hand-numbered init orders. The MC orders them with
/// boot_dependency_order() at boot; a cycle is a boot error: it is logged, recorded
/// on Kernel.boot_dependency_cycle and fails the mc_boot_dependencies unit test.

/// Kahn's algorithm, popping the newest ready node (the MC's historical order, kept
/// so boot order is unchanged). `nodes` is the ordered node list; `deps` maps each
/// node to the list of nodes it must follow. Returns the sorted list. Nodes caught in
/// a cycle are left out of it; when `cycle_out` is given, the names of one cycle's
/// members (in cycle order) are appended to it.
/proc/boot_dependency_order(list/nodes, list/deps, list/cycle_out)
	var/n = length(nodes)
	var/list/index_of = list()
	for(var/i in 1 to n)
		index_of[nodes[i]] = i
	var/list/succ = new /list(n)
	var/list/counts = new /list(n)
	for(var/i in 1 to n)
		succ[i] = list()
		counts[i] = 0
	for(var/i in 1 to n)
		for(var/dep in deps[nodes[i]])
			var/j = index_of[dep]
			if(!j)
				continue
			succ[j] += nodes[i]
			counts[i] += 1
	var/list/ready = list()
	for(var/i in 1 to n)
		if(counts[i] == 0)
			ready += nodes[i]
	. = list()
	while(length(ready))
		var/node = ready[ready.len]
		ready.len--
		. += node
		for(var/next in succ[index_of[node]])
			var/k = index_of[next]
			counts[k] -= 1
			if(counts[k] == 0)
				ready += next
	if(length(.) == n || isnull(cycle_out))
		return
	// Walk dependency edges from a stuck node until one repeats: that is a cycle.
	var/list/stuck = nodes - .
	var/list/path = list()
	var/node = stuck[1]
	while(!(node in path))
		path += node
		var/found = null
		for(var/dep in deps[node])
			if(dep in stuck)
				found = dep
				break
		if(isnull(found))
			break
		node = found
	var/start = path.Find(node)
	if(start)
		for(var/i in start to length(path))
			cycle_out += "[path[i]]"
		cycle_out += "[node]"
	else
		for(var/stuck_node in stuck)
			cycle_out += "[stuck_node]"
