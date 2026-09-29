// Should be more than any minimum exposure time coming in
#define TIME_UNTIL_DELETION (10 SECONDS)

/// The countdown before a target can be irradiated.
/// Started by the radiation subsystem when pulse information has a minimum exposure time;
/// clears itself after a while. Mob state plus one om_after_replace() timer: the subsystem
/// asks radiation_countdown_check() directly.
/mob/living
	/// world.time the countdown started, or 0 when none is running.
	var/rad_countdown_started = 0
	/// The shortest minimum time before being irradiated. An attempted irradiation outside
	/// this timeframe goes through.
	var/rad_countdown_minimum = 0

/// Starts (or keeps) the countdown with `minimum_exposure_time`.
/mob/living/proc/radiation_countdown_start(minimum_exposure_time)
	if(!rad_countdown_started)
		rad_countdown_started = world.time
		rad_countdown_minimum = minimum_exposure_time
	else
		rad_countdown_minimum = min(rad_countdown_minimum, minimum_exposure_time)
	om_after_replace(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear))

/mob/living/proc/radiation_countdown_clear()
	rad_countdown_started = 0
	rad_countdown_minimum = 0

/// While a countdown runs: CANCEL_IRRADIATION until the minimum exposure time has passed,
/// then SKIP_MINIMUM_EXPOSURE_TIME_CHECK. 0 when no countdown runs.
/mob/living/proc/radiation_countdown_check(datum/radiation_pulse_information/pulse_information)
	if(!rad_countdown_started)
		return 0
	rad_countdown_minimum = min(rad_countdown_minimum, pulse_information.minimum_exposure_time)
	om_after_replace(src, TIME_UNTIL_DELETION, TYPE_PROC_REF(/mob/living, radiation_countdown_clear))
	// Played with fire, now you might be getting irradiated.
	if (ELAPSED(src, rad_countdown_started, CLOCK_WORLD) >= rad_countdown_minimum)
		return SKIP_MINIMUM_EXPOSURE_TIME_CHECK
	return CANCEL_IRRADIATION

#undef TIME_UNTIL_DELETION
