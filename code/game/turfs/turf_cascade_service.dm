// Defaults are tuned for bluespace cascade
#define DEFAULT_CONVERSION_RATE 350
#define DEFAULT_CONVERSION_PROB 60
#define DEFAULT_CONVERSION_DELAY 2.5 SECONDS

// The turf cascade system (was SSturf_cascade): a spreading turf conversion (the supermatter cascade). It grows it
// every 0.2 s while one is running and parks otherwise. The API is in turf_cascade_api.dm.
SYSTEM_DEF(turf_cascade)
	name = "Turf Cascade"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	/// TRUE while a step that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE

	VAR_PRIVATE/next_group_time = 0 // cooldown: the next expansion
	VAR_PRIVATE/next_group_delay = DEFAULT_CONVERSION_DELAY

	VAR_PRIVATE/list/currentrun = list()
	VAR_PRIVATE/list/remaining_turf = list()
	VAR_PRIVATE/turf_iterations = 0

	VAR_PRIVATE/turf_replace_type = null // Turf path that turfs will be replaced with
	VAR_PRIVATE/conversion_probability = DEFAULT_CONVERSION_PROB // Randomized rate of conversion, 0 to 100
	VAR_PRIVATE/conversion_rate = DEFAULT_CONVERSION_RATE // Maximum number of turfs converted in each batch

/datum/system/turf_cascade/reactions()
	. = ..()
	. += every(2, PROC_REF(grow_cascade), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/turf_cascade/stat_entry(msg)
	return "[msg]C: [length(currentrun)] | R: [length(remaining_turf)] | R: [conversion_rate] | P: [turf_replace_type]"

/datum/system/turf_cascade/proc/has_work()
	return !isnull(turf_replace_type)

/datum/system/turf_cascade/proc/grow_cascade(dt)
	if(!has_work())
		return STEP_PARK
	var/resumed = resuming
	resuming = FALSE
	if(!resumed)
		if(!COOLDOWN_FINISHED(src, next_group_time)) // Wait for next expansion
			return STEP_DONE
		if(!turf_replace_type || (!length(remaining_turf) && !length(currentrun)))
			stop_cascade()
			return STEP_PARK
		COOLDOWN_START(src, next_group_time, next_group_delay)

		if(!length(currentrun) && length(remaining_turf) && turf_iterations <= 0)
			// Create a random list of tiles to expand with instead of doing it in order
			var/subtractive_rand_max = conversion_rate * (1 - (conversion_probability / 100))
			var/i = 10 // Always do at least a handful of the oldest, to avoid spots that linger unfilled
			while(i-- > 0)
				var/turf/next = remaining_turf[1]
				remaining_turf -= next
				currentrun += next
				if(!length(remaining_turf))
					break

			// Now for randomized growth. If we still have any left to grow into!
			if(length(remaining_turf))
				turf_iterations = max(1, conversion_rate - rand(0, subtractive_rand_max)) // Allows for slower rates and more messy growth, min 1, max conversion_rate

	while(turf_iterations-- > 0)
		var/turf/next = pick(remaining_turf)
		remaining_turf -= next
		currentrun += next
		if(!length(remaining_turf))
			break
		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD

	while(length(currentrun))
		var/turf/changing = currentrun[1]
		currentrun -= changing

		// Convert turf if we are not the replacement type already
		if(changing.type != turf_replace_type)
			changing.ChangeTurf(turf_replace_type)
			remaining_turf += changing.conversion_cascade_act(remaining_turf)

		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD

	return STEP_DONE

/// Called when we have no more turfs to convert, or an admin wants to emergency stop
/datum/system/turf_cascade/proc/stop_cascade()
	turf_replace_type = null
	remaining_turf.Cut()
	currentrun.Cut()
	conversion_rate = DEFAULT_CONVERSION_RATE
	conversion_probability = DEFAULT_CONVERSION_PROB
	next_group_delay = DEFAULT_CONVERSION_DELAY
