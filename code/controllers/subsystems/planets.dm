SUBSYSTEM_DEF(planets)
	name = "Planets"
	priority = FIRE_PRIORITY_PLANETS
	wait = 2 SECONDS
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	dependencies = list(
		// The plant world service sets up at the top of Initialize() (it was SSplants).
		/datum/controller/subsystem/mapping
	)

	var/static/list/planets = list()
	var/static/list/z_to_planet = list()

	var/static/list/needs_sun_update = list()
	var/static/list/needs_temp_update = list()

/datum/controller/subsystem/planets/Initialize()
	// Seed and gene tables first (was SSplants, which planets depended on); atoms need them.
	GLOB.plant_service.initialize()
	admin_notice(span_danger("Initializing planetary weather."), R_DEBUG)
	createPlanets()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/planets/proc/createPlanets()
	var/list/planet_datums = using_map.planet_datums_to_make
	for(var/P in planet_datums)
		var/datum/planet/NP = new P()
		planets += NP
		PERIODIC_START(NP, PERIODIC_SLOW)
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
/datum/controller/subsystem/planets/proc/addTurf(turf/T)
	if(length(z_to_planet) >= T.z && z_to_planet[T.z])
		var/datum/planet/P = z_to_planet[T.z]
		if(!istype(P))
			return
		if(istype(T, /turf/unsimulated/wall/planetary))
			LAZYADD(P.planet_walls, T)
		else if(istype(T, /turf/simulated) && T.is_outdoors())
			LAZYADD(P.planet_floors, T)
			P.weather_holder.apply_to_turf(T)

/datum/controller/subsystem/planets/proc/removeTurf(turf/T,is_edge)
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
/datum/controller/subsystem/planets/fire(resumed = 0)
	var/list/needs_sun_update = src.needs_sun_update
	while(length(needs_sun_update))
		var/datum/planet/P = needs_sun_update[length(needs_sun_update)]
		needs_sun_update.len--
		updateSunlight(P)
		if(MC_TICK_CHECK)
			return

	#ifndef UNIT_TESTS // Don't be updating temperatures and such during unit tests
	var/list/needs_temp_update = src.needs_temp_update
	while(length(needs_temp_update))
		var/datum/planet/P = needs_temp_update[length(needs_temp_update)]
		needs_temp_update.len--
		updateTemp(P)
		if(MC_TICK_CHECK)
			return
	#endif


/datum/controller/subsystem/planets/proc/updateSunlight(datum/planet/P)
	var/new_brightness = P.sun["brightness"]
	P.sun_holder.update_brightness(new_brightness, P.planet_floors || list())

	var/new_color = P.sun["color"]
	P.sun_holder.update_color(new_color)
	SSlighting.update_sunlight(SSlighting.get_pshandler_planet(P))

/datum/controller/subsystem/planets/proc/updateTemp(datum/planet/P)
	//Set new temperatures
	for(var/turf/unsimulated/wall/planetary/wall as anything in P.planet_walls)
		wall.set_temperature(P.weather_holder.temperature)
		CHECK_TICK

/datum/controller/subsystem/planets/proc/weatherDisco()
	weather_disco_step(100000)

/datum/controller/subsystem/planets/proc/weather_disco_step(count)
	for(var/datum/planet/P as anything in planets)
		if(P.weather_holder)
			P.weather_holder.change_weather(DEFAULTPICK(P.weather_holder.allowed_weather_types, null))
	if(count > 1)
		om_after(src, 3, PROC_REF(weather_disco_step), count - 1)
