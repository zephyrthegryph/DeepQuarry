SYSTEM_DEF(lighting)
	name = "Lighting"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	init_stage = INITSTAGE_MAIN
	needs = list(
		/datum/system/air
	)
	wait = 1
	periodic_runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY // Do some work during lobby waiting period. May as well.
	var/sun_mult = 1.0
	var/static/list/sources_queue = list() // List of lighting sources queued for update.
	var/static/list/corners_queue = list() // List of lighting corners queued for update.
	var/static/list/objects_queue = list() // List of lighting objects queued for update.
	var/static/list/sunlight_queue = list() // List of turfs that are affected by sunlight
	var/static/list/sunlight_queue_active = list() // List of turfs that need to have their sunlight updated
	var/list/planet_shandlers = list() // Precomputed lighting values for tiles only affected by the sun
	var/list/z_to_pshandler = list()

/datum/system/lighting/stat_entry(msg)
	msg = "L:[length(sources_queue)]|C:[length(corners_queue)]|O:[length(objects_queue)]"
	return ..()


/datum/system/lighting/initialize()
	if(!initialized)
		initialized = TRUE
		create_all_lighting_objects()

	for(var/datum/planet/planet in planets_planets())
		if(!planet_shandlers[planet])
			planet_shandlers[planet] = new /datum/planet_sunlight_handler(planet)

	light_step(0, TRUE)
	sunlight_queue_active += sunlight_queue + sunlight_queue // Run through shandler's twice during lobby wait to get some initial computation out of the way. After these two, the sunlight system will run MUCH faster.


/// The light queues drain every tick (it was SSlighting's SS_TICKER fire()).
/datum/system/lighting/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(light_step), when = PROC_REF(work_ready), phase = KERNEL_PHASE_K, lane = LANE_PRESENTATION)

// Lighting folds in wave F5, after phase 4f makes it a Rust field
/datum/system/lighting/proc/light_step(dt, init_tick_checks)
	KERNEL_SPLIT_TICK_INIT(4)
	if(!init_tick_checks)
		KERNEL_SPLIT_TICK

	var/list/queue = sources_queue
	var/i = 0

	// UPDATE SOURCE QUEUE
	queue = sources_queue
	while(i < length(queue)) //we don't use for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/light_source/L = queue[i]
		// Which sources keep being re-queued (the churn metrics; world Topic "lightcensus").
		CHURN_COUNT(lights, L.source_atom ? L.source_atom.type : /datum/light_source)
		L.update_corners()

		if(!QDELETED(L))
			L.needs_update = LIGHTING_NO_UPDATE
		else
			i -= 1 // update_corners() has removed L from the list, move back so we don't overflow or skip the next element

		// At init the whole queue drains in one pass (S10b: no stoplag yield); afterwards the MC budget splits it.
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			break
	if (i)
		queue.Cut(1, i + 1)
		i = 0

	if(!init_tick_checks)
		KERNEL_SPLIT_TICK

	// UPDATE CORNERS QUEUE
	queue = corners_queue
	while(i < length(queue)) //we don't use for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/lighting_corner/C = queue[i]
		C.needs_update = FALSE //update_objects() can call qdel if the corner is storing no data
		C.update_objects()

		// At init the whole queue drains in one pass (S10b: no stoplag yield); afterwards the MC budget splits it.
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			break
	if (i)
		queue.Cut(1, i + 1)
		i = 0

	if(!init_tick_checks)
		KERNEL_SPLIT_TICK

	// UPDATE OBJECTS QUEUE
	queue = objects_queue
	while(i < length(queue)) //we don't use for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/lighting_object/O = queue[i]
		if (QDELETED(O))
			continue
		O.update()
		O.needs_update = FALSE

		// At init the whole queue drains in one pass (S10b: no stoplag yield); afterwards the MC budget splits it.
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			break
	if (i)
		queue.Cut(1, i + 1)
		i = 0


	if(!init_tick_checks)
		KERNEL_SPLIT_TICK

	// UPDATE SUNLIGHT QUEUE
	queue = sunlight_queue_active
	while(i < length(queue)) //we don't use for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/sunlight_handler/shandler = queue[i]
		if (QDELETED(shandler))
			continue
		shandler.sunlight_update()

		// At init the whole queue drains in one pass (S10b: no stoplag yield); afterwards the MC budget splits it.
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			break
	if (i)
		queue.Cut(1, i + 1)

/datum/system/lighting/proc/update_sunlight(datum/planet_sunlight_handler/pshandler)
	if(istype(pshandler))
		pshandler.update_sun()
		if(length(pshandler.shandlers)) sunlight_queue_active |= pshandler.shandlers
	else
		for(var/datum/planet/planet in planet_shandlers)
			var/datum/planet_sunlight_handler/planet_shandler = planet_shandlers[planet]
			planet_shandler.update_sun()
		sunlight_queue_active = sunlight_queue.Copy()

/datum/system/lighting/proc/get_pshandler_planet(datum/planet/planet)
	if(!planet_shandlers[planet])
		planet_shandlers[planet] = new /datum/planet_sunlight_handler(planet)
	return planet_shandlers[planet]

//Wrapper for the list, because these type of lists are just awful to work with
//Also takes care of initialization order issues
/datum/system/lighting/proc/get_pshandler_z(z)
	if(z > length(z_to_pshandler))
		z_to_pshandler.len = z
	var/datum/planet_sunlight_handler/pshandler = z_to_pshandler[z]
	if(istype(pshandler))
		return pshandler
	else if(SSplanets.initialized && length(planets_z_to_planet()) >= z && SSplanets.z_to_planet[z])
		var/datum/planet/P = planets_z_to_planet()[z]
		if(istype(P))
			pshandler = get_pshandler_planet(P)
			z_to_pshandler[z] = pshandler
	return pshandler
