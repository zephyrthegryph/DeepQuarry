// Generic lifecycle notices, independent of gameplay consumers.
/// Published on an actor when one of its ops starts waiting (a timed wait() or a question; op_wait_begin()): the old do_after bar began.
/datum/notice/do_after_began

/// Published on an actor when one of its waiting ops ends, finished or interrupted (/datum/pending_op/proc/unregister()).
/datum/notice/do_after_ended

/datum/notice/qdeleting
	var/force

/datum/notice/qdeleting/fill(force)
	src.force = force
