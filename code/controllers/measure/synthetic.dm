// Kernel measurement: synthetic player input for the benchmarks and the tests.
//
// A benchmark world has no clients, so nothing would ever record input latency. These drive the real paths: a
// click goes through the real /atom/Click (the router's stamps), a verb through the real input inbox
// (input_submit() and the phase K drain), so what the meter records is what a player's input would.
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

/// A no-op input in the synthetic lane.
/datum/input_event/synthetic
	driven = TRUE

/datum/input_event/synthetic/lane_key()
	return GLOB.km_synthetic

/datum/input_event/synthetic/resolve()
	GLOB.km_synthetic.verb_noop()
	return null

/// Queues a no-op input in the inbox the way one sent while the tick is busy is, whatever the usage now.
/proc/km_synthetic_verb()
	SSinput.room_override = FALSE
	input_submit(new /datum/input_event/synthetic)
	SSinput.room_override = null

#endif
