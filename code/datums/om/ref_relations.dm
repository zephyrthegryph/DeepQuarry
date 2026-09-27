// Typed accessors for the relations that replaced object-typed vars in the LC-refs sweep
// (doc/rewrite/lifecycle.md sec 4, object_model_core.md sec 7). Each reads the edge; nothing
// mirrors it into a var. Raw om_relation_of()/om_related_to() calls live here, in
// code/datums/om, as tools/ci/api_lints.py (raw_relation) requires.

/// The movable a throw is carrying (/datum/om/relation/throw_of).
/datum/proc/throw_subject() as /atom/movable
	return om_relation_of(src, /datum/om/relation/throw_of)
