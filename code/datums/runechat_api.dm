// The runechat system's API (code/datums/runechat_service.dm declares the system).
//
//   SSrunechat.enqueue(callable)   queue a message's finish callback (an om_callable() spec); the kernel delivers it
//   SSrunechat.dequeue(callable)   drop a queued callback whose message went away first

/datum/system/runechat/proc/enqueue(list/callable)
	message_queue += list(callable)
	wake_work_item(PROC_REF(deliver_messages))

/datum/system/runechat/proc/dequeue(list/callable)
	message_queue -= list(callable)
