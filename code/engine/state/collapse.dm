/*
 * Collapse eligibility (doc/rewrite/state.md section 1): an object may collapse
 * into a latent entry only if nothing live depends on it. The checks:
 *   - outgoing references the codecs refuse (the serializer's errors);
 *   - active timers and processing (state_refusal());
 *   - observe() hooks with anything outside the subtree
 *     (behaviours are fine: they are type behaviour, state.md section 8);
 *   - incoming references: refcount() of each object in the subtree must equal
 *     the references its container, its contents and the subtree itself account
 *     for. Anything extra is an outside holder, and the object stays real.
 *
 * With `name_holders` (unit-test builds only), an extra reference runs the
 * reference finder so the blocker names the holder. It is opt-in: the finder
 * walks the whole world with no tick checks (seconds per search), and the
 * everyday callers (the latency policy's pin check, latent_collapse()) ask
 * about things a live owner legitimately holds, such as a machine's parts in
 * its component_parts, where "blocked" is the expected answer.
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
GLOBAL_TABLE(state_refcount_overhead, GLOBAL_PROC_REF(build_state_refcount_overhead))

/proc/build_state_refcount_overhead()
	var/list/overhead
	var/datum/state_refcount_probe/probe = new
	// One reference is this proc's `probe` variable, standing in for held_refs = 1.
	overhead = probe.measure_refcount_overhead()
	overhead[1] -= 1
	spent(probe)
	return overhead

/datum/state_refcount_probe/proc/measure_refcount_overhead()
	var/list/nodes = list(src, new /datum/state_refcount_probe)
	var/list/internal = nodes.Copy()
	var/list/counts = state_internal_ref_counts(nodes, internal)
	. = list(state_refcount_excess(nodes, internal, 1, counts), state_refcount_excess(nodes, internal, 2, counts))
	spent(nodes[2])

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
/datum/proc/state_collapse_blockers(held_refs = 1, name_holders = FALSE)
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
	. += state_refcount_blockers(nodes, internal, held_refs, name_holders)

/// Running behaviour: timers and processing.
/proc/state_running_blockers(datum/node)
	. = list()
	if(time_scheduler().timer_count(node))
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
	for(var/atom/movable/child as anything in contents_of(A))
		nodes += child
		state_collect_subtree(child, nodes)

/// observe() hooks that tie the subtree to something outside it: a node observing an outside entity, or an outside listener observing a node.
/proc/state_hook_blockers(list/nodes, list/internal)
	return state_reference_environment().hook_blockers(nodes, internal)

/// Compares refcount() of each object in the subtree with the references accounted for.
/proc/state_refcount_blockers(list/nodes, list/internal, held_refs, name_holders = FALSE)
	. = list()
	var/list/overhead = GLOBAL_TABLE_GET(state_refcount_overhead)
	var/list/counts = state_internal_ref_counts(nodes, internal)
	for(var/i in 1 to length(nodes))
		var/extra = state_refcount_excess(nodes, internal, i, counts) - (i == 1 ? overhead[1] + held_refs : overhead[2])
		if(extra > 0)
			. += state_describe_outside_refs(nodes[i], extra, name_holders)

/// refcount() of nodes[i] less the references its container, contents and subtree account for.
/// `internal_counts` (state_internal_ref_counts()) carries the subtree's references to every node,
/// counted in one pass; without it they are counted for this node alone.
/proc/state_refcount_excess(list/nodes, list/internal, i, list/internal_counts)
	return refcount(nodes[i]) - state_accounted_refs(nodes[i], internal, internal_counts ? internal_counts[i] : null)

/// References to `node` that its container, its contents and the subtree account for.
/// Relation views naming it count too: collapse parks them (om_handle_park()) and they re-link
/// when the thing re-materializes. `internal_refs`: the subtree's references to it, when already counted.
/proc/state_accounted_refs(datum/node, list/internal, internal_refs)
	. = (isnull(internal_refs) ? state_internal_refs(node, internal) : internal_refs) + rel_incoming_refs(node)
	// A queued refresh (changed()) holds it in GLOB.refresh_queue until the drain: framework bookkeeping, which
	// skips a collapsed entity, not an outside holder.
	if(node.refresh_queued)
		.++
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
	var/datum/scheduler_record/rec = movable.om_rec
	if(!rec)
		return
	if(!(rec in internal))
		for(var/name in rec.vars)
			if(!(name in GLOB.state_refscan_skip))
				. += state_count_refs_in(rec.vars[name], movable, 0, (name in GLOB.state_refscan_flat))
	for(var/datum/relation_edge/edge as anything in rec.edges)
		if(edge in internal)
			continue
		if(edge.source == movable && edge.target == movable.loc && istype(edge.rel, /datum/relation_definition/slot))
			. += 1

/// References to `node` from the vars of the subtree and its owned parts.
/proc/state_internal_refs(datum/node, list/internal)
	. = 0
	for(var/datum/holder as anything in internal)
		for(var/name in holder.vars)
			if(name in GLOB.state_refscan_skip)
				continue
			. += state_count_refs_in(holder.vars[name], node, 0, (name in GLOB.state_refscan_flat))

/// References to each of `nodes` from the vars of the subtree and its owned parts, as counts by
/// index: one pass over the holders' vars. state_internal_refs() per node rescanned every holder
/// once per node, O(nodes x holders), which made one collapse check on a full locker cost 5-25 ms.
/// Nodes are matched with nodes.Find(), so counting holds no reference to any node beyond what
/// `nodes` already does and the refcount overhead calibration is unaffected.
/proc/state_internal_ref_counts(list/nodes, list/internal)
	var/list/counts = new /list(length(nodes))
	for(var/i in 1 to length(counts))
		counts[i] = 0
	for(var/j in 1 to length(internal))
		var/datum/holder = internal[j]
		for(var/name in holder.vars)
			if(name in GLOB.state_refscan_skip)
				continue
			state_tally_refs_in(holder.vars[name], nodes, counts, 0, (name in GLOB.state_refscan_flat))
	return counts

/// state_count_refs_in() for every node at once: adds each reference to one of `nodes` found in
/// `value` to `counts` at that node's index. Same traversal and flat-list rules.
/proc/state_tally_refs_in(value, list/nodes, list/counts, depth, flat = FALSE)
	if(isdatum(value))
		var/found = nodes.Find(value)
		if(found)
			counts[found]++
		return
	if(!islist(value) || depth > 4)
		return
	var/list/L = value
	for(var/key in L)
		if(isnull(key))
			continue
		if(islist(key))
			state_tally_refs_in(key, nodes, counts, depth + 1)
		else if(isdatum(key))
			var/found = nodes.Find(key)
			if(found)
				counts[found]++
		if(!flat && !isnum(key) && !islist(key))
			var/assoc
			// See state_count_refs_in(): a built-in list with no associated values.
			try
				assoc = L[key]
			catch // ALLOW(silent_catch): a list with no associated values is expected here; it is read as flat
				flat = TRUE
				continue
			if(!isnull(assoc))
				state_tally_refs_in(assoc, nodes, counts, depth + 1)

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
			var/assoc
			// Some built-in lists held in ordinary vars (appearance/overlay lists of an
			// /image or a copied overlays list) have no associated values, and L[key]
			// on them is a "bad index" runtime. Read those as flat; the sweep caught the
			// runtime per atom but backed the atom off and logged it every pass.
			try
				assoc = L[key]
			catch // ALLOW(silent_catch): a list with no associated values is expected here; it is read as flat
				flat = TRUE
				continue
			if(!isnull(assoc))
				. += state_count_refs_in(assoc, node, depth + 1)

/proc/state_describe_outside_refs(datum/node, extra, name_holders = FALSE)
	return state_reference_environment().describe(node, extra, name_holders)

#undef STATE_REFS_FROM_LOC
#undef STATE_REFS_PER_CONTENT

GLOBAL_DATUM(state_reference_environment, /datum/state_reference_environment)
/datum/state_reference_environment
/datum/state_reference_environment/proc/hook_blockers(list/nodes, list/internal)
	return list()
/datum/state_reference_environment/proc/describe(datum/node, extra, name_holders = FALSE)
	return "[node.type] has [extra] reference\s from outside its container"

/proc/state_reference_environment()
	RETURN_TYPE(/datum/state_reference_environment)
	if(!GLOB.state_reference_environment)
		GLOB.state_reference_environment = new /datum/state_reference_environment
	return GLOB.state_reference_environment
