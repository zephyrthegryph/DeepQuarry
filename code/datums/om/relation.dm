// Object-model core: relations and relation forwarding
// (doc/rewrite/object_model_core.md sections D and B.4).

/// Links `source` to `target` by relation `rel_path`. Returns the edge, or a
/// text reason when a single end is taken and the relation refuses.
/proc/om_link(datum/source, datum/target, rel_path)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	if(!source || !target || source == target)
		return "invalid ends"
	if(!own_guard(source, target, "a [rel_path] link")) // the one teardown guard (guard.dm)
		return "deleted"
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
			old.unlink_reason = RELATION_REPLACED
			om_unlink_edge(old)
	var/datum/om/edge/edge = new
	edge.rel = R
	edge.source = source
	edge.target = target
	LAZYADD(srec.edges, edge)
	LAZYADD(trec.edges, edge)
	om_edge_views_link(R, source, target)
	try
		R.on_link(source, target, edge)
	catch(var/exception/e)
		srec.sched.report_caught(e, "[R.type] on_link: [e]")
	om_edge_setup(edge)
	om_agg_edge_added(edge)
	om_edge_structure_changed(srec, R.id, CHANGE_RELATION_ADDED)
	om_edge_structure_changed(trec, R.id, CHANGE_RELATION_ADDED)
	changed(source, CHANGE_RELATION_ADDED)
	changed(target, CHANGE_RELATION_ADDED)
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
	if(!edge.unlink_reason)
		edge.unlink_reason = deleting ? RELATION_DESTROYING : RELATION_UNLINKED
	om_edge_views_unlink(R, source, target)
	try
		R.on_unlink(source, target, edge)
	catch(var/exception/e)
		var/datum/om/rec/either = srec || trec
		if(either)
			either.sched.report_caught(e, "[R.type] on_unlink: [e]")
		else
			dq_report_caught(e, "[R.type] on_unlink")
	if(srec && !srec.torn_down)
		om_edge_structure_changed(srec, R.id, CHANGE_RELATION_REMOVED)
		changed(source, CHANGE_RELATION_REMOVED)
	if(trec && !trec.torn_down)
		om_edge_structure_changed(trec, R.id, CHANGE_RELATION_REMOVED)
		changed(target, CHANGE_RELATION_REMOVED)
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
/proc/om_edge_views_link(datum/om/relation/R, datum/source, datum/target)
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

/// The inverse of om_edge_views_link(): a view is cleared only while it still names the partner.
/proc/om_edge_views_unlink(datum/om/relation/R, datum/source, datum/target)
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
/proc/om_leave(datum/member, rel_path, datum/other)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in member?.om_rec?.edges)
		if(edge.rel != R)
			continue
		if(other && edge.source != other && edge.target != other)
			continue
		try
			R.on_member_leave(edge.source, edge.target, member)
		catch(var/exception/e)
			dq_report_caught(e, "[R.type] on_member_leave")
		edge.unlink_reason = RELATION_LEFT
		om_unlink_edge(edge)
		return TRUE
	return FALSE

/// z-level release: every REF view naming a turf on `z` is cleared, and every rich edge with a
/// turf end on `z` is unlinked (RELATION_Z_RELEASED). Movables on the z-level drop their own
/// edges when they are destroyed.
/proc/om_drop_z(z)
	om_z_generation_bump(z)
	. = rel_drop_z(z)
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		for(var/datum/om/edge/edge as anything in T.om_rec?.edges?.Copy())
			edge.unlink_reason = RELATION_Z_RELEASED
			om_unlink_edge(edge)
			.++

/// Per z-level: bumped each time the level is released (om_drop_z()), carried in turf handles.
GLOBAL_LIST_EMPTY(om_z_generations)

/proc/om_z_generation(z)
	var/list/gens = GLOB.om_z_generations
	return (z > 0 && z <= length(gens)) ? gens[z] : 0

/proc/om_z_generation_bump(z)
	if(z <= 0)
		return
	var/list/gens = GLOB.om_z_generations
	if(length(gens) < z)
		gens.len = z
	gens[z] = (gens[z] || 0) + 1

/proc/om_edge_from(datum/om/rec/rec, datum/om/relation/R, as_source)
	for(var/datum/om/edge/edge as anything in rec.edges)
		if(edge.rel == R && (as_source ? edge.source == rec.owner : edge.target == rec.owner))
			return edge
	return null

/// Targets of `E`'s edges of this relation (E is the source).
/proc/linked(datum/E, rel_path)
	. = list()
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.source == E)
			. += edge.target

/// Sources of edges of this relation pointing at `E` (E is the target): its members.
/proc/linked_to(datum/E, rel_path)
	. = list()
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.target == E)
			. += edge.source

/// The single target of `E`'s edge of this relation, or null.
/proc/link_of(datum/E, rel_path)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in E?.om_rec?.edges)
		if(edge.rel == R && edge.source == E)
			return edge.target
	return null

/// The single source of an edge of this relation targeting `E`, or null.
/// Pair with a target_single relation (at most one exists to find).
/proc/link_source_of(datum/E, rel_path)
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
	if(R.compiled_active_if || R.compiled_holds_while)
		var/datum/om/behaviour/B = om_registry().edge_behaviour
		om_attach(edge, B)
		var/mask = (R.compiled_active_if?.depends_on || 0) | (R.compiled_holds_while?.depends_on || 0)
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
	if(R.compiled_holds_while && !isnull(R.compiled_holds_while.why_not(source, target)))
		edge.unlink_reason = RELATION_BROKEN
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
	if(rec.table.cache_relations)
		om_cache_clear(rec.owner, rec.table.cache_relations, rel_id)
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
// ---------------------------------------------------------------- typed relation accessors
//
// One proc per relation end, typed so reads chain (M.buckled_to()?.loc). They
// replaced the BUCKLED()/PULLING()/... accessor macros; tools/ci/check_ratchets.sh
// bans the macros and bare link_of() outside code/datums/om.

/// Was BUCKLED().
/mob/proc/buckled_to() as /atom/movable
	return link_of(src, /datum/om/relation/buckled_to)

/// Was BUCKLED_MOBS().
/atom/movable/proc/buckled_mob_list() as /list
	return linked_to(src, /datum/om/relation/buckled_to)

/// Was PULLING().
/mob/proc/pulling_target() as /atom/movable
	return link_of(src, /datum/om/relation/pulling)

/// A wheelchair pulls too (relaymove()); declared here rather than on /atom/movable.
/obj/structure/bed/chair/wheelchair/proc/pulling_target() as /atom/movable
	return link_of(src, /datum/om/relation/pulling)

/// Was PULLED_BY().
/atom/movable/proc/pulled_by_mob() as /mob/living
	return link_source_of(src, /datum/om/relation/pulling)

/// Was GRABBED_BY().
/mob/proc/grabbed_by_list() as /list
	return linked_to(src, /datum/om/relation/grabbing)

/// Was EYE_OWNER().
/mob/observer/eye/proc/eye_owner() as /mob
	return link_of(src, /datum/om/relation/eye_of)

/// Was EYES_OF().
/mob/living/proc/eyes_list() as /list
	return linked_to(src, /datum/om/relation/eye_of)

/// Was ACTIVE_EYE().
/mob/proc/active_eye() as /mob/observer/eye
	return link_of(src, /datum/om/relation/active_eye)

/// Was GRAB_TARGET().
/obj/item/grab/proc/grab_target() as /mob/living
	return link_of(src, /datum/om/relation/grabbing)

/// Was ORBIT_TARGET().
/atom/movable/proc/orbit_target() as /atom/movable
	return link_of(src, /datum/om/relation/orbiting)

/// Was ORBITERS().
/atom/movable/proc/orbiter_list() as /list
	return linked_to(src, /datum/om/relation/orbiting)

/// Was LEASH_PET().
/obj/item/leash/proc/leash_pet() as /mob/living
	return link_source_of(src, /datum/om/relation/leashed_to)

/// Was LEASH_MASTER().
/obj/item/leash/proc/leash_master() as /mob/living
	return link_of(src, /datum/om/relation/leash_held_by)

/// Was LEASH_OF().
/mob/living/proc/leash_item() as /obj/item
	return link_of(src, /datum/om/relation/leashed_to)

/// Was FOLLOWING().
/mob/observer/proc/following_target() as /atom/movable
	return link_of(src, /datum/om/relation/following)

/// Was FOLLOWERS().
/mob/proc/follower_list() as /list
	return linked_to(src, /datum/om/relation/following)

/// Was BORER_HOST().
/mob/living/simple_mob/animal/borer/proc/borer_host() as /mob/living/carbon/human
	return link_of(src, /datum/om/relation/host_of)

/// Was BORER_OF().
/mob/living/carbon/human/proc/borer_of() as /mob/living/simple_mob/animal/borer
	return link_source_of(src, /datum/om/relation/host_of)

/// Was BS_TX_TARGET().
/obj/item/radio/proc/bs_tx_target() as /obj/machinery/telecomms
	return link_of(src, /datum/om/relation/bluespace_tx_to)

/// Was BS_TX_RADIOS().
/obj/machinery/telecomms/proc/bs_tx_radios() as /list
	return linked_to(src, /datum/om/relation/bluespace_tx_to)

/// Was BS_RX_SOURCE().
/obj/item/radio/proc/bs_rx_source() as /obj/machinery/telecomms
	return link_of(src, /datum/om/relation/bluespace_rx_from)

/// Was BS_RX_RADIOS().
/obj/machinery/telecomms/proc/bs_rx_radios() as /list
	return linked_to(src, /datum/om/relation/bluespace_rx_from)

/// Was GRIPPER_HELD().
/obj/item/gripper/proc/gripper_held() as /obj/item
	return link_of(src, /datum/om/relation/gripper_holding)

/// Was UAV_MASTERS().
/obj/item/uav/proc/uav_masters() as /list
	return linked_to(src, /datum/om/relation/uav_master)

/// The mob holding grab item src (the grab lives in the assailant's hand), or null. Was GRAB_ASSAILANT().
/obj/item/grab/proc/grab_assailant() as /mob/living/carbon/human
	return ishuman(loc) ? loc : null
