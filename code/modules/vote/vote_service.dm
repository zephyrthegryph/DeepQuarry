// The vote world service (was SSvote): the running vote counts down every second, parked while
// no vote is running.
GLOBAL_DATUM_INIT(vote_service, /datum/world_service/vote, new)

/datum/world_service/vote
	name = "Vote"
	lane = /datum/om/behaviour/world/vote
	on_demand = TRUE

	var/datum/vote/active_vote

/datum/world_service/vote/service_step(resumed)
	if(active_vote)
		active_vote.tick()
	return TRUE

/datum/world_service/vote/proc/start_vote(datum/vote/V, mob/user)
	own_set(src, nameof(active_vote), V)
	active_vote.start(user)
	demand()

/datum/world_service/vote/has_work()
	return !isnull(active_vote)

/// vote
/datum/om/behaviour/world/vote
	name = "world: vote"
	every = 1 SECOND
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/vote/service()
	return GLOB.vote_service

