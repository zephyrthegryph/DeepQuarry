/datum/repository/New()
	return

/datum/cache_entry
	COOLDOWN_DECLARE(timestamp)
	var/data

/datum/cache_entry/New()
	STAMP(src, timestamp, CLOCK_WORLD)

/datum/cache_entry/proc/is_valid()
	return FALSE

/datum/cache_entry/valid_until/New(valid_duration)
	..()
	timestamp += valid_duration

/datum/cache_entry/valid_until/is_valid()
	return COOLDOWN_RUNNING(src, timestamp)
