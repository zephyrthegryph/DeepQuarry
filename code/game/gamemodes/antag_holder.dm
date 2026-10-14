///Antag datum that is held on /datum/mind. Holds all the antag data.
/datum/antag_holder
	var/datum/changeling/changeling
	var/is_antag = FALSE

CAPABILITIES(/datum/antag_holder)
	ref_one(nameof(changeling))

/datum/antag_holder/proc/apply_antags(mob/M)
	if(!M)
		return
	if(changeling())
		M.make_changeling()
		is_antag = TRUE

/datum/antag_holder/proc/is_antag()
	return is_antag

/// The mob's changeling state (a relation view).
/datum/antag_holder/proc/changeling() as /datum/changeling
	return changeling
