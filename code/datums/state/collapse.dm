/*
 * Collapse eligibility (doc/rewrite/state.md section 1): an object may collapse
 * into a latent entry only if nothing live depends on it. The checks:
 *   - outgoing references the codecs refuse (the serializer's errors);
 *   - active timers and processing (state_refusal());
 *   - per-instance signal registrations with anything outside the subtree
 *     (type elements are fine: they are type behaviour, state.md section 8);
 *   - incoming references: refcount() of each object in the subtree must equal
 *     the references its container, its contents and the subtree itself account
 *     for. Anything extra is an outside holder, and the object stays real.
 *
 * In unit-test builds, an extra reference runs the reference finder so the
 * blocker names the holder.
 */

/// References a movable gets from its loc, and an atom gets per movable in its
/// contents. Measured on BYOND 516; dq_state_tests checks them.
#define STATE_REFS_FROM_LOC 1
#define STATE_REFS_PER_CONTENT 1
/// References state_collapse_blockers() itself holds while counting: the
/// entries in its `nodes` and `internal` lists, plus `src` for the root.
/// The counting loops go by index so no loop variable holds a node.
#define STATE_REFS_WHILE_COUNTING 2
#define STATE_REFS_SRC 1

/// Built-in vars the incoming-reference scan skips: they are counted by the
/// loc/contents rule above, or they cannot hold references to datums.
GLOBAL_LIST_INIT(state_refscan_skip, list("vars", "loc", "locs", "contents", "vis_locs", "overlays", "underlays", "verbs", "filters", "type", "parent_type", "appearance"))

/**
 * The reasons this object cannot collapse into a latent entry, or an empty list.
 * `held_refs` is how many references the caller itself holds to src (its own
 * variables and lists), which are not counted as outside holders.
 */
/datum/proc/state_collapse_blockers(held_refs = 1)
	. = list()
	var/list/errors = list()
	if(!state_serialize(src, STATE_FULL, errors))
		. += errors
	var/list/nodes = list(src)
	if(isatom(src))
		state_collect_subtree(src, nodes)
	// Components of the subtree are part of it: their parent refs and signal
	// registrations are internal.
	var/list/internal = nodes.Copy()
	for(var/i in 1 to length(nodes))
		var/list/components = state_components_of(nodes[i])
		if(components)
			internal |= components
	// Owned parts: datums and loc-less atoms the subtree's vars hold (HUD
	// objects, wires, reagent holders). Their references back are internal.
	var/list/owned = list()
	for(var/i in 1 to length(internal))
		state_owned_parts(internal[i], internal, owned)
	internal |= owned
	owned.Cut()
	for(var/i in 1 to length(nodes))
		. += state_running_blockers(nodes[i])
	. += state_signal_blockers(nodes, internal)
	. += state_refcount_blockers(nodes, internal, held_refs)

/// Running behaviour: timers and processing.
/proc/state_running_blockers(datum/node)
	. = list()
	if(length(node._active_timers))
		. += "[node.type] has active timers"
	if(node.datum_flags & DF_ISPROCESSING)
		. += "[node.type] is processing"

/proc/state_owned_parts(datum/holder, list/internal, list/owned)
	for(var/name in holder.vars)
		if(name in GLOB.state_refscan_skip)
			continue
		var/value = holder.vars[name]
		if(islist(value))
			for(var/item in value)
				state_add_owned_part(item, internal, owned)
		else
			state_add_owned_part(value, internal, owned)

/proc/state_add_owned_part(value, list/internal, list/owned)
	if(!isdatum(value) || (value in internal) || istype(value, /datum/element))
		return
	if(ismovable(value))
		var/atom/movable/movable = value
		if(movable.loc)
			return
	else if(isatom(value))
		return
	owned |= value

/proc/state_components_of(datum/D)
	for(var/key in D._datum_components)
		var/entry = D._datum_components[key]
		LAZYOR(., entry)

/proc/state_collect_subtree(atom/A, list/nodes)
	for(var/atom/movable/child as anything in A.contents)
		nodes += child
		state_collect_subtree(child, nodes)

/// Signal registrations that tie the subtree to something outside it.
/proc/state_signal_blockers(list/nodes, list/internal)
	. = list()
	for(var/datum/node as anything in internal)
		for(var/datum/target as anything in node._signal_procs)
			if(!(target in internal))
				. += "[node.type] listens to signals from [target.type]"
	for(var/datum/node as anything in nodes)
		for(var/signal in node._listen_lookup)
			var/listeners = node._listen_lookup[signal]
			for(var/datum/listener as anything in (islist(listeners) ? listeners : list(listeners)))
				if(istype(listener, /datum/element) || (listener in internal))
					continue
				. += "[listener.type] listens to [signal] on [node.type]"

/// Compares refcount() of each object in the subtree with the references accounted for.
/proc/state_refcount_blockers(list/nodes, list/internal, held_refs)
	. = list()
	for(var/i in 1 to length(nodes))
		var/expected = STATE_REFS_WHILE_COUNTING + state_accounted_refs(nodes[i], internal)
		if(i == 1)
			expected += held_refs + STATE_REFS_SRC
		var/actual = refcount(nodes[i])
		if(actual > expected)
			. += state_describe_outside_refs(nodes[i], actual - expected, actual)

/// References to `node` that its container, its contents, the subtree and type elements account for.
/proc/state_accounted_refs(datum/node, list/internal)
	. = state_internal_refs(node, internal)
	if(ismovable(node))
		var/atom/movable/movable = node
		if(movable.loc)
			. += STATE_REFS_FROM_LOC
	if(isatom(node))
		var/atom/A = node
		. += STATE_REFS_PER_CONTENT * length(A.contents)
	// Each element listening to the node holds it once, as a key of its _signal_procs.
	var/list/elements = list()
	for(var/signal in node._listen_lookup)
		var/listeners = node._listen_lookup[signal]
		for(var/datum/element/E in (islist(listeners) ? listeners : list(listeners)))
			elements |= E
	. += length(elements)

/// References to `node` from the vars of the subtree and its components.
/proc/state_internal_refs(datum/node, list/internal)
	. = 0
	for(var/datum/holder as anything in internal)
		for(var/name in holder.vars)
			if(name in GLOB.state_refscan_skip)
				continue
			. += state_count_refs_in(holder.vars[name], node, 0)

/proc/state_count_refs_in(value, datum/node, depth)
	if(value == node)
		return 1
	if(!islist(value) || depth > 4)
		return 0
	. = 0
	var/list/L = value
	for(var/key in L)
		if(key == node)
			.++
		else if(islist(key))
			. += state_count_refs_in(key, node, depth + 1)
		if(!isnum(key) && !islist(key))
			var/assoc = L[key]
			if(!isnull(assoc))
				. += state_count_refs_in(assoc, node, depth + 1)

/proc/state_describe_outside_refs(datum/node, extra, actual)
	. = "[node.type] has [extra] reference\s from outside its container (refcount [actual])"
#ifdef UNIT_TESTS
	// Name the holder. Slow (it walks the world), so test builds only.
	SSgarbage.should_save_refs = TRUE
	node.found_refs = null
	node.find_references()
	SSgarbage.should_save_refs = FALSE
	var/list/names = list()
	for(var/where in node.found_refs)
		if(!islist(where))
			names += "[where]"
	node.found_refs = null
	// The finder cannot name the global a list belongs to, so look there directly.
	for(var/global_name in GLOB.vars)
		var/list/candidate = GLOB.vars[global_name]
		if(islist(candidate) && (node in candidate))
			names += "GLOB.[global_name]"
	if(length(names))
		. += " (found in: [jointext(names, ", ")])"
#endif

#undef STATE_REFS_FROM_LOC
#undef STATE_REFS_PER_CONTENT
#undef STATE_REFS_WHILE_COUNTING
#undef STATE_REFS_SRC
