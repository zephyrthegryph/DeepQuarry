// Kernel measurement: synthetic player input for the benchmarks and the tests.
//
// A benchmark world has no clients, so nothing would ever record input latency. These drive the real paths: a
// click goes through the real /atom/Click (the router's stamps), a verb through the real verb queue
// (SSverb_manager.lane.queue_verb() and run_verb_queue()), so what the meter records is what a player's input would.
// Compiled into test and benchmark builds only.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

GLOBAL_DATUM_INIT(km_synthetic, /datum/km_synthetic, new)

/// The target of synthetic verbs.
/datum/km_synthetic
	/// Synthetic verbs that have run.
	var/verbs_run = 0

/datum/km_synthetic/proc/verb_noop()
	verbs_run++

/// `user` clicks `target` as if a client had: /atom/Click under its own usr. The user is restored after.
/proc/km_synthetic_click(mob/user, atom/target)
	var/mob/saved_user = usr
	usr = user
	target.Click(get_turf(target), "mapwindow.map", "")
	usr = saved_user

/// Queues a no-op verb on SSverb_manager the way a verb sent while the tick is busy is, whatever the usage now.
/proc/km_synthetic_verb()
	SSverb_manager.lane.queue_verb(VERB_CALLBACK(GLOB.km_synthetic, TYPE_PROC_REF(/datum/km_synthetic, verb_noop)))

#endif
