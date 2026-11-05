// Should be more than any minimum exposure time coming in
#define TIME_UNTIL_DELETION (10 SECONDS)


/// Starts (or keeps) the countdown with `minimum_exposure_time`.
/mob/living/proc/radiation_countdown_start(minimum_exposure_time)
	if(!STATE_GET(src, rad_countdown, rad_countdown_started))
		STATE_SET(src, rad_countdown, rad_countdown_started, world.time)
		STATE_SET(src, rad_countdown, rad_countdown_minimum, minimum_exposure_time)
	else
		STATE_SET(src, rad_countdown, rad_countdown_minimum, min(STATE_GET(src, rad_countdown, rad_countdown_minimum), minimum_exposure_time))
	after(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear), key = "radiation_countdown_clear")

/mob/living/proc/radiation_countdown_clear()
	STATE_SET(src, rad_countdown, rad_countdown_started, 0)
	STATE_SET(src, rad_countdown, rad_countdown_minimum, 0)

/// While a countdown runs: CANCEL_IRRADIATION until the minimum exposure time has passed,
/// then SKIP_MINIMUM_EXPOSURE_TIME_CHECK. 0 when no countdown runs.
/mob/living/proc/radiation_countdown_check(datum/radiation_pulse_information/pulse_information)
	if(!STATE_GET(src, rad_countdown, rad_countdown_started))
		return 0
	STATE_SET(src, rad_countdown, rad_countdown_minimum, min(STATE_GET(src, rad_countdown, rad_countdown_minimum), pulse_information.minimum_exposure_time))
	after(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear), key = "radiation_countdown_clear")
	// Played with fire, now you might be getting irradiated.
	if (world.time - STATE_GET(src, rad_countdown, rad_countdown_started) >= STATE_GET(src, rad_countdown, rad_countdown_minimum))
		return SKIP_MINIMUM_EXPOSURE_TIME_CHECK
	return CANCEL_IRRADIATION

#undef TIME_UNTIL_DELETION
