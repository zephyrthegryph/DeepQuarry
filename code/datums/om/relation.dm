// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/datum/om/behaviour/internal/edge_refresh
	parent_type = /datum/scheduled_behaviour/internal/edge_refresh
	abstract_type = /datum/om/behaviour/internal/edge_refresh

/proc/om_link(datum/source, datum/target, rel_path)
	return relation_link(arglist(args))

/proc/om_unlink(datum/source, datum/target, rel_path)
	return relation_unlink(arglist(args))

/proc/om_unlink_edge(datum/om/edge/edge, datum/deleting)
	return relation_unlink_edge(arglist(args))

/proc/om_edge_views_link(datum/om/relation/R, datum/source, datum/target)
	return relation_edge_views_link(arglist(args))

/proc/om_edge_views_unlink(datum/om/relation/R, datum/source, datum/target)
	return relation_edge_views_unlink(arglist(args))

/proc/om_leave(datum/member, rel_path, datum/other)
	return relation_leave(arglist(args))

/proc/om_drop_z(z)
	return relation_drop_z(arglist(args))

/proc/om_z_generation(z)
	return relation_z_generation(arglist(args))

/proc/om_z_generation_bump(z)
	return relation_z_generation_bump(arglist(args))

/proc/om_edge_from(datum/om/rec/rec, datum/om/relation/R, as_source)
	return relation_edge_from(arglist(args))

/proc/om_edge_setup(datum/om/edge/edge)
	return relation_edge_setup(arglist(args))

/proc/om_edge_teardown(datum/om/edge/edge)
	return relation_edge_teardown(arglist(args))

/proc/om_edge_refresh(datum/om/edge/edge)
	return relation_edge_refresh(arglist(args))

/proc/om_edge_structure_changed(datum/om/rec/rec, rel_id, bit)
	return relation_edge_structure_changed(arglist(args))

/proc/om_has_related(datum/om/rec/rec)
	return relation_has_related(arglist(args))

/proc/om_neighbours(datum/E, rel_id)
	return relation_neighbours(arglist(args))

/proc/om_rebuild_fwd(datum/om/rec/rec)
	return relation_rebuild_fwd(arglist(args))

/proc/om_install_path(datum/om/rec/rec, list/ids, depth, datum/at, mask, bid)
	return relation_install_path(arglist(args))

/proc/om_fwd_add(datum/om/rec/rec, datum/N, mask, bid, structural)
	return relation_fwd_add(arglist(args))

/proc/om_clear_fwd_out(datum/om/rec/rec)
	return relation_clear_fwd_out(arglist(args))

// Old interaction callers identify successful links by their legacy edge subtype.
/datum/relation_definition/make_edge()
	return new /datum/om/edge
