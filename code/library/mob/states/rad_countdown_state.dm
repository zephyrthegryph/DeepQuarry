// rad_countdown: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, rad_countdown, field), write with STATE_SET(M, rad_countdown, field, value), end it with rad_countdown_clear(M).

/datum/rad_countdown_state
	var/rad_countdown_minimum = 0
	/// / The countdown before a target can be irradiated. / Started by the radiation subsystem when pulse information has a minimum exposure time; / clears itself after a while. Mob state plus one keyed after() timer: the subsystem / asks radiation_countdown_check() directly. / world.time the countdown started, or 0 when none is running: the lazy state field rad_countdown_started.
	var/rad_countdown_started = 0

/mob/living
	var/datum/rad_countdown_state/rad_countdown
