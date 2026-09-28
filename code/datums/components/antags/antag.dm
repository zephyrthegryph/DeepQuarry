///Component that holds the antag trait. This is the base version.
/datum/component/antag
	dupe_mode = COMPONENT_DUPE_UNIQUE //Only one type.

/datum/component/antag/Initialize()
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE

///Should never be destroyed as these are applied to the mind.
// ALLOW(lifecycle): antag state refuses deletion unless forced.
/datum/component/antag/Destroy(force = FALSE)
	if(!force)
		return QDEL_HINT_LETMELIVE
	. = ..()

///Antag datum that is held on /datum/mind. Holds all the antag data.
/datum/antag_holder
	var/changeling_handle
	var/is_antag = FALSE

/datum/antag_holder/proc/apply_antags(mob/M)
	if(!M)
		return
	if(changeling())
		M.make_changeling()
		is_antag = TRUE

/datum/antag_holder/proc/is_antag()
	return is_antag

/// LC-refs: the antagonist mob (our parent) (was a var copying parent).
/datum/component/antag/proc/owner() as /mob/living
	return parent

/// LC-refs: the mob's changeling component -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/antag_holder/proc/changeling() as /datum/component/antag/changeling
	return om_resolve(changeling_handle)
