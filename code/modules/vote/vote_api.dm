// The vote system's API (code/modules/vote/vote_service.dm declares the system).
//
//   SSvote.start_vote(vote, user) makes `vote` the running vote and starts it (`user`: who started it)
//   SSvote.get_active_vote()      the running vote, or null
//   SSvote.forget_vote(vote)      `vote` ended: the system stops tracking it

/datum/system/vote/proc/start_vote(datum/vote/V, mob/user)
	rel_set(src, nameof(active_vote), V)
	active_vote.start(user)
	wake_work_item(PROC_REF(tick_vote))

/// The running vote, or null.
/datum/system/vote/proc/get_active_vote()
	return active_vote

/// `V` is going away: stop tracking it when it is the running vote.
/datum/system/vote/proc/forget_vote(datum/vote/V)
	if(active_vote == V)
		rel_clear(src, nameof(active_vote))
