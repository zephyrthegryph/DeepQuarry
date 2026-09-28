// Queued runechat messages (was SSrunechat): delivered every tick, parked while the queue is empty.
GLOBAL_DATUM_INIT(runechat_service, /datum/world_service/runechat, new)

/datum/world_service/runechat
	name = "Runechat"
	lane = /datum/om/behaviour/world/runechat
	on_demand = TRUE

	var/list/datum/callback/message_queue = list() // ALLOW(instance_list): d: world service singleton

/datum/world_service/runechat/has_work()
	return length(message_queue)

/datum/world_service/runechat/service_step(resumed)
	while(length(message_queue))
		var/datum/callback/queued_message = message_queue[length(message_queue)]
		queued_message.Invoke()
		message_queue.len--
		if(TICK_CHECK)
			return FALSE
	return TRUE

/// runechat (was SSrunechat).
/datum/om/behaviour/world/runechat
	name = "world: runechat"
	every = 1

/datum/om/behaviour/world/runechat/service()
	return GLOB.runechat_service

REF_OWNED_LIST(/datum/world_service/runechat, "message_queue")
