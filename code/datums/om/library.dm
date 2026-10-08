// Object-model core: the standard library of table rows
// (doc/rewrite/object_model_core.md, "Library"). Statuses, body effects and grants are stats; clocks are code/engine/time/clocks.dm.

// ---------------------------------------------------------------- relations

// A machine's occupant is a slot (/datum/om/relation/slot/occupant,
// containment.md §10), not a relation declared here: read it with SLOT_ITEM().

// What a mob is buckled to, what a puller pulls and what a grab holds are sparse declared links (links() in CAPABILITIES(/atom/movable),
// code/engine/declare/link_state.dm), not relations declared here.

// ---------------------------------------------------------------- bundles
