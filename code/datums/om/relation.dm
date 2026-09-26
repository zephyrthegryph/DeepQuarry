// Object-model core: relations and relation forwarding
// (doc/rewrite/object_model_core.md sections D and B.4).

/// Links `source` to `target` by relation `rel_path`. Returns the edge, or a
/// text reason when a single end is taken and the relation refuses.
/proc/om_link(datum/source, datum/target, rel_path)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	if(!source || !target || source == target)
		return "invalid ends"
	var/datum/om/rec/srec = om_rec_of(source)
	var/datum/om/rec/trec = om_rec_of(target)
	if(!srec || !trec)
		return "deleted"
	for(var/datum/om/edge/edge as anything in srec.edges)
		if(edge.rel == R && edge.source == source && edge.target == target)
			return edge
	if(R.source_single)
		var/datum/om/edge/old = om_edge_from(srec, R, TRUE)
		if(old)
			if(R.conflict == OM_REL_REFUSE)
				return "[source] already has \a [R.name || "link"]"
			om_unlink_edge(old)
	if(R.target_single)
		var/datum/om/edge/old = om_edge_from(trec, R, FALSE)
		if(old)
			if(R.conflict == OM_REL_REFUSE)
				return "[target] is in use"
			om_unlink_edge(old)
	var/datum/om/edge/edge = new
	edge.rel = R
	edge.source = source
	edge.target = target
	LAZYADD(srec.edges, edge)
	LAZYADD(trec.edges, edge)
	try
		R.on_link(source, target, edge)
	catch(var/exception/e)
		srec.sched.error("[R.type] on_link: [e]")
	om_edge_setup(edge)
	om_agg_edge_added(edge)
	om_edge_structure_changed(srec, R.id, CHANGE_RELATION_ADDED)
	om_edge_structure_changed(trec, R.id, CHANGE_RELATION_ADDED)
	om_changed(source, CHANGE_RELATION_ADDED)
	om_changed(target, CHANGE_RELATION_ADDED)
	return edge

/proc/om_unlink(datum/source, datum/target, rel_path)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	var/datum/om/rec/srec = source?.om_rec
	for(var/datum/om/edge/edge as anything in srec?.edges)
		if(edge.rel == R && edge.source == source && edge.target == target)
			om_unlink_edge(edge)
			return TRUE
	return FALSE

/// Removes `edge` from both ends. `deleting` is the end being destroyed, if
/// any: end policies apply to the other end. Hooks get both ends non-null.
/proc/om_unlink_edge(datum/om/edge/edge, datum/deleting)
	var/datum/om/relation/R = edge.rel
	var/datum/source = edge.source
	var/datum/target = edge.target
	if(!source || !target)
		return
	var/datum/om/rec/srec = source.om_rec
	var/datum/om/rec/trec = target.om_rec
	if(srec)
		LAZYREMOVE(srec.edges, edge)
	if(trec)
		LAZYREMOVE(trec.edges, edge)
	om_edge_teardown(edge)
	if(trec)
		om_agg_edge_removed(edge, trec)
	try
		R.on_unlink(source, target, edge)
	catch(var/exception/e)
		var/datum/om/rec/either = srec || trec
		either?.sched.error("[R.type] on_unlink: [e]")
	if(srec && !srec.torn_down)
		om_edge_structure_changed(srec, R.id, CHANGE_RELATION_REMOVED)
		om_changed(source, CHANGE_RELATION_REMOVED)
	if(trec && !trec.torn_down)
		om_edge_structure_changed(trec, R.id, CHANGE_RELATION_REMOVED)
		om_changed(target, CHANGE_RELATION_REMOVED)
	edge.source = null
	edge.target = null
	if(deleting == source && R.on_source_delete == OM_END_DELETE_OTHER && !QDELETED(target))
		qdel(target)
	else if(deleting == target && R.on_target_delete == OM_END_DELETE_OTHER && !QDELETED(source))
		qdel(source)

/proc/om_edge_from(datum/om/rec/rec, datum/om/relation/R, as_source)
	for(var/datum/om/edge/edge as anything in rec.edges)
		if(edge.rel == R && (as_source ? edge.source == rec.owner : edge.target == rec.owner))
			return edge
	return null

/// Targets of `E`'s edges of this relation (E is the source).
/proc/om_related(datum/E, rel_path)
	. = list()
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.source == E)
			. += edge.target

/// Sources of edges of this relation pointing at `E` (E is the target): its members.
/proc/om_related_to(datum/E, rel_path)
	. = list()
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.target == E)
			. += edge.source

/// The single target of `E`'s edge of this relation, or null.
/proc/om_relation_of(datum/E, rel_path)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.source == E)
			return edge.target
	return null

/// The single source of an edge of this relation targeting `E`, or null.
/// Pair with a target_single relation (at most one exists to find).
/proc/om_source_of(datum/E, rel_path)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.target == E)
			return edge.source
	return null

// ---------------------------------------------------------------- edge contributions

/datum/om/behaviour/internal/edge_refresh
	name = "om: relation active_if"
	lane = LANE_URGENT

/datum/om/behaviour/internal/edge_refresh/on_wake(datum/om/edge/edge, changes)
	om_edge_refresh(edge)

/proc/om_edge_setup(datum/om/edge/edge)
	var/datum/om/relation/R = edge.rel
	if(R.compiled_active_if || R.compiled_break_if)
		var/datum/om/behaviour/B = om_registry().edge_behaviour
		om_attach(edge, B)
		var/mask = (R.compiled_active_if?.depends_on || 0) | (R.compiled_break_if?.depends_on || 0)
		if(mask)
			om_watch(edge, edge.source, mask, B)
			om_watch(edge, edge.target, mask, B)
	om_edge_refresh(edge)

/proc/om_edge_teardown(datum/om/edge/edge)
	if(edge.om_rec)
		om_teardown_rest(edge)
	edge.active = FALSE

/// Applies or releases the relation's contributions as active_if says.
/proc/om_edge_refresh(datum/om/edge/edge)
	var/datum/om/relation/R = edge.rel
	var/datum/source = edge.source
	var/datum/target = edge.target
	if(!source || !target)
		return
	if(R.compiled_break_if && !isnull(R.compiled_break_if.why_not(source, target)))
		om_unlink_edge(edge)
		return
	var/want = !R.compiled_active_if || isnull(R.compiled_active_if.why_not(source, target))
	if(!want)
		if(edge.active)
			edge.active = FALSE
			om_release_all_from(edge)
		return
	edge.active = TRUE
	for(var/id in R.contributes)
		om_hold(target, id, edge, om_read(source, R.contributes[id]))
	for(var/id in R.source_contributes)
		om_hold(source, id, edge, om_read(target, R.source_contributes[id]))
	for(var/kind in R.grants_target)
		var/ids = R.grants_target[kind]
		for(var/id in (islist(ids) ? ids : list(ids)))
			om_grant(target, kind, id, edge)
	for(var/kind in R.grants_occupant)
		var/ids = R.grants_occupant[kind]
		for(var/id in (islist(ids) ? ids : list(ids)))
			om_grant(source, kind, id, edge)

// ---------------------------------------------------------------- forwarding

/// An edge of relation `rel_id` was added to or removed from `rec`: wake
/// behaviours that asked for RELATION_ADDED/REMOVED on it, and rebuild every
/// forwarding path that runs through this entity.
/proc/om_edge_structure_changed(datum/om/rec/rec, rel_id, bit)
	for(var/i in 1 to length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		if(!(B.related_added_mask & bit))
			continue
		for(var/list/entry as anything in B.compiled_related)
			var/list/path = entry[1]
			if(length(path) == 1 && path[1] == rel_id && (entry[2] & bit))
				om_wake_id(rec.owner, B.id, bit)
				break
	if(om_has_related(rec))
		om_rebuild_fwd(rec)
	if(rec.fwd_in)
		var/list/origins = list()
		for(var/j in 1 to length(rec.fwd_in) step 4)
			if(rec.fwd_in[j + 3])
				origins |= rec.fwd_in[j]
		for(var/datum/origin as anything in origins)
			if(origin.om_rec)
				om_rebuild_fwd(origin.om_rec)

/proc/om_has_related(datum/om/rec/rec)
	for(var/datum/om/behaviour/B as anything in rec.att)
		if(B.compiled_related)
			return TRUE
	if(rec.dv)
		var/list/defs = om_registry().derived
		for(var/i in 1 to length(rec.dv) step 5)
			var/datum/om/derived/D = defs[rec.dv[i]]
			if(D.compiled_related || D.over_rel_id)
				return TRUE
	return FALSE

/// Every entity one hop along relation `rel_id` from `E`, either direction.
/proc/om_neighbours(datum/E, rel_id)
	. = list()
	for(var/datum/om/edge/edge as anything in E.om_rec?.edges)
		if(edge.rel.id != rel_id)
			continue
		. |= (edge.source == E) ? edge.target : edge.source

/// Recomputes the forwarding entries `rec`'s owner has installed on related
/// entities (wake_on_related, derived related_inputs, aggregate members).
/proc/om_rebuild_fwd(datum/om/rec/rec)
	om_clear_fwd_out(rec)
	var/datum/origin = rec.owner
	if(!origin || rec.torn_down)
		return
	for(var/datum/om/behaviour/B as anything in rec.att)
		for(var/list/entry as anything in B.compiled_related)
			om_install_path(rec, entry[1], 1, origin, entry[2], B.id)
	if(rec.dv)
		var/list/defs = om_registry().derived
		for(var/i in 1 to length(rec.dv) step 5)
			var/datum/om/derived/D = defs[rec.dv[i]]
			for(var/list/entry as anything in D.compiled_related)
				om_install_path(rec, entry[1], 1, origin, entry[2], -D.idx)
			if(D.over_rel_id && D.member_inputs)
				for(var/datum/om/edge/edge as anything in rec.edges)
					if(edge.rel.id == D.over_rel_id && edge.target == origin)
						om_fwd_add(rec, edge.source, D.member_inputs, -D.idx, FALSE)

/proc/om_install_path(datum/om/rec/rec, list/ids, depth, datum/at, mask, bid)
	var/last = depth == length(ids)
	for(var/datum/N as anything in om_neighbours(at, ids[depth]))
		if(N == rec.owner)
			continue
		if(last)
			om_fwd_add(rec, N, mask, bid, FALSE)
		else
			om_fwd_add(rec, N, 0, bid, TRUE)
			om_install_path(rec, ids, depth + 1, N, mask, bid)

/proc/om_fwd_add(datum/om/rec/rec, datum/N, mask, bid, structural)
	var/datum/om/rec/nrec = om_rec_of(N)
	if(!nrec)
		return
	// Copy-on-write: om_dispatch_change() walks fwd_in without copying it.
	var/list/entry = list(rec.owner, mask, bid, structural ? 1 : 0)
	nrec.fwd_in = nrec.fwd_in ? nrec.fwd_in + entry : entry
	LAZYOR(rec.fwd_out, N)
	if(mask)
		N.om_listen |= mask

/proc/om_clear_fwd_out(datum/om/rec/rec)
	var/datum/origin = rec.owner
	for(var/datum/N as anything in rec.fwd_out)
		var/datum/om/rec/nrec = N.om_rec
		if(!nrec?.fwd_in)
			continue
		// Copy-on-write (see om_fwd_add()).
		var/list/F = nrec.fwd_in.Copy()
		var/j = 1
		while(j <= length(F))
			if(F[j] == origin)
				F.Cut(j, j + 4)
				continue
			j += 4
		nrec.fwd_in = length(F) ? F : null
		om_recompute_listen(nrec)
	rec.fwd_out = null
