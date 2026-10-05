// The crew transfer system (was SStransfer): the automatic transfer votes and the shift's hard end, checked every
// second while the round is running. The API is in transfer_api.dm.
SYSTEM_DEF(transfer)
	name = "Transfer"
	needs = list(/datum/system/atoms)
	periodic_runlevels = RUNLEVEL_GAME

	VAR_PRIVATE/timerbuffer = 0 //buffer for time check
	VAR_PRIVATE/currenttick = 0
	VAR_PRIVATE/shift_hard_end = 0
	VAR_PRIVATE/shift_last_vote = 0

/datum/system/transfer/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(check_transfer), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/transfer/initialize()
	initialized = TRUE
	timerbuffer = CONFIG_GET(number/vote_autotransfer_initial)
	shift_hard_end = CONFIG_GET(number/vote_autotransfer_initial) + (CONFIG_GET(number/vote_autotransfer_interval) * 2) // //Change this "1" to how many extend votes you want there to be.
	shift_last_vote = shift_hard_end - CONFIG_GET(number/vote_autotransfer_interval)
	log_world("System [name] initialized: first vote at [timerbuffer / 600] min, hard end at [shift_hard_end / 600] min.")

/datum/system/transfer/proc/check_transfer(dt)
	currenttick = currenttick + 1
	if (round_duration_in_ds >= shift_last_vote - 2 MINUTES)
		shift_last_vote = 1000000000000 //Setting to a stupidly high number since it'll be not used again.
		to_chat(world, span_world(span_notice("Warning: This upcoming round-extend vote will be your last chance to vote for shift extension. Wrap up your scenes in the next 60 minutes if the round is extended.")))
	if (round_duration_in_ds >= shift_hard_end - 1 MINUTE)
		init_shift_change(null, 1)
		shift_hard_end = timerbuffer + CONFIG_GET(number/vote_autotransfer_interval) //If shuttle somehow gets recalled, let's force it to call again next time a vote would occur.
		timerbuffer = timerbuffer + CONFIG_GET(number/vote_autotransfer_interval) //Just to make sure a vote doesn't occur immediately afterwords.
	else if (round_duration_in_ds >= timerbuffer - 1 MINUTE)
		SSvote.start_vote(new /datum/vote/crew_transfer)
		timerbuffer = timerbuffer + CONFIG_GET(number/vote_autotransfer_interval)
	return STEP_DONE

/datum/system/transfer/proc/hard_end_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_shift_end = A.answer.value
	if(!new_shift_end)
		return

	var/calculated_end = new_shift_end * 600

	shift_hard_end = calculated_end
	shift_last_vote = calculated_end
	timerbuffer = calculated_end
