// Should be more than any minimum exposure time coming in
#define TIME_UNTIL_DELETION (10 SECONDS)

/// The countdown before a target can be irradiated.
/// Started by the radiation subsystem when pulse information has a minimum exposure time;
/// clears itself after a while. Mob state plus one keyed after() timer: the subsystem
/// asks radiation_countdown_check() directly.
/// Exposure state exists only while this mob has a running countdown.
sparse(/mob/living, rad_countdown_started, type = num)
sparse(/mob/living, rad_countdown_minimum, type = num)

/// Starts (or keeps) the countdown with `minimum_exposure_time`.
/mob/living/proc/radiation_countdown_start(minimum_exposure_time)
	if(!sparse_get_or(src, rad_countdown_started, 0))
		sparse_set_or(src, rad_countdown_started, EXPIRY_NOW(src, CLOCK_WORLD), 0)
		sparse_set_or(src, rad_countdown_minimum, minimum_exposure_time, 0)
	else
		sparse_set_or(src, rad_countdown_minimum, min(sparse_get_or(src, rad_countdown_minimum, 0), minimum_exposure_time), 0)
	after(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear), key = "radiation_countdown_clear")

/mob/living/proc/radiation_countdown_clear()
	sparse_set(src, rad_countdown_started, null)
	sparse_set(src, rad_countdown_minimum, null)

/// While a countdown runs: CANCEL_IRRADIATION until the minimum exposure time has passed,
/// then SKIP_MINIMUM_EXPOSURE_TIME_CHECK. 0 when no countdown runs.
/mob/living/proc/radiation_countdown_check(datum/radiation_pulse_information/pulse_information)
	if(!sparse_get_or(src, rad_countdown_started, 0))
		return 0
	sparse_set_or(src, rad_countdown_minimum, min(sparse_get_or(src, rad_countdown_minimum, 0), pulse_information.minimum_exposure_time), 0)
	after(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear), key = "radiation_countdown_clear")
	// Played with fire, now you might be getting irradiated.
	if (ELAPSED_SINCE(src, sparse_get_or(src, rad_countdown_started, 0), CLOCK_WORLD) >= sparse_get_or(src, rad_countdown_minimum, 0))
		return SKIP_MINIMUM_EXPOSURE_TIME_CHECK
	return CANCEL_IRRADIATION

#undef TIME_UNTIL_DELETION
