// Queued runechat messages (was SSrunechat): delivered every tick, parked while the queue is empty. The API is in
// runechat_api.dm.
SYSTEM_DEF(runechat)
	name = "Runechat"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	VAR_PRIVATE/list/message_queue = list() // om_callable() specs

/datum/system/runechat/reactions()
	. = ..()
	. += every(1, PROC_REF(deliver_messages), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/runechat/proc/deliver_messages(dt)
	if(!length(message_queue))
		return STEP_PARK
	while(length(message_queue))
		var/list/queued_message = message_queue[length(message_queue)]
		om_run(queued_message)
		message_queue.len--
		if(KERNEL_OVER_BUDGET)
			return STEP_YIELD
	return STEP_PARK
