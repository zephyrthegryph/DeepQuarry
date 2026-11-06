// The runechat system's API (code/datums/runechat_service.dm declares the system).
//
//   SSrunechat.enqueue(owner, PROC_REF(finish), list(args))   queue a message's finish call (owner.finish(args...)); the kernel delivers it, oldest first.
//                                                             Returns the queued row.
//   SSrunechat.dequeue(row)                                   drop a queued call whose message went away first

/datum/system/runechat/proc/enqueue(datum/owner, handler, list/with = null)
	var/list/row = list(owner, handler, with)
	message_queue += list(row)
	wake_work_item(PROC_REF(deliver_messages))
	return row

/datum/system/runechat/proc/dequeue(list/row)
	var/at = message_queue.Find(row)
	if(!at)
		return
	message_queue.Cut(at, at + 1)
	if(at < deliver_cursor)
		deliver_cursor-- // a message before the cursor left: the next one slid down
