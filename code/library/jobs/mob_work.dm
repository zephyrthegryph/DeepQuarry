// Shared timed-work policy for mob actions.

/// A mob's timed work on a turf (spinning a web, laying eggs, building): it stays within one tile, conscious; the claim keeps a second
/// worker off the turf; death or deletion cancels it. The actor's procs finish or clean up.
/datum/task/mob_work
	abstract_type = /datum/task/mob_work
	duration = 5 SECONDS
	claims = TRUE
	claims_actor = TRUE // the worker is busy: its AI stays still, and it can't start a second job

/datum/task/mob_work/check_reason()
	var/mob/M = actor
	if(!istype(M) || M.stat != CONSCIOUS)
		return "not conscious"
	if(!target || QDELETED(target))
		return "it's gone"
	var/turf/at = get_turf(M)
	var/turf/tt = get_turf(target)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > 1)
		return "too far away"
	return null

/datum/task/mob_work/watched_reads()
	. = list(list(actor, OP_KEEP_MOVED), list(actor, "stat"))
	if(target && target != actor)
		. += list(list(target, OP_KEEP_MOVED))
