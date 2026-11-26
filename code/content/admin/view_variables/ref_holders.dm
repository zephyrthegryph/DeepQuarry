// A whole-world search for what holds a datum. The reference finder (reference_tracking.dm) lists holders; this one also says how far it got, which is
// what a missing holder needs: it walks breadth first from the globals through lists, alists and the vars of datums that are not atoms, each container
// once, under a time budget, and reports every place that holds the target with the path that reached it, plus how many containers it visited and
// left. Use it when refcount(D) is higher than the holders you know of: a search that finishes (nothing left unvisited) and finds fewer holders than the
// count shows that the rest are in no DM container (a proc frame that is still running, a native table).
//
// Atoms are not opened by default (a million of them would be the whole cost). With `atoms` set the search also walks the vars, lists, vis_contents and
// contents of atoms (the world's areas first, then the target's own place, then every obj and mob), and reports an /image whose loc is the target, which
// is a reference no list element shows. Neither are the engine's declaration datums (ref_holders_skips()); a list longer
// than REF_HOLDERS_LONG_LIST is tested for the target with one native `in` and not walked.

/// The built-in list vars of an atom that BYOND does not let a search index by their elements: skipped, or read directly (contents, vis_contents).
GLOBAL_LIST_INIT(REF_HOLDERS_BUILTIN_LISTS, list("overlays", "underlays", "verbs", "vis_locs", "filters", "images", "locs", "group"))

/// A list this long is atoms and numbers (the world's contents, a registry): one native membership test, not a walk of its elements.
#define REF_HOLDERS_LONG_LIST 20000

/// With `from` (a datum or a list of datums), the search starts there instead of at the globals and walks only what they reach (atoms included when `atoms`).
/// The paths (text) of every container var, list element or alist entry that holds `target`, found within `budget` deciseconds of real time. The last
/// entry of the result is not a path but the summary ("visited N containers, M left unvisited"). Logs each hit and the summary as REF_HOLDERS lines.
/proc/ref_holders(datum/target, budget = 1 MINUTES, atoms = FALSE, from = null)
	var/list/labels = list()
	var/list/parents = list()
	var/list/values = list()
	var/list/seen = list()
	var/list/hits = list()
	if(from)
		// Queued directly: when `from` is the target itself it is walked, not reported as holding itself. A list of datums (every atom of the world, say)
		// seeds each one, so the walk goes level by level outward from all of them at once.
		var/list/roots = islist(from) ? from : list(from)
		for(var/datum/root in roots)
			if(seen[ref(root)])
				continue
			seen[ref(root)] = TRUE
			labels += "from [root.type]"
			parents += 0
			values += list(root)
	else
		for(var/name in global.vars)
			ref_holders_visit(0, "global.[name]", global.vars[name], target, labels, parents, values, seen, hits, atoms)
	if(atoms && !from)
		// Seeded in the order a holder is most likely: the areas, the target's own place, then everything that stands in the world.
		for(var/area/A in world)
			ref_holders_visit(0, "world area [A.type]", A, target, labels, parents, values, seen, hits, atoms)
		var/atom/place = target
		if(isatom(place))
			ref_holders_visit(0, "target.loc", place.loc, target, labels, parents, values, seen, hits, atoms)
			var/turf/at = get_turf(place)
			if(at)
				for(var/turf/near in range(3, at))
					ref_holders_visit(0, "turf near target", near, target, labels, parents, values, seen, hits, atoms)
					for(var/atom/neighbour in near)
						ref_holders_visit(0, "atom near target", neighbour, target, labels, parents, values, seen, hits, atoms)
		for(var/obj/O in world)
			ref_holders_visit(0, "world obj [O.type]", O, target, labels, parents, values, seen, hits, atoms)
		for(var/mob/M in world)
			ref_holders_visit(0, "world mob [M.type]", M, target, labels, parents, values, seen, hits, atoms)
	var/head = 1
	var/deadline = REALTIMEOFDAY + budget
	while(head <= length(values) && REALTIMEOFDAY < deadline)
		var/value = values[head]
		var/at = head
		head++
		if(istype(value, /alist))
			var/alist/table = value
			for(var/entry_key, entry in table)
				ref_holders_visit(at, "(alist key)", entry_key, target, labels, parents, values, seen, hits, atoms)
				ref_holders_visit(at, "(alist value of [istext(entry_key) ? entry_key : "a key"])", entry, target, labels, parents, values, seen, hits, atoms)
		else if(islist(value))
			var/list/L = value
			if(length(L) > REF_HOLDERS_LONG_LIST)
				if(target in L)
					ref_holders_visit(at, "(element)", target, target, labels, parents, values, seen, hits, atoms)
				continue
			for(var/entry in L)
				ref_holders_visit(at, "(element)", entry, target, labels, parents, values, seen, hits, atoms)
				// Some of an atom's own lists cannot be indexed by an atom, so with `atoms` the value under an atom key is not read (the key itself is).
				if(istext(entry) || (isdatum(entry) && !(atoms && isatom(entry))))
					var/assoc = L[entry]
					if(!isnull(assoc))
						ref_holders_visit(at, "(value of [istext(entry) ? entry : "a key"])", assoc, target, labels, parents, values, seen, hits, atoms)
		else
			var/datum/holder = value
			for(var/var_name in holder.vars)
				if(atoms && (var_name in GLOB.REF_HOLDERS_BUILTIN_LISTS))
					continue
				if(atoms && (var_name == "contents" || var_name == "vis_contents"))
					// These lists of atoms cannot be indexed by their elements, so they are read here, not queued as lists.
					var/list/atom_list = holder.vars[var_name]
					for(var/atom/member in atom_list)
						ref_holders_visit(at, ".[var_name] (element)", member, target, labels, parents, values, seen, hits, atoms)
					continue
				ref_holders_visit(at, ".[var_name]", holder.vars[var_name], target, labels, parents, values, seen, hits, atoms)
	var/summary = "visited [head - 1] containers, [length(values) - head + 1] left unvisited"
	log_world("REF_HOLDERS: [length(hits)] holder(s) found for [ref(target)] ([summary])")
	hits += summary
	return hits

/// One place in ref_holders(): recorded with its path when it is the target; a container not seen before is queued to be walked.
/proc/ref_holders_visit(parent, label, value, datum/target, list/labels, list/parents, list/values, list/seen, list/hits, atoms = FALSE)
	if(isnull(value) || isnum(value) || istext(value) || ispath(value))
		return
	if(value == target)
		ref_holders_hit(parent, label, labels, parents, hits)
		return
	if(atoms && istype(value, /image))
		var/image/picture = value
		if(picture.loc == target)
			ref_holders_hit(parent, "[label] (an /image whose loc is it)", labels, parents, hits)
		return
	if(!(islist(value) || istype(value, /alist) || (isdatum(value) && (atoms || !isatom(value)) && !isclient(value) && !ref_holders_skips(value))))
		return
	var/key = ref(value)
	if(seen[key])
		return
	seen[key] = TRUE
	labels += label
	parents += parent
	values += list(value)

/// Records a hit: the path from the global that reached the holder, ending in `label`.
/proc/ref_holders_hit(parent, label, list/labels, list/parents, list/hits)
	var/path = label
	var/up = parent
	var/steps = 0
	while(up && steps++ < 12)
		path = "[labels[up]] [path]"
		up = parents[up]
	hits += path
	log_world("REF_HOLDERS: [path] holds it")

/// The declaration data the engine builds once (entries, type tables, log lines, plans): thousands of datums that hold no instance.
/proc/ref_holders_skips(datum/value)
	return istype(value, /datum/entry) || istype(value, /datum/centry) || istype(value, /datum/type_table) || istype(value, /datum/log_entry) || istype(value, /datum/lifeform_plan)
