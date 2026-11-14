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
	var/static/list/sources_queue_near = list() // Handles (handle_of()) of the queued sources standing in a chunk some viewer holds: drained before sources_queue (queue_source()).
	var/static/list/corners_queue = list() // List of lighting corners queued for update.
	var/static/list/objects_queue = list() // List of lighting objects queued for update.
	var/static/list/sunlight_queue_active = list() // List of turfs that need to have their sunlight updated
	var/list/planet_shandlers = list() // Precomputed lighting values for tiles only affected by the sun
	var/list/z_to_pshandler = list()

/datum/system/lighting/stat_entry(msg)
	msg = "L:[length(sources_queue_near)]+[length(sources_queue)]|C:[length(corners_queue)]|O:[length(objects_queue)]"
	return ..()


/datum/system/lighting/initialize()
	#ifdef UNIT_TESTS
	if(unit_test_boot_skips(BOOT_NEED_LIGHTING))
		// initialized stays FALSE, so no turf or light grows a lighting object later either: the world is consistently unlit.
		unit_test_boot_skipped(BOOT_NEED_LIGHTING, "create_all_lighting_objects (Lighting stays uninitialized)")
	else if(!initialized)
		initialized = TRUE
		create_all_lighting_objects()
	#else
	if(!initialized)
		initialized = TRUE
		GLOB.client_lighting = TRUE // client-rendered glows from round start: no lighting objects (client_glow.dm)
		log_world("client lighting: on")
		lighting_smooth_apply()
		create_all_lighting_objects()
	#endif

	for(var/datum/planet/planet in planets_planets())
		if(!planet_shandlers[planet])
			planet_shandlers[planet] = new /datum/planet_sunlight_handler(planet)

	light_step(0, TRUE)
	sunlight_queue_active += members_of(SUNLIGHT_AWAKE_KEY) + members_of(SUNLIGHT_AWAKE_KEY) // Run through shandler's twice during lobby wait to get some initial computation out of the way. After these two, the sunlight system will run MUCH faster.


/// The light queues drain every tick (it was SSlighting's SS_TICKER fire()).
/datum/system/lighting/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(light_step), when = PROC_REF(work_ready), phase = KERNEL_PHASE_K, lane = LANE_PRESENTATION)

// Lighting folds in wave F5, after phase 4f makes it a Rust field
/datum/system/lighting/proc/light_step(dt, init_tick_checks)
	KERNEL_SPLIT_TICK_INIT(4)
	if(!init_tick_checks)
		KERNEL_SPLIT_TICK

	var/step_start = TICK_USAGE
	var/start_sources = length(sources_queue) + length(sources_queue_near)
	var/start_corners = length(corners_queue)
	var/start_objects = length(objects_queue)
	var/start_sunlight = length(sunlight_queue_active)
	var/start_near = length(sources_queue_near)
	var/list/queue
	var/i = 0

	// UPDATE SOURCE QUEUE: the lights a viewer holds the chunk of first (a player's own light and the shadows round it never wait behind a power flip across the map), the rest after
	if(!drain_sources(sources_queue_near, init_tick_checks, TRUE))
		drain_sources(sources_queue, init_tick_checks)

	var/sources_ms = TICK_USAGE_TO_MS(step_start)
	var/flush_started = TICK_USAGE
	client_glow_reconsider_flush(init_tick_checks) // client lighting: the opacity changes since the last step, one redraw per light (client_shadow.dm)
	var/flush_ms = TICK_USAGE_TO_MS(flush_started)

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

	var/smooth_started = TICK_USAGE
	lighting_smooth_step(init_tick_checks) // corner mode: the turfs sampled since the last step, their corners and tiles (lighting_smoothing.dm)

	// A step over a whole tick: what it had to do and what it left, to tell one huge element from a budget that did not bind.
	if(!init_tick_checks && TICK_USAGE_TO_MS(step_start) > world.tick_lag * 100)
		log_world("light_step took [TICK_USAGE_TO_MS(step_start)]ms (limit [Kernel.current_ticklimit]%); parts: sources [round(sources_ms, 0.1)], glow flush [round(flush_ms, 0.1)] ([GLOB.client_glow_last_flush_redrawn] light(s) redrawn, [GLOB.client_glow_last_flush_sighted] viewer(s) took sight), smoothing [round(TICK_USAGE_TO_MS(smooth_started), 0.1)]; start: sources [start_sources] ([start_near] near a viewer), corners [start_corners], objects [start_objects], sunlight [start_sunlight]; left: sources [length(sources_queue) + length(sources_queue_near)], corners [length(corners_queue)], objects [length(objects_queue)], sunlight [length(sunlight_queue_active)]")

/// Drains the light sources in `queue` (one of the two source queues) in order until it is empty or the tick's budget is spent. TRUE when the budget stopped it
/// with sources left. `handles`: the queue holds handles (the near queue), not the sources.
/datum/system/lighting/proc/drain_sources(list/queue, init_tick_checks, handles = FALSE)
	var/i = 0
	while(i < length(queue)) //we don't use for loop here because i cannot be changed during an iteration
		i += 1

		var/datum/light_source/L = handles ? handle_get(queue[i]) : queue[i]
		// A deleted (or marked-for-deletion) source still in the queue is dropped here: stepping back over it while it
		// stays in place would spin this loop forever.
		if(QDELETED(L))
			queue.Cut(i, i + 1)
			i -= 1
			continue
		// Which sources keep being re-queued (the churn metrics; world Topic "lightcensus").
		CHURN_COUNT(lights, L.source_atom ? L.source_atom.type : /datum/light_source)
		L.update_corners()

		if(!QDELETED(L))
			L.needs_update = LIGHTING_NO_UPDATE
		else
			// update_corners() deleted L: on_destroy() normally took it out of the list; drop it here if it did not, then
			// step back so the next element is not skipped.
			if(i <= length(queue) && (handles ? handle_get(queue[i]) : queue[i]) == L)
				queue.Cut(i, i + 1)
			i -= 1

		// At init the whole queue drains in one pass (S10b: no stoplag yield); afterwards the MC budget splits it.
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			if(i)
				queue.Cut(1, i + 1)
			return length(queue) > 0
	if(i)
		queue.Cut(1, i + 1)
	return FALSE

/datum/system/lighting/proc/update_sunlight(datum/planet_sunlight_handler/pshandler)
	if(istype(pshandler))
		pshandler.update_sun()
		if(length(pshandler.shandlers)) sunlight_queue_active |= pshandler.shandlers
	else
		for(var/datum/planet/planet in planet_shandlers)
			var/datum/planet_sunlight_handler/planet_shandler = planet_shandlers[planet]
			planet_shandler.update_sun()
		sunlight_queue_active = members_of(SUNLIGHT_AWAKE_KEY).Copy()

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
	else if(SSplanets.is_initialized() && SSplanets.planet_at_z(z))
		var/datum/planet/P = SSplanets.planet_at_z(z)
		if(istype(P))
			pshandler = get_pshandler_planet(P)
			z_to_pshandler[z] = pshandler
	return pshandler
