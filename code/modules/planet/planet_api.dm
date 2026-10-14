// The planet system's API (code/modules/planet/planet_service.dm declares the system).
//
//   SSplanets.addTurf(turf)       a turf joins its planet's floors or walls (turf/simulated/proc/make_outdoors() calls it)
//   SSplanets.removeTurf(turf)    it leaves them
//
// planets and z_to_planet are read as vars by the lighting, solar and event code.

// DO NOT CALL THIS DIRECTLY UNLESS IT'S IN INITIALIZE,
// USE turf/simulated/proc/make_indoors() and
//     turf/simulated/proc/make_outdoors()
/datum/system/planets/proc/addTurf(turf/T)
	if(length(z_to_planet) >= T.z && z_to_planet[T.z])
		var/datum/planet/P = z_to_planet[T.z]
		if(!istype(P))
			return
		if(istype(T, /turf/unsimulated/wall/planetary))
			rel_add(P, nameof(P.planet_walls), T)
		else if(istype(T, /turf/simulated) && T.is_outdoors())
			rel_add(P, nameof(P.planet_floors), T)
			P.weather_holder.apply_to_turf(T)

/datum/system/planets/proc/removeTurf(turf/T,is_edge)
	if(length(z_to_planet) >= T.z)
		var/datum/planet/P = z_to_planet[T.z]
		if(!P)
			return
		if(istype(T, /turf/unsimulated/wall/planetary))
			rel_remove(P, nameof(P.planet_walls), T)
		else
			rel_remove(P, nameof(P.planet_floors), T)
			P.weather_holder.remove_from_turf(T)
			P.sun_holder.remove_from_turf(T)
