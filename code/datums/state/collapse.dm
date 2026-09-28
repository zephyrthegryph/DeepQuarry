/*
 * Collapse eligibility (doc/rewrite/state.md section 1): an object may collapse
 * into a latent entry only if nothing live depends on it. The checks:
 *   - outgoing references the codecs refuse (the serializer's errors);
 *   - active timers and processing (state_refusal());
 *   - OM event hooks (om_hook()) with anything outside the subtree
 *     (behaviours are fine: they are type behaviour, state.md section 8);
 *   - incoming references: refcount() of each object in the subtree must equal
 *     the references its container, its contents and the subtree itself account
 *     for. Anything extra is an outside holder, and the object stays real.
 *
 * In unit-test builds, an extra reference runs the reference finder so the
 * blocker names the holder.
 */

/// References a movable gets from its loc, and an atom gets per movable in its
/// contents. Measured on BYOND 516; dq_state_collapse_blockers checks them.
#define STATE_REFS_FROM_LOC 1
#define STATE_REFS_PER_CONTENT 1

/// Probe for measuring the references the counting code itself holds.
/datum/state_refcount_probe

/**
 * The references state_collapse_blockers() itself holds on a node while it
 * counts (its lists, `src`, evaluation temporaries), as list(root, other node).
 * Measured once by running the same counting code on probes, so it follows
 * whatever BYOND counts. The counting loops go by index so no loop variable
 * holds a node.
 */
/proc/state_refcount_overhead()
	var/static/list/overhead
	if(!overhead)
		var/datum/state_refcount_probe/probe = new
		// One reference is this proc's `probe` variable, standing in for held_refs = 1.
		overhead = probe.measure_refcount_overhead()
		overhead[1] -= 1
		qdel(probe)
	return overhead

/datum/state_refcount_probe/proc/measure_refcount_overhead()
	var/list/nodes = list(src, new /datum/state_refcount_probe)
	var/list/internal = nodes.Copy()
	. = list(state_refcount_excess(nodes, internal, 1), state_refcount_excess(nodes, internal, 2))
	qdel(nodes[2])

/// Built-in vars the incoming-reference scan skips: they are counted by the
/// loc/contents rule above, or they cannot hold references to datums.
GLOBAL_LIST_INIT(state_refscan_skip, list("vars", "loc", "locs", "contents", "vis_locs", "overlays", "underlays", "verbs", "filters", "type", "parent_type", "appearance"))

/// Built-in list vars the scan reads as plain lists: they can hold references
/// (a light spot in an owned effect's vis_contents), but indexing them by an
/// object is a "bad index" runtime, so their entries have no associated value.
GLOBAL_LIST_INIT(state_refscan_flat, list("vis_contents"))

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
	var/list/internal = nodes.Copy()
	// Owned parts: datums and loc-less atoms the subtree's vars hold (HUD
	// objects, wires, reagent holders). Their references back are internal.
	var/list/owned = list()
	for(var/i in 1 to length(internal))
		state_owned_parts(internal[i], internal, owned)
	internal |= owned
	owned.Cut()
	for(var/i in 1 to length(nodes))
		. += state_running_blockers(nodes[i])
	. += state_hook_blockers(nodes, internal)
	. += state_refcount_blockers(nodes, internal, held_refs)

/// Running behaviour: timers and processing.
/proc/state_running_blockers(datum/node)
	. = list()
	if(om_timer_count(node))
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
	if(!isdatum(value) || (value in internal))
		return
	if(ismovable(value))
		var/atom/movable/movable = value
		if(movable.loc)
			return
	else if(isatom(value))
		return
	owned |= value

/proc/state_collect_subtree(atom/A, list/nodes)
	for(var/atom/movable/child as anything in A.contents)
		nodes += child
		state_collect_subtree(child, nodes)

/// OM event hooks that tie the subtree to something outside it.
/proc/state_hook_blockers(list/nodes, list/internal)
	. = list()
	for(var/datum/node as anything in internal)
		for(var/datum/target as anything in node.om_rec?.hooks_out)
			if(!(target in internal))
				. += "[node.type] hooks events on [target.type]"
	for(var/datum/node as anything in nodes)
		var/list/hooks_in = node.om_rec?.hooks_in
		for(var/path in hooks_in)
			var/list/hooks = hooks_in[path]
			for(var/i in 1 to length(hooks) step 2)
				var/datum/listener = hooks[i]
				if(listener in internal)
					continue
				. += "[listener.type] hooks [path] on [node.type]"

/// Compares refcount() of each object in the subtree with the references accounted for.
/proc/state_refcount_blockers(list/nodes, list/internal, held_refs)
	. = list()
	var/list/overhead = state_refcount_overhead()
	for(var/i in 1 to length(nodes))
		var/extra = state_refcount_excess(nodes, internal, i) - (i == 1 ? overhead[1] + held_refs : overhead[2])
		if(extra > 0)
			. += state_describe_outside_refs(nodes[i], extra)

/// refcount() of nodes[i] less the references its container, contents and subtree account for.
/proc/state_refcount_excess(list/nodes, list/internal, i)
	return refcount(nodes[i]) - state_accounted_refs(nodes[i], internal)

/// References to `node` that its container, its contents and the subtree account for.
/proc/state_accounted_refs(datum/node, list/internal)
	. = state_internal_refs(node, internal)
	if(ismovable(node))
		var/atom/movable/movable = node
		if(movable.loc)
			. += STATE_REFS_FROM_LOC
			// A container's ledger lists what it holds. Inside the subtree the
			// ledger is an owned part and its lists are scanned already.
			var/datum/ledger/L = movable.loc.ledger
			if(L && !(movable.loc in internal))
				. += L.refs_to(movable)
		. += state_om_slot_refs(movable, internal)
	if(isatom(node))
		var/atom/A = node
		. += STATE_REFS_PER_CONTENT * length(A.contents)

/// References to `movable` held by the object model for its containment: its
/// own record (when the owned-part scan did not already count it) and the slot
/// relation edge linking it to its loc (om_slot_entered()), which the loc's
/// record holds from outside the subtree. Other edges stay outside holders.
/proc/state_om_slot_refs(atom/movable/movable, list/internal)
	. = 0
	var/datum/om/rec/rec = movable.om_rec
	if(!rec)
		return
	if(!(rec in internal))
		for(var/name in rec.vars)
			if(!(name in GLOB.state_refscan_skip))
				. += state_count_refs_in(rec.vars[name], movable, 0, (name in GLOB.state_refscan_flat))
	for(var/datum/om/edge/edge as anything in rec.edges)
		if(edge in internal)
			continue
		if(edge.source == movable && edge.target == movable.loc && istype(edge.rel, /datum/om/relation/slot))
			. += 1

/// References to `node` from the vars of the subtree and its owned parts.
/proc/state_internal_refs(datum/node, list/internal)
	. = 0
	for(var/datum/holder as anything in internal)
		for(var/name in holder.vars)
			if(name in GLOB.state_refscan_skip)
				continue
			. += state_count_refs_in(holder.vars[name], node, 0, (name in GLOB.state_refscan_flat))

/// `flat`: a built-in list with no associated values (vis_contents), where
/// L[object] is a "bad index" runtime rather than null.
/proc/state_count_refs_in(value, datum/node, depth, flat = FALSE)
	if(value == node)
		return 1
	if(!islist(value) || depth > 4)
		return 0
	. = 0
	var/list/L = value
	for(var/key in L)
		// A null entry has no associated value, and L[null] is a bad index.
		if(isnull(key))
			continue
		if(key == node)
			.++
		else if(islist(key))
			. += state_count_refs_in(key, node, depth + 1)
		if(!flat && !isnum(key) && !islist(key))
			var/assoc = L[key]
			if(!isnull(assoc))
				. += state_count_refs_in(assoc, node, depth + 1)

/proc/state_describe_outside_refs(datum/node, extra)
	. = "[node.type] has [extra] reference\s from outside its container"
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
