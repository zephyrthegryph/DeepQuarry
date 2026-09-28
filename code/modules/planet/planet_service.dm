// The planet world service (fold wave F4; was SSplanets). SSatoms initializes it before the map's
// atoms (turfs register as planet floors and walls in Initialize()). Each planet's clock, weather
// and sun run on its own PERIODIC_SLOW lane; the lighting and wall temperature changes they queue
// are applied here by /datum/om/behaviour/world/planets (code/datums/om/world_lanes.dm), every 2 s
// on the background lane, parked while nothing is queued.
GLOBAL_DATUM_INIT(planet_service, /datum/world_service/planets, new)

/datum/world_service/planets
	name = "Planets"
	lane = /datum/om/behaviour/world/planets
	on_demand = TRUE

	var/static/list/planets = list()
	var/static/list/z_to_planet = list()

	var/static/list/needs_sun_update = list()
	var/static/list/needs_temp_update = list()

/datum/world_service/planets/initialize()
	if(initialized)
		return
	initialized = TRUE
	// Seed and gene tables first (was SSplants, which planets depended on); atoms need them.
	GLOB.plant_service.initialize()
	admin_notice(span_danger("Initializing planetary weather."), R_DEBUG)
	createPlanets()
	log_world("World service [name] initialized: [length(planets)] planet\s.")

/datum/world_service/planets/proc/createPlanets()
	var/list/planet_datums = using_map.planet_datums_to_make
	for(var/P in planet_datums)
		var/datum/planet/NP = new P()
		planets += NP
		om_task_periodic(NP, PERIODIC_SLOW)
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

// DO NOT CALL THIS DIRECTLY UNLESS IT'S IN INITIALIZE,
// USE turf/simulated/proc/make_indoors() and
//     turf/simulated/proc/make_outdoors()
/datum/world_service/planets/proc/addTurf(turf/T)
	if(length(z_to_planet) >= T.z && z_to_planet[T.z])
		var/datum/planet/P = z_to_planet[T.z]
		if(!istype(P))
			return
		if(istype(T, /turf/unsimulated/wall/planetary))
			LAZYADD(P.planet_walls, T)
		else if(istype(T, /turf/simulated) && T.is_outdoors())
			LAZYADD(P.planet_floors, T)
			P.weather_holder.apply_to_turf(T)

/datum/world_service/planets/proc/removeTurf(turf/T,is_edge)
	if(length(z_to_planet) >= T.z)
		var/datum/planet/P = z_to_planet[T.z]
		if(!P)
			return
		if(istype(T, /turf/unsimulated/wall/planetary))
			LAZYREMOVE(P.planet_walls, T)
		else
			LAZYREMOVE(P.planet_floors, T)
			P.weather_holder.remove_from_turf(T)
			P.sun_holder.remove_from_turf(T)


/// Applies the lighting and wall-temperature changes the planets queued (their own clocks and
/// weather run on the slow lane), in batches that yield across ticks.
/datum/world_service/planets/service_step(resumed)
	var/list/needs_sun_update = src.needs_sun_update
	while(length(needs_sun_update))
		var/datum/planet/P = needs_sun_update[length(needs_sun_update)]
		needs_sun_update.len--
		updateSunlight(P)
		if(TICK_CHECK)
			return FALSE

	#ifndef UNIT_TESTS // Don't be updating temperatures and such during unit tests
	var/list/needs_temp_update = src.needs_temp_update
	while(length(needs_temp_update))
		var/datum/planet/P = needs_temp_update[length(needs_temp_update)]
		needs_temp_update.len--
		updateTemp(P)
		if(TICK_CHECK)
			return FALSE
	#endif
	return TRUE

/datum/world_service/planets/has_work()
	return length(needs_sun_update) || length(needs_temp_update)

/datum/world_service/planets/stat_line()
	return "Planets: [length(planets)] | Sun: [length(needs_sun_update)] | Temp: [length(needs_temp_update)]"

/datum/world_service/planets/proc/updateSunlight(datum/planet/P)
	var/new_brightness = P.sun["brightness"]
	P.sun_holder.update_brightness(new_brightness, P.planet_floors || list())

	var/new_color = P.sun["color"]
	P.sun_holder.update_color(new_color)
	SSlighting.update_sunlight(SSlighting.get_pshandler_planet(P))

/datum/world_service/planets/proc/updateTemp(datum/planet/P)
	//Set new temperatures
	for(var/turf/unsimulated/wall/planetary/wall as anything in P.planet_walls)
		wall.set_temperature(P.weather_holder.temperature)

/datum/world_service/planets/proc/weatherDisco()
	weather_disco_step(100000)

/datum/world_service/planets/proc/weather_disco_step(count)
	for(var/datum/planet/P as anything in planets)
		if(P.weather_holder)
			P.weather_holder.change_weather(DEFAULTPICK(P.weather_holder.allowed_weather_types, null))
	if(count > 1)
		om_after(src, 3, PROC_REF(weather_disco_step), count - 1)
