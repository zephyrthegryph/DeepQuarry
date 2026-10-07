// Queued runechat messages (was SSrunechat): delivered every tick, parked while the queue is empty. The API is in
// runechat_api.dm.
SYSTEM_DEF(runechat)
	name = "Runechat"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	VAR_PRIVATE/list/message_queue = list() // rows list(owner, PROC_REF, with), oldest first
	/// The next message to deliver while a pass runs (dequeue() keeps it pointing at the same message).
	VAR_PRIVATE/deliver_cursor = 1

/datum/system/runechat/reactions()
	. = ..()
	. += every(1, PROC_REF(deliver_messages), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Delivers the queued messages oldest first (a bubble queued first appears first), through an index cursor: the delivered prefix is cut once per pass,
/// not one element at a time.
/datum/system/runechat/proc/deliver_messages(dt)
	if(!length(message_queue))
		deliver_cursor = 1
		return STEP_PARK
	var/step_result = STEP_PARK
	while(deliver_cursor <= length(message_queue))
		var/list/queued_message = message_queue[deliver_cursor]
		deliver_cursor++
		var/datum/queued_owner = queued_message[1]
		if(!QDELETED(queued_owner))
			call(queued_owner, queued_message[2])(arglist(queued_message[3] || list()))
		if(KERNEL_OVER_BUDGET)
			step_result = STEP_YIELD
			break
	message_queue.Cut(1, min(deliver_cursor, length(message_queue) + 1))
	deliver_cursor = 1
	return step_result
