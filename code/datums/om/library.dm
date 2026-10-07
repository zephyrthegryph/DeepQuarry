// Object-model core: the standard library of table rows
// (doc/rewrite/object_model_core.md, "Library"). Mob Life uses the clocks and suspension;
// statuses are stats (code/library/mob/statuses.dm).

/proc/om_library_effects()
	// ALLOW(sys_const_list_alloc): read once, while the OM registry builds inside the global controller's New(), before any GLOBAL_LIST_INIT exists
	return list(
		// Body effects (body_effects.dm): factor tables keyed by definition type, value = stacks.
		EFFECT_BODY_EFFECTS = list("combine" = COMBINE_SUM_PER_KEY, "channel" = CHANGE_MOB_CONDITIONS, "publishes" = MOB_KEY_CONDITIONS, "type" = /datum/om/effect/body_effects),
		// Grant kinds.
		GRANT_ABILITY = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_LANGUAGE = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_VERB = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_verb),
		GRANT_VERB_HIDE = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_verb),
		GRANT_CAPABILITY = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_capability),
		GRANT_ACCESS = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_TRAIT = list("combine" = COMBINE_SUM_PER_KEY),
		GRANT_CADENCE = list("combine" = COMBINE_SUM_PER_KEY, "type" = /datum/om/effect/grant_cadence),
	)

// ---------------------------------------------------------------- relations

// A machine's occupant is a slot (/datum/om/relation/slot/occupant,
// containment.md §10), not a relation declared here: read it with SLOT_ITEM().

// What a mob is buckled to, what a puller pulls and what a grab holds are sparse declared links (links() in CAPABILITIES(/atom/movable),
// code/engine/declare/link_state.dm), not relations declared here.

// ---------------------------------------------------------------- bundles

