///Antag datum that is held on /datum/mind. Holds all the antag data.
/datum/antag_holder
	var/datum/changeling/changeling
	var/is_antag = FALSE

/datum/antag_holder/proc/apply_antags(mob/M)
	if(!M)
		return
	if(changeling())
		M.make_changeling()
		is_antag = TRUE

/datum/antag_holder/proc/is_antag()
	return is_antag

/// LC-refs: the mob's changeling state -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/antag_holder/proc/changeling() as /datum/changeling
	return changeling
