// The vote system (was SSvote): the running vote counts down every second, parked while no vote is running.
// The API is in vote_api.dm.
SYSTEM_DEF(vote)
	name = "Vote"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	VAR_PRIVATE/datum/vote/active_vote

/datum/system/vote/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(tick_vote), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/vote/proc/tick_vote(dt)
	if(!active_vote)
		return STEP_PARK
	active_vote.tick()
	return isnull(active_vote) ? STEP_PARK : STEP_DONE
