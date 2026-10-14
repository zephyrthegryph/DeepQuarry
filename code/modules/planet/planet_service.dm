// The planet system (was SSplanets). SSatoms depends on it, so it boots before the map's atoms (turfs register as
// planet floors and walls in Initialize()). Each planet's clock, weather and sun step themselves with an every() of 2 s; the
// lighting and wall temperature changes they queue are applied here, every 2 s on the background lane, parked while
// nothing is queued. The API is in planet_api.dm.
SYSTEM_DEF(planets)
	name = "Planets"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	// The map's z-levels exist once mapping has run; SSatoms depends on this service.
	needs = list(/datum/system/mapping)

	var/static/list/planets = list()
	var/static/list/z_to_planet = list()

	var/static/list/needs_sun_update = list()
	var/static/list/needs_temp_update = list()

/datum/system/planets/reactions()
	. = ..()
	. += every(2 SECONDS, PROC_REF(apply_updates), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/planets/initialize()
	if(initialized)
		return
	initialized = TRUE
	// Seed and gene tables first (was SSplants, which planets depended on); atoms need them.
	SSplants.ready()
	admin_notice(span_danger("Initializing planetary weather."), R_DEBUG)
	createPlanets()
	log_world("System [name] initialized: [length(planets)] planet\s.")

/datum/system/planets/proc/createPlanets()
	var/list/planet_datums = using_map.planet_datums_to_make
	for(var/P in planet_datums)
		var/datum/planet/NP = new P()
		planets += NP
		NP.set_clock_running(TRUE)
		for(var/index in 1 to length(NP.expected_z_levels))
			var/Z = LAZYACCESS(NP.expected_z_levels, index)
			if(!isnum(Z))
				Z = GLOB.map_templates_loaded[Z]
				LAZYSET(NP.expected_z_levels, index, Z)
			if(Z > length(z_to_planet))
				z_to_planet.len = Z
			if(z_to_planet[Z])
				admin_notice(span_danger("Z[Z] is shared by more than one planet!"), R_DEBUG)
				continue
			z_to_planet[Z] = NP

/// Applies the lighting and wall-temperature changes the planets queued (their own clocks and
/// weather run on the slow lane), in batches that yield across ticks.
/datum/system/planets/proc/apply_updates(dt)
	if(!has_work())
		return STEP_PARK
	var/list/needs_sun_update = src.needs_sun_update
	while(length(needs_sun_update))
		var/datum/planet/P = needs_sun_update[length(needs_sun_update)]
		needs_sun_update.len--
		updateSunlight(P)
		if(KERNEL_OVER_BUDGET)
			return STEP_YIELD

	#ifndef UNIT_TESTS // Don't be updating temperatures and such during unit tests
	var/list/needs_temp_update = src.needs_temp_update
	while(length(needs_temp_update))
		var/datum/planet/P = needs_temp_update[length(needs_temp_update)]
		needs_temp_update.len--
		updateTemp(P)
		if(KERNEL_OVER_BUDGET)
			return STEP_YIELD
	#endif
	return has_work() ? STEP_DONE : STEP_PARK

/datum/system/planets/proc/has_work()
	return length(needs_sun_update) || length(needs_temp_update)

/// Wakes the update step when a planet queued work (planet.dm).
/datum/system/planets/proc/wake_updates()
	if(has_work())
		wake_work_item(PROC_REF(apply_updates))

/datum/system/planets/stat_entry(msg)
	return "[msg]Planets: [length(planets)] | Sun: [length(needs_sun_update)] | Temp: [length(needs_temp_update)]"

/datum/system/planets/proc/updateSunlight(datum/planet/P)
	var/new_brightness = P.sun["brightness"]
	P.sun_holder.update_brightness(new_brightness, P.planet_floors || list())

	var/new_color = P.sun["color"]
	P.sun_holder.update_color(new_color)
	SSlighting.update_sunlight(SSlighting.get_pshandler_planet(P))

/datum/system/planets/proc/updateTemp(datum/planet/P)
	//Set new temperatures
	for(var/turf/unsimulated/wall/planetary/wall as anything in P.planet_walls)
		heat_set_solid(wall, P.weather_holder.temperature)

/datum/system/planets/proc/weatherDisco()
	weather_disco_step(100000)

/datum/system/planets/proc/weather_disco_step(count)
	for(var/datum/planet/P as anything in planets)
		if(P.weather_holder)
			P.weather_holder.change_weather(DEFAULTPICK(P.weather_holder.allowed_weather_types, null))
	if(count > 1)
		after(src, 0.3 SECONDS, PROC_REF(weather_disco_step), with = list(count - 1))
