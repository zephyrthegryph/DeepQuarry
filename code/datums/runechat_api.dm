// The runechat system's API (code/datums/runechat_service.dm declares the system).
//
//   SSrunechat.enqueue(callable)   queue a message's finish callback (an om_callable() spec); the kernel delivers it
//   SSrunechat.dequeue(callable)   drop a queued callback whose message went away first

/datum/system/runechat/proc/enqueue(list/callable)
	message_queue += list(callable)
	wake_work_item(PROC_REF(deliver_messages))

/datum/system/runechat/proc/dequeue(list/callable)
	var/at = message_queue.Find(callable)
	if(!at)
		return
	message_queue.Cut(at, at + 1)
	if(at < deliver_cursor)
		deliver_cursor-- // a message before the cursor left: the next one slid down
