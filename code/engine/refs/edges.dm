// Object-model core: relations and relation forwarding
// (doc/rewrite/object_model_core.md sections D and B.4).

/// Links `source` to `target` by relation `rel_path`. Returns the edge, or a
/// text reason when a single end is taken and the relation refuses.
/proc/relation_link(datum/source, datum/target, rel_path)
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	if(!source || !target || source == target)
		return "invalid ends"
	if(!own_guard(source, target, "a [rel_path] link")) // the one teardown guard (guard.dm)
		return "deleted"
	var/datum/scheduler_record/srec = scheduler_record_of(source)
	var/datum/scheduler_record/trec = scheduler_record_of(target)
	if(!srec || !trec)
		return "deleted"
	for(var/datum/relation_edge/edge as anything in srec.edges)
		if(edge.rel == R && edge.source == source && edge.target == target)
			return edge
	if(R.source_single)
		var/datum/relation_edge/old = relation_edge_from(srec, R, TRUE)
		if(old)
			if(R.conflict == OM_REL_REFUSE)
				return "[source] already has \a [R.name || "link"]"
			relation_unlink_edge(old)
	if(R.target_single)
		var/datum/relation_edge/old = relation_edge_from(trec, R, FALSE)
		if(old)
			if(R.conflict == OM_REL_REFUSE)
				return "[target] is in use"
			old.unlink_reason = RELATION_REPLACED
			relation_unlink_edge(old)
	var/datum/relation_edge/edge = R.make_edge()
	edge.rel = R
	edge.source = source
	edge.target = target
	LAZYADD(srec.edges, edge)
	LAZYADD(trec.edges, edge)
	relation_edge_views_link(R, source, target)
	try
		R.on_link(source, target, edge)
	catch(var/exception/e)
		srec.sched.report_caught(e, "[R.type] on_link: [e]")
	relation_edge_setup(edge)
	derived_agg_edge_added(edge)
	relation_edge_structure_changed(srec, R.id, CHANGE_RELATION_ADDED)
	relation_edge_structure_changed(trec, R.id, CHANGE_RELATION_ADDED)
	state_changed(source, CHANGE_RELATION_ADDED)
	state_changed(target, CHANGE_RELATION_ADDED)
	return edge

/proc/relation_unlink(datum/source, datum/target, rel_path)
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	var/datum/scheduler_record/srec = source?.om_rec
	for(var/datum/relation_edge/edge as anything in srec?.edges)
		if(edge.rel == R && edge.source == source && edge.target == target)
			relation_unlink_edge(edge)
			return TRUE
	return FALSE

/// Removes `edge` from both ends. `deleting` is the end being destroyed, if
/// any: end policies apply to the other end. Hooks get both ends non-null.
/proc/relation_unlink_edge(datum/relation_edge/edge, datum/deleting)
	var/datum/relation_definition/R = edge.rel
	var/datum/source = edge.source
	var/datum/target = edge.target
	if(!source || !target)
		return
	var/datum/scheduler_record/srec = source.om_rec
	var/datum/scheduler_record/trec = target.om_rec
	if(srec)
		LAZYREMOVE(srec.edges, edge)
	if(trec)
		LAZYREMOVE(trec.edges, edge)
	relation_edge_teardown(edge)
	if(trec)
		derived_agg_edge_removed(edge, trec)
	if(!edge.unlink_reason)
		edge.unlink_reason = deleting ? RELATION_DESTROYING : RELATION_UNLINKED
	relation_edge_views_unlink(R, source, target)
	try
		R.on_unlink(source, target, edge)
	catch(var/exception/e)
		var/datum/scheduler_record/either = srec || trec
		if(either)
			either.sched.report_caught(e, "[R.type] on_unlink: [e]")
		else
			dq_report_caught(e, "[R.type] on_unlink")
	if(srec && !srec.torn_down)
		relation_edge_structure_changed(srec, R.id, CHANGE_RELATION_REMOVED)
		state_changed(source, CHANGE_RELATION_REMOVED)
	if(trec && !trec.torn_down)
		relation_edge_structure_changed(trec, R.id, CHANGE_RELATION_REMOVED)
		state_changed(target, CHANGE_RELATION_REMOVED)
	edge.source = null
	edge.target = null
	if(R.derived_view)
		if(!QDELETED(source) && hascall(source, R.derived_view))
			call(source, R.derived_view)()
	if(deleting == source && R.on_source_delete == OM_END_DELETE_OTHER && !QDELETED(target))
		spent(target)
	else if(deleting == target && R.on_target_delete == OM_END_DELETE_OTHER && !QDELETED(source))
		spent(source)

/// Framework-maintained view vars and the list-undo list, on link.
/proc/relation_edge_views_link(datum/relation_definition/R, datum/source, datum/target)
	if(R.source_view)
		source.vars[R.source_view] = target // ALLOW(api): the relation machinery writes the view var itself; it is the accessor for these views
		own_field_changed(source, R.source_view)
	if(R.target_view)
		target.vars[R.target_view] = source // ALLOW(api): the relation machinery writes the view var itself; it is the accessor for these views
		own_field_changed(target, R.target_view)
	if(R.undo_list)
		var/list/L = target.vars[R.undo_list]
		if(!islist(L))
			L = list()
			target.vars[R.undo_list] = L // ALLOW(api): the relation machinery restores the undo list itself; it is the accessor for relations
			own_field_changed(target, R.undo_list)
		L |= source
	if(R.derived_view && hascall(source, R.derived_view))
		call(source, R.derived_view)()

/// The inverse of relation_edge_views_link(): a view is cleared only while it still names the partner.
/proc/relation_edge_views_unlink(datum/relation_definition/R, datum/source, datum/target)
	if(R.source_view && source.vars[R.source_view] == target)
		source.vars[R.source_view] = null // ALLOW(api): the relation machinery writes the view var itself; it is the accessor for these views
		own_field_changed(source, R.source_view)
	if(R.target_view && target.vars[R.target_view] == source)
		target.vars[R.target_view] = null // ALLOW(api): the relation machinery writes the view var itself; it is the accessor for these views
		own_field_changed(target, R.target_view)
	if(R.undo_list)
		var/list/L = target.vars[R.undo_list]
		if(islist(L))
			L -= source
			if(!length(L))
				target.vars[R.undo_list] = null // ALLOW(api): the relation machinery restores the undo list itself; it is the accessor for relations
				own_field_changed(target, R.undo_list)

/// A member leaves through its own domain proc: the relation's on_member_leave() runs, then the
/// edge between `member` and `other` (either direction) is unlinked with RELATION_LEFT.
/proc/relation_leave(datum/member, rel_path, datum/other)
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	for(var/datum/relation_edge/edge as anything in member?.om_rec?.edges)
		if(edge.rel != R)
			continue
		if(other && edge.source != other && edge.target != other)
			continue
		try
			R.on_member_leave(edge.source, edge.target, member)
		catch(var/exception/e)
			dq_report_caught(e, "[R.type] on_member_leave")
		edge.unlink_reason = RELATION_LEFT
		relation_unlink_edge(edge)
		return TRUE
	return FALSE

/// z-level release: every REF view naming a turf on `z` is cleared, and every rich edge with a
/// turf end on `z` is unlinked (RELATION_Z_RELEASED). Movables on the z-level drop their own
/// edges when they are destroyed.
/proc/relation_drop_z(z)
	relation_z_generation_bump(z)
	. = rel_drop_z(z)
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		for(var/datum/relation_edge/edge as anything in T.om_rec?.edges?.Copy())
			edge.unlink_reason = RELATION_Z_RELEASED
			relation_unlink_edge(edge)
			.++

/// Per z-level: bumped each time the level is released (relation_drop_z()), carried in turf handles.
GLOBAL_LIST_EMPTY(om_z_generations)

/proc/relation_z_generation(z)
	var/list/gens = GLOB.om_z_generations
	return (z > 0 && z <= length(gens)) ? gens[z] : 0

/proc/relation_z_generation_bump(z)
	if(z <= 0)
		return
	var/list/gens = GLOB.om_z_generations
	if(length(gens) < z)
		gens.len = z
	gens[z] = (gens[z] || 0) + 1

/proc/relation_edge_from(datum/scheduler_record/rec, datum/relation_definition/R, as_source)
	for(var/datum/relation_edge/edge as anything in rec.edges)
		if(edge.rel == R && (as_source ? edge.source == rec.owner : edge.target == rec.owner))
			return edge
	return null

/// Targets of `E`'s edges of this relation (E is the source).
/proc/linked(datum/E, rel_path)
	. = list()
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	for(var/datum/relation_edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.source == E)
			. += edge.target

/// Sources of edges of this relation pointing at `E` (E is the target): its members.
/proc/linked_to(datum/E, rel_path)
	. = list()
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	for(var/datum/relation_edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.target == E)
			. += edge.source

/// The single target of `E`'s edge of this relation, or null.
/proc/link_of(datum/E, rel_path)
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	for(var/datum/relation_edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.source == E)
			return edge.target
	return null

/// The single source of an edge of this relation targeting `E`, or null.
/// Pair with a target_single relation (at most one exists to find).
/proc/link_source_of(datum/E, rel_path)
	var/datum/relation_definition/R = definition_registry().relation(rel_path)
	for(var/datum/relation_edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.target == E)
			return edge.source
	return null

// ---------------------------------------------------------------- edge contributions

/datum/scheduled_behaviour/internal/edge_refresh
	name = "om: relation active_if"
	lane = LANE_URGENT

/datum/scheduled_behaviour/internal/edge_refresh/on_wake(datum/relation_edge/edge, changes)
	relation_edge_refresh(edge)

/proc/relation_edge_setup(datum/relation_edge/edge)
	var/datum/relation_definition/R = edge.rel
	if(R.compiled_active_if || R.compiled_holds_while)
		var/datum/scheduled_behaviour/B = definition_registry().edge_behaviour
		entity_attach(edge, B)
		var/mask = (R.compiled_active_if?.depends_on || 0) | (R.compiled_holds_while?.depends_on || 0)
		if(mask)
			entity_watch(edge, edge.source, mask, B)
			entity_watch(edge, edge.target, mask, B)
	relation_edge_refresh(edge)

/proc/relation_edge_teardown(datum/relation_edge/edge)
	if(edge.om_rec)
		entity_teardown_rest(edge)
	edge.active = FALSE

/// Applies or releases the relation's contributions as active_if says.
/proc/relation_edge_refresh(datum/relation_edge/edge)
	var/datum/relation_definition/R = edge.rel
	var/datum/source = edge.source
	var/datum/target = edge.target
	if(!source || !target)
		return
	if(R.compiled_holds_while && !isnull(R.compiled_holds_while.why_not(source, target)))
		edge.unlink_reason = RELATION_BROKEN
		relation_unlink_edge(edge)
		return
	var/want = !R.compiled_active_if || isnull(R.compiled_active_if.why_not(source, target))
	if(!want)
		if(edge.active)
			edge.active = FALSE
			contribution_release_all_from(edge)
		return
	edge.active = TRUE
	for(var/id in R.contributes)
		contribution_hold(target, id, edge, definition_read(source, R.contributes[id]))
	for(var/id in R.source_contributes)
		contribution_hold(source, id, edge, definition_read(target, R.source_contributes[id]))

// ---------------------------------------------------------------- forwarding

/// An edge of relation `rel_id` was added to or removed from `rec`: wake
/// behaviours that asked for RELATION_ADDED/REMOVED on it, and rebuild every
/// forwarding path that runs through this entity.
/proc/relation_edge_structure_changed(datum/scheduler_record/rec, rel_id, bit)
	if(rec.table.cache_relations)
		entity_cache_clear(rec.owner, rec.table.cache_relations, rel_id)
	for(var/i in 1 to length(rec.att))
		var/datum/scheduled_behaviour/B = rec.att[i]
		if(!(B.related_added_mask & bit))
			continue
		for(var/list/entry as anything in B.compiled_related)
			var/list/path = entry[1]
			if(length(path) == 1 && path[1] == rel_id && (entry[2] & bit))
				entity_wake_id(rec.owner, B.id, bit)
				break
	if(relation_has_related(rec))
		relation_rebuild_fwd(rec)
	if(rec.fwd_in)
		var/list/origins = list()
		for(var/j in 1 to length(rec.fwd_in) step 4)
			if(rec.fwd_in[j + 3])
				origins |= rec.fwd_in[j]
		for(var/datum/origin as anything in origins)
			if(origin.om_rec)
				relation_rebuild_fwd(origin.om_rec)

/proc/relation_has_related(datum/scheduler_record/rec)
	for(var/datum/scheduled_behaviour/B as anything in rec.att)
		if(B.compiled_related)
			return TRUE
	if(rec.dv)
		var/list/defs = definition_registry().derived
		for(var/i in 1 to length(rec.dv) step 5)
			var/datum/derived_definition/D = defs[rec.dv[i]]
			if(D.compiled_related || D.over_rel_id)
				return TRUE
	return FALSE

/// Every entity one hop along relation `rel_id` from `E`, either direction.
/proc/relation_neighbours(datum/E, rel_id)
	. = list()
	for(var/datum/relation_edge/edge as anything in E.om_rec?.edges)
		if(edge.rel.id != rel_id)
			continue
		. |= (edge.source == E) ? edge.target : edge.source

/// Recomputes the forwarding entries `rec`'s owner has installed on related
/// entities (wake_on_related, derived related_inputs, aggregate members).
/proc/relation_rebuild_fwd(datum/scheduler_record/rec)
	relation_clear_fwd_out(rec)
	var/datum/origin = rec.owner
	if(!origin || rec.torn_down)
		return
	for(var/datum/scheduled_behaviour/B as anything in rec.att)
		for(var/list/entry as anything in B.compiled_related)
			relation_install_path(rec, entry[1], 1, origin, entry[2], B.id)
	if(rec.dv)
		var/list/defs = definition_registry().derived
		for(var/i in 1 to length(rec.dv) step 5)
			var/datum/derived_definition/D = defs[rec.dv[i]]
			for(var/list/entry as anything in D.compiled_related)
				relation_install_path(rec, entry[1], 1, origin, entry[2], -D.idx)
			if(D.over_rel_id && D.member_inputs)
				for(var/datum/relation_edge/edge as anything in rec.edges)
					if(edge.rel.id == D.over_rel_id && edge.target == origin)
						relation_fwd_add(rec, edge.source, D.member_inputs, -D.idx, FALSE)

/proc/relation_install_path(datum/scheduler_record/rec, list/ids, depth, datum/at, mask, bid)
	var/last = depth == length(ids)
	for(var/datum/N as anything in relation_neighbours(at, ids[depth]))
		if(N == rec.owner)
			continue
		if(last)
			relation_fwd_add(rec, N, mask, bid, FALSE)
		else
			relation_fwd_add(rec, N, 0, bid, TRUE)
			relation_install_path(rec, ids, depth + 1, N, mask, bid)

/proc/relation_fwd_add(datum/scheduler_record/rec, datum/N, mask, bid, structural)
	var/datum/scheduler_record/nrec = scheduler_record_of(N)
	if(!nrec)
		return
	// Copy-on-write: entity_dispatch_change() walks fwd_in without copying it.
	var/list/entry = list(rec.owner, mask, bid, structural ? 1 : 0)
	nrec.fwd_in = nrec.fwd_in ? nrec.fwd_in + entry : entry
	LAZYOR(rec.fwd_out, N)
	if(mask)
		N.om_listen |= mask

/proc/relation_clear_fwd_out(datum/scheduler_record/rec)
	var/datum/origin = rec.owner
	for(var/datum/N as anything in rec.fwd_out)
		var/datum/scheduler_record/nrec = N.om_rec
		if(!nrec?.fwd_in)
			continue
		// Copy-on-write (see relation_fwd_add()).
		var/list/F = nrec.fwd_in.Copy()
		var/j = 1
		while(j <= length(F))
			if(F[j] == origin)
				F.Cut(j, j + 4)
				continue
			j += 4
		nrec.fwd_in = length(F) ? F : null
		entity_recompute_listen(nrec)
	rec.fwd_out = null
/// Relations allocate their actual edge carrier through this engine-declared interface.
/datum/relation_definition/proc/make_edge()
	return new /datum/relation_edge
