// Generic lifecycle notices, independent of gameplay consumers.
/// Published on an actor when one of its ops starts waiting (a timed wait() or a question; op_wait_begin()): the old do_after bar began.
ACTION(do_after_began, FIXED, notice = /datum/notice/do_after_began)

/// Published on an actor when one of its waiting ops ends, finished or interrupted (/datum/pending_op/proc/unregister()).
ACTION(do_after_ended, FIXED, notice = /datum/notice/do_after_ended)

/// Published on a datum when its destroy transaction begins (qdel()): the observers that still hold it let go.
ACTION(qdeleting, force, FIXED, notice = /datum/notice/qdeleting)

/// Published on a borrower when a datum it borrows through a relation is deleted (rel_teardown(), phase 4 of the target's destroy transaction), after the
/// borrower's var was cleared and its on_unlink() hook ran. `relation` is the borrower's var, `other_type` the type of the deleted target. A waiting op
/// that holds its target by relation hears this to run its on_interrupt() (/datum/pending_op/proc/borrow_ended()).
ACTION(borrow_ended, relation, other_type, FIXED, notice = /datum/notice/borrow_ended)
