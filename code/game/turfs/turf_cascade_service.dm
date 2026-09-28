// Defaults are tuned for bluespace cascade
#define DEFAULT_CONVERSION_RATE 350
#define DEFAULT_CONVERSION_PROB 60
#define DEFAULT_CONVERSION_DELAY 2.5 SECONDS

// The turf cascade world service (fold wave F4; was SSturf_cascade): a spreading turf conversion
// (the supermatter cascade). /datum/om/behaviour/world/turf_cascade (code/datums/om/world_lanes.dm)
// grows it every 0.2 s while one is running and parks otherwise.
GLOBAL_DATUM_INIT(turf_cascade_service, /datum/world_service/turf_cascade, new)

/datum/world_service/turf_cascade
	name = "Turf Cascade"
	lane = /datum/om/behaviour/world/turf_cascade
	on_demand = TRUE

	VAR_PRIVATE/last_group_time = 0
	VAR_PRIVATE/next_group_delay = DEFAULT_CONVERSION_DELAY

	VAR_PRIVATE/list/currentrun = list()
	VAR_PRIVATE/list/remaining_turf = list()
	VAR_PRIVATE/turf_iterations = 0

	VAR_PRIVATE/turf_replace_type = null // Turf path that turfs will be replaced with
	VAR_PRIVATE/conversion_probability = DEFAULT_CONVERSION_PROB // Randomized rate of conversion, 0 to 100
	VAR_PRIVATE/conversion_rate = DEFAULT_CONVERSION_RATE // Maximum number of turfs converted in each batch

/datum/world_service/turf_cascade/stat_line()
	return "C: [length(currentrun)] | R: [length(remaining_turf)] | R: [conversion_rate] | P: [turf_replace_type]"

/datum/world_service/turf_cascade/has_work()
	return !isnull(turf_replace_type)

/datum/world_service/turf_cascade/service_step(resumed)
	if(!resumed)
		if(world.time < (last_group_time + next_group_delay)) // Wait for next expansion
			return TRUE
		if(!turf_replace_type || (!length(remaining_turf) && !length(currentrun)))
			stop_cascade()
			return TRUE
		last_group_time = world.time

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
		if(TICK_CHECK)
			return FALSE

	while(length(currentrun))
		var/turf/changing = currentrun[1]
		currentrun -= changing

		// Convert turf if we are not the replacement type already
		if(changing.type != turf_replace_type)
			changing.ChangeTurf(turf_replace_type)
			remaining_turf += changing.conversion_cascade_act(remaining_turf)

		if(TICK_CHECK)
			return FALSE

	return TRUE

/// Starts the turf cascade and wakes the service's lane. If a cascade is already in process, it will not allow another another to start.
/datum/world_service/turf_cascade/proc/start_cascade(turf/start_turf, turf_path, max_per_fire = DEFAULT_CONVERSION_RATE, time_delay = DEFAULT_CONVERSION_DELAY, convert_probability = DEFAULT_CONVERSION_PROB)
	if(turf_replace_type)
		return
	if(!isturf(start_turf) || !max_per_fire)
		return
	turf_replace_type = turf_path
	remaining_turf.Add(start_turf)
	conversion_rate = max_per_fire
	conversion_probability = convert_probability
	next_group_delay = DEFAULT_CONVERSION_DELAY
	log_world("Turf cascade started at [AREACOORD(start_turf)] converting to [turf_path].")
	demand()

/// Called when we have no more turfs to convert, or an admin wants to emergency stop
/datum/world_service/turf_cascade/proc/stop_cascade()
	turf_replace_type = null
	remaining_turf.Cut()
	currentrun.Cut()
	conversion_rate = DEFAULT_CONVERSION_RATE
	conversion_probability = DEFAULT_CONVERSION_PROB
	next_group_delay = DEFAULT_CONVERSION_DELAY

#undef DEFAULT_CONVERSION_RATE
#undef DEFAULT_CONVERSION_PROB
#undef DEFAULT_CONVERSION_DELAY
