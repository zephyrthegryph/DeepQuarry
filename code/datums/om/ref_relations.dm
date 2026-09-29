// Typed accessors for the relations that replaced object-typed vars in the LC-refs sweep
// (doc/rewrite/lifecycle.md sec 4, object_model_core.md sec 7). Each reads the edge; nothing
// mirrors it into a var. Raw link_of()/linked_to() calls live here, in
// code/datums/om, as tools/ci/api_lints.py (raw_relation) requires.

/// The movable a throw is carrying (/datum/om/relation/throw_of).
/datum/proc/throw_subject() as /atom/movable
	return link_of(src, /datum/om/relation/throw_of)

/// The datum an action acts for (/datum/om/relation/action_for).
/datum/proc/action_target() as /datum
	return link_of(src, /datum/om/relation/action_for)

/// The mob an action is granted to (/datum/om/relation/action_granted_to).
/datum/proc/action_owner() as /mob
	return link_of(src, /datum/om/relation/action_granted_to)

/// A spell master's buttons (/datum/om/relation/spell_button_on).
/datum/proc/spell_buttons() as /list
	return linked_to(src, /datum/om/relation/spell_button_on)

/// The spell master a spell button is listed on (/datum/om/relation/spell_button_on).
/datum/proc/spell_master_of() as /atom/movable/screen/movable/spell_master
	return link_of(src, /datum/om/relation/spell_button_on)
