// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/datum/om/behaviour/internal/edge_refresh
	parent_type = /datum/scheduled_behaviour/internal/edge_refresh
	abstract_type = /datum/om/behaviour/internal/edge_refresh

/proc/om_link(datum/source, datum/target, rel_path)
	return relation_link(arglist(args))

/proc/om_unlink(datum/source, datum/target, rel_path)
	return relation_unlink(arglist(args))







/proc/om_z_generation_bump(z)
	return relation_z_generation_bump(arglist(args))












// Old interaction callers identify successful links by their legacy edge subtype.
/datum/relation_definition/make_edge()
	return new /datum/om/edge
