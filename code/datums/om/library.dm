// Object-model core: the standard library of table rows
// (doc/rewrite/object_model_core.md, "Library"). Mob Life uses the clocks and suspension;
// statuses are stats (code/library/mob/statuses.dm).

/proc/definition_standard_effects()
	return list() // no standard effect rows are left: statuses, body effects, grants and buckling are stats

// ---------------------------------------------------------------- relations

// A machine's occupant is a slot (/datum/om/relation/slot/occupant,
// containment.md §10), not a relation declared here: read it with SLOT_ITEM().

// What a mob is buckled to, what a puller pulls and what a grab holds are sparse declared links (links() in CAPABILITIES(/atom/movable),
// code/engine/declare/link_state.dm), not relations declared here.

// ---------------------------------------------------------------- bundles


/proc/om_library_effects()
	return definition_standard_effects()
