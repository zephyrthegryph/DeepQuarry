// Generic lifecycle notices, independent of gameplay consumers.
/// Published on an actor when one of its ops starts waiting (a timed wait() or a question; op_wait_begin()): the old do_after bar began.
ACTION(do_after_began, FIXED, notice = /datum/notice/do_after_began)

/// Published on an actor when one of its waiting ops ends, finished or interrupted (/datum/pending_op/proc/unregister()).
ACTION(do_after_ended, FIXED, notice = /datum/notice/do_after_ended)

/// Published on a datum when its destroy transaction begins (qdel()): the observers that still hold it let go.
ACTION(qdeleting, force, FIXED, notice = /datum/notice/qdeleting)
