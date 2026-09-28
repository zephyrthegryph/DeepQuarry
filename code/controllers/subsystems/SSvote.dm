SUBSYSTEM_DEF(vote)
	name = "Vote"
	flags = SS_NO_INIT | SS_NO_FIRE // countdown: /datum/om/behaviour/world/feature/vote (1 s)

	var/datum/vote/active_vote

/datum/controller/subsystem/vote/lane_step(resumed)
	if(active_vote)
		active_vote.tick()
	return TRUE

/datum/controller/subsystem/vote/proc/start_vote(datum/vote/V)
	active_vote = V
	active_vote.start()
