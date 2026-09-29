///like normal callbacks but they also record their creation time for measurement purposes
///they also require the same usr/user that made the callback to both still exist and to still have a client in order to execute
/datum/callback/verb_callback
	///the tick this callback datum was created in. used for testing latency
	var/creation_time = 0
	///world.time and TICK_USAGE when this verb was queued for a later tick (SSverb_manager.queue_verb()): the tick meter
	///reads them when it runs, to record how long the verb waited.
	var/enqueue_time = 0
	var/enqueue_usage = 0

/datum/callback/verb_callback/New(thingtocall, proctocall, ...)
	creation_time = DS2TICKS(world.time)
	. = ..()

#ifndef UNIT_TESTS
/datum/callback/verb_callback/Invoke(...)
	var/mob/our_user = user
	if(QDELETED(our_user) || isnull(our_user.client))
		return
	var/mob/temp = usr
	. = ..()
	usr = temp

/datum/callback/verb_callback/InvokeAsync(...)
	var/mob/our_user = user
	if(QDELETED(our_user) || isnull(our_user.client))
		return
	var/mob/temp = usr
	. = ..()
	usr = temp
#endif
