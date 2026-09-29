// The crew transfer world service (fold wave F4; was SStransfer): the automatic transfer votes and
// the shift's hard end, checked every second by /datum/om/behaviour/world/transfer
// (code/datums/om/world_lanes.dm) while the round is running.
GLOBAL_DATUM_INIT(transfer_service, /datum/world_service/transfer, new)

/datum/world_service/transfer
	name = "Transfer"
	needs = list(/datum/controller/subsystem/atoms)
	lane = /datum/om/behaviour/world/transfer

	VAR_PRIVATE/timerbuffer = 0 //buffer for time check
	VAR_PRIVATE/currenttick = 0
	VAR_PRIVATE/shift_hard_end = 0
	VAR_PRIVATE/shift_last_vote = 0

/datum/world_service/transfer/initialize()
	initialized = TRUE
	timerbuffer = CONFIG_GET(number/vote_autotransfer_initial)
	shift_hard_end = CONFIG_GET(number/vote_autotransfer_initial) + (CONFIG_GET(number/vote_autotransfer_interval) * 2) // //Change this "1" to how many extend votes you want there to be.
	shift_last_vote = shift_hard_end - CONFIG_GET(number/vote_autotransfer_interval)
	log_world("World service [name] initialized: first vote at [timerbuffer / 600] min, hard end at [shift_hard_end / 600] min.")

/datum/world_service/transfer/service_step(resumed)
	currenttick = currenttick + 1
	if (round_duration_in_ds >= shift_last_vote - 2 MINUTES)
		shift_last_vote = 1000000000000 //Setting to a stupidly high number since it'll be not used again.
		to_chat(world, span_world(span_notice("Warning: This upcoming round-extend vote will be your last chance to vote for shift extension. Wrap up your scenes in the next 60 minutes if the round is extended.")))
	if (round_duration_in_ds >= shift_hard_end - 1 MINUTE)
		init_shift_change(null, 1)
		shift_hard_end = timerbuffer + CONFIG_GET(number/vote_autotransfer_interval) //If shuttle somehow gets recalled, let's force it to call again next time a vote would occur.
		timerbuffer = timerbuffer + CONFIG_GET(number/vote_autotransfer_interval) //Just to make sure a vote doesn't occur immediately afterwords.
	else if (round_duration_in_ds >= timerbuffer - 1 MINUTE)
		GLOB.vote_service.start_vote(new /datum/vote/crew_transfer)
		timerbuffer = timerbuffer + CONFIG_GET(number/vote_autotransfer_interval)
	return TRUE

/datum/world_service/transfer/proc/modify_hard_end(client/user)
	om_ask(user, /datum/om/prompt/number, PROC_REF(hard_end_entered), default = shift_hard_end / 600, title = "Shift End", message = "Modify the shift end timer (Input in Minutes)", requires = PROMPT_ADMIN(R_ADMIN|R_EVENT|R_SERVER))

/datum/world_service/transfer/proc/hard_end_entered(datum/om/prompt/number/ask)
	var/new_shift_end = ask.number
	if(!new_shift_end)
		return

	var/calculated_end = new_shift_end * 600

	shift_hard_end = calculated_end
	shift_last_vote = calculated_end
	timerbuffer = calculated_end

///Accessor proc for getting the shift hard end.
/datum/world_service/transfer/proc/get_hard_end()
	return shift_hard_end
