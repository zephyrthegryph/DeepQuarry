// A whole-world search for what holds a datum. The reference finder (reference_tracking.dm) lists holders; this one also says how far it got, which is
// what a missing holder needs: it walks breadth first from the globals through lists, alists and the vars of datums that are not atoms, each container
// once, under a time budget, and reports every place that holds the target with the path that reached it, plus how many containers it visited and
// left. Use it when refcount(D) is higher than the holders you know of: a search that finishes (nothing left unvisited) and finds fewer holders than the
// count shows that the rest are in no DM container (a proc frame that is still running, a native table).
//
// Atoms are not opened (a million of them would be the whole cost) and neither are the engine's declaration datums (ref_holders_skips()); a list longer
// than REF_HOLDERS_LONG_LIST is tested for the target with one native `in` and not walked.

/// A list this long is atoms and numbers (the world's contents, a registry): one native membership test, not a walk of its elements.
#define REF_HOLDERS_LONG_LIST 20000

/// The paths (text) of every container var, list element or alist entry that holds `target`, found within `budget` deciseconds of real time. The last
/// entry of the result is not a path but the summary ("visited N containers, M left unvisited"). Logs each hit and the summary as REF_HOLDERS lines.
/proc/ref_holders(datum/target, budget = 1 MINUTES)
	var/list/labels = list()
	var/list/parents = list()
	var/list/values = list()
	var/list/seen = list()
	var/list/hits = list()
	for(var/name in global.vars)
		ref_holders_visit(0, "global.[name]", global.vars[name], target, labels, parents, values, seen, hits)
	var/head = 1
	var/deadline = REALTIMEOFDAY + budget
	while(head <= length(values) && REALTIMEOFDAY < deadline)
		var/value = values[head]
		var/at = head
		head++
		if(istype(value, /alist))
			var/alist/table = value
			for(var/entry_key, entry in table)
				ref_holders_visit(at, "(alist key)", entry_key, target, labels, parents, values, seen, hits)
				ref_holders_visit(at, "(alist value of [istext(entry_key) ? entry_key : "a key"])", entry, target, labels, parents, values, seen, hits)
		else if(islist(value))
			var/list/L = value
			if(length(L) > REF_HOLDERS_LONG_LIST)
				if(target in L)
					ref_holders_visit(at, "(element)", target, target, labels, parents, values, seen, hits)
				continue
			for(var/entry in L)
				ref_holders_visit(at, "(element)", entry, target, labels, parents, values, seen, hits)
				if(istext(entry) || isdatum(entry))
					var/assoc = L[entry]
					if(!isnull(assoc))
						ref_holders_visit(at, "(value of [istext(entry) ? entry : "a key"])", assoc, target, labels, parents, values, seen, hits)
		else
			var/datum/holder = value
			for(var/var_name in holder.vars)
				ref_holders_visit(at, ".[var_name]", holder.vars[var_name], target, labels, parents, values, seen, hits)
	var/summary = "visited [head - 1] containers, [length(values) - head + 1] left unvisited"
	log_world("REF_HOLDERS: [length(hits)] holder(s) found for [ref(target)] ([summary])")
	hits += summary
	return hits

/// One place in ref_holders(): recorded with its path when it is the target; a container not seen before is queued to be walked.
/proc/ref_holders_visit(parent, label, value, datum/target, list/labels, list/parents, list/values, list/seen, list/hits)
	if(isnull(value) || isnum(value) || istext(value) || ispath(value))
		return
	if(value == target)
		var/path = label
		var/up = parent
		var/steps = 0
		while(up && steps++ < 12)
			path = "[labels[up]] [path]"
			up = parents[up]
		hits += path
		log_world("REF_HOLDERS: [path] holds it")
		return
	if(!(islist(value) || istype(value, /alist) || (isdatum(value) && !isatom(value) && !isclient(value) && !ref_holders_skips(value))))
		return
	var/key = ref(value)
	if(seen[key])
		return
	seen[key] = TRUE
	labels += label
	parents += parent
	values += list(value)

/// The declaration data the engine builds once (entries, type tables, log lines, plans): thousands of datums that hold no instance.
/proc/ref_holders_skips(datum/value)
	return istype(value, /datum/entry) || istype(value, /datum/centry) || istype(value, /datum/type_table) || istype(value, /datum/log_entry) || istype(value, /datum/lifeform_plan)
