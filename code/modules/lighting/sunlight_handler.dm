/turf/simulated
	var/datum/sunlight_handler/shandler
	var/shandler_noinit = FALSE

CAPABILITIES(/turf/simulated)
	after_init(0, then(PROC_REF(turf_after_init)))
	owns_one(nameof(shandler), /datum/sunlight_handler)
	verb_entry(/turf/simulated/proc/climb_wall, when = nameof(climbable))
	adjacency(ADJ_KIND_TURF_EDGE, dirs = ADJ_ALL_AROUND, changed = PROC_REF(edges_changed))

/// A turf the map loads runs its after-init pass once the whole load exists; one made later (ChangeTurf) runs it only when its type says so.
/turf/simulated/proc/turf_after_init(datum/act/timer/A)
	if(A.mapload || runtime_after_init())
		sim_after_init(A)

/// Whether a turf made during the round runs sim_after_init() too (a floor with flooring, open space, glass), not only one the map loads.
/turf/simulated/proc/runtime_after_init()
	return FALSE

/// The after-init pass of a simulated turf: planet sunlight. Subtypes add their own work after ..().
/turf/simulated/proc/sim_after_init(datum/act/timer/A)
	if(((SSplanets.initialized && SSplanets.z_to_planet.len >= z && SSplanets.z_to_planet[z]) || SSlighting.get_pshandler_z(z)) && has_dynamic_lighting()) //Only for planet turfs or fakesuns that specify they want to use this system
		if(is_outdoors())
			var/turf/T = GetAbove(src)
			if(T && !isopenturf(T) && (SSplanets.z_to_planet.len >= T.z && SSplanets.z_to_planet[T.z]))
				make_indoors()
		if(!shandler_noinit)
			rel_set(src, nameof(shandler), new /datum/sunlight_handler(src))
			shandler.manualInit()

/turf/simulated/lighting_build_overlay()
	..()
	if(shandler)
		rel_set(shandler, nameof(shandler.only_sun_object), lighting_object)

/datum/sunlight_handler
	var/tmp/datum/simple_sun/sun
	var/turf/simulated/holder
	var/tmp/datum/lighting_object/only_sun_object
	var/effect_str_r = 0
	var/effect_str_g = 0
	var/effect_str_b = 0
	//agony but necessary for memory optimization
	var/tmp/datum/lighting_corner/affected_NE
	var/tmp/datum/lighting_corner/affected_NW
	var/tmp/datum/lighting_corner/affected_SW
	var/tmp/datum/lighting_corner/affected_SE
	var/tmp/datum/lighting_corner/only_sun_NE
	var/tmp/datum/lighting_corner/only_sun_NW
	var/tmp/datum/lighting_corner/only_sun_SW
	var/tmp/datum/lighting_corner/only_sun_SE
	var/sunlight = FALSE
	var/inherited = FALSE
	var/datum/planet_sunlight_handler/pshandler
	var/sleeping = FALSE

/datum/sunlight_handler/New(parent)
	. = ..()
	rel_set(src, nameof(holder), parent)

//Moved initialization here to make sure that it doesn't happen too early when replacing turfs.
/datum/sunlight_handler/proc/manualInit()
	if(!holder.lighting_corners_initialised)
		GENERATE_MISSING_CORNERS(holder)
	var/corners = list(holder.lighting_corner_NE,holder.lighting_corner_NW,holder.lighting_corner_SE,holder.lighting_corner_SW)
	for(var/datum/lighting_corner/corner in corners)
		if(corner.sunlight == SUNLIGHT_NONE)
			corner.sunlight = SUNLIGHT_POSSIBLE
	try_get_sun()
	sunlight_check()

/datum/sunlight_handler/proc/holder_change()
	GENERATE_MISSING_CORNERS(holder) //Somehow corners are self destructing under specific circumstances. Likely race conditions. This is slightly unoptimal but may be necessary.
	sunlight_check() //Also not optimal but made necessary by race conditions
	sunlight_update()
	for(var/dir in (GLOB.cardinal + GLOB.cornerdirs))
		var/turf/simulated/T = get_step(holder, dir)
		if(istype(T) && T.shandler)
			T.shandler.sunlight_update()
	sunlight_update()
	//Might seem silly and unoptimized to call update twice, but this is not called frequently and it makes things easier.
	//Logical flow goes:
	//Update 1: Disowns the lighting corner
	//Update surrounding turfs: Allows for corner to be claimed by other sunlight handler
	//Update 2: Accounts for changes made by surrounding turfs

/datum/sunlight_handler/proc/get_affected_list()
	var/list/affected = list()
	if(affected_NE()) affected += affected_NE()
	if(affected_NW()) affected += affected_NW()
	if(affected_SW()) affected += affected_SW()
	if(affected_SE()) affected += affected_SE()
	return affected

/datum/sunlight_handler/proc/add_to_affected(datum/lighting_corner/corner)
	if(holder.lighting_corner_NE == corner)
		rel_set(src, nameof(affected_NE), corner)
		return
	if(holder.lighting_corner_NW == corner)
		rel_set(src, nameof(affected_NW), corner)
		return
	if(holder.lighting_corner_SW == corner)
		rel_set(src, nameof(affected_SW), corner)
		return
	if(holder.lighting_corner_SE == corner)
		rel_set(src, nameof(affected_SE), corner)
		return

/datum/sunlight_handler/proc/remove_from_affected(datum/lighting_corner/corner)
	if(affected_NE() == corner)
		rel_clear(src, nameof(affected_NE))
		return
	if(affected_NW() == corner)
		rel_clear(src, nameof(affected_NW))
		return
	if(affected_SW() == corner)
		rel_clear(src, nameof(affected_SW))
		return
	if(affected_SE() == corner)
		rel_clear(src, nameof(affected_SE))
		return

/datum/sunlight_handler/proc/get_only_sun_list()
	var/list/only_sun = list()
	if(only_sun_NE()) only_sun += only_sun_NE()
	if(only_sun_NW()) only_sun += only_sun_NW()
	if(only_sun_SW()) only_sun += only_sun_SW()
	if(only_sun_SE()) only_sun += only_sun_SE()
	return only_sun

/datum/sunlight_handler/proc/add_to_only_sun(datum/lighting_corner/corner)
	if(holder.lighting_corner_NE == corner)
		rel_set(src, nameof(only_sun_NE), corner)
		return
	if(holder.lighting_corner_NW == corner)
		rel_set(src, nameof(only_sun_NW), corner)
		return
	if(holder.lighting_corner_SW == corner)
		rel_set(src, nameof(only_sun_SW), corner)
		return
	if(holder.lighting_corner_SE == corner)
		rel_set(src, nameof(only_sun_SE), corner)
		return

/datum/sunlight_handler/proc/remove_from_only_sun(datum/lighting_corner/corner)
	if(only_sun_NE() == corner)
		rel_clear(src, nameof(only_sun_NE))
		return
	if(only_sun_NW() == corner)
		rel_clear(src, nameof(only_sun_NW))
		return
	if(only_sun_SW() == corner)
		rel_clear(src, nameof(only_sun_SW))
		return
	if(only_sun_SE() == corner)
		rel_clear(src, nameof(only_sun_SE))
		return

/datum/sunlight_handler/proc/turf_update(old_density, turf/new_turf, above)
	if(above)
		sunlight_check()
		sunlight_update()
		return
	if(new_turf.density && !old_density && sunlight) //This has the potential to cut off our sunlight
		sunlight_check()
		sunlight_update()
	else if (!new_turf.density && old_density && !sunlight) //This has the potential to introduce sunlight
		sunlight_check()
		sunlight_update()

/datum/sunlight_handler/proc/sunlight_check()
	GENERATE_MISSING_CORNERS(holder) //Somehow corners are self destructing under specific circumstances. Likely race conditions. This is slightly unoptimal but may be necessary.
	set_sleeping(FALSE) //We set sleeping to false just incase. If the conditions are correct, we'll end up going back to sleeping soon enough anyways.
	var/cur_sunlight = sunlight
	if(holder.is_outdoors())
		sunlight = SUNLIGHT_OVERHEAD
	if(holder.density)
		sunlight = FALSE
	if(try_get_sun() && !holder.is_outdoors() && !holder.density)
		var/outside_near = FALSE
		outer_loop:
			for(var/dir in GLOB.cardinal)
				var/steps = 1
				var/turf/cur_turf = get_step(holder,dir)
				while(cur_turf && !cur_turf.density && steps < (SUNLIGHT_RADIUS + 1))
					if(cur_turf.is_outdoors())
						outside_near = TRUE
						break outer_loop
					steps += 1
					cur_turf = get_step(cur_turf,dir)
		if(!outside_near) //If GLOB.cardinal directions fail, then check diagonals.
			var/radius = ONE_OVER_SQRT_2 * SUNLIGHT_RADIUS + 1
			outer_loop:
				for(var/dir in GLOB.cornerdirs)
					var/steps = 1
					var/turf/cur_turf = get_step(holder,dir)
					var/opp_dir = turn(dir,180)
					var/north_south = opp_dir & (NORTH|SOUTH)
					var/east_west = opp_dir & (EAST|WEST)

					while(cur_turf && !cur_turf.density && steps < radius)
						var/turf/vert_behind = get_step(cur_turf,north_south)
						var/turf/hori_behind = get_step(cur_turf,east_west)
						if(vert_behind.density && hori_behind.density) //Prevent light from passing infinitesimally small gaps
							break outer_loop
						if(cur_turf.is_outdoors())
							outside_near = TRUE
							break outer_loop
						steps += 1
						cur_turf = get_step(cur_turf,dir)
		if(outside_near)
			sunlight = TRUE
		else if(sunlight)
			sunlight = FALSE

	if(cur_sunlight != sunlight)
		sunlight_update()
		if(!sunlight)
			SSlighting.sunlight_queue -= src
		else
			SSlighting.sunlight_queue += src

/datum/sunlight_handler/proc/sunlight_update()
	var/list/corners = list(holder.lighting_corner_NE,holder.lighting_corner_NW,holder.lighting_corner_SE,holder.lighting_corner_SW)
	var/list/new_corners = list()
	var/list/removed_corners = list()
	var/list/affected = get_affected_list()
	var/list/only_sun = get_only_sun_list()
	var/sunlightonly_corners = 0
	var/sunlightonly_shade_corners = 0
	var/sleepable_corners = 0
	for(var/datum/lighting_corner/corner in corners)
		switch(corner.sunlight)
			if(SUNLIGHT_NONE)
				if(sunlight)
					corner.sunlight = SUNLIGHT_CURRENT
					new_corners += corner
				else
					corner.sunlight = SUNLIGHT_POSSIBLE
			if(SUNLIGHT_POSSIBLE)
				if(sunlight)
					corner.sunlight = SUNLIGHT_CURRENT
					new_corners += corner
			if(SUNLIGHT_CURRENT)
				if(!sunlight && (corner in affected))
					remove_from_affected(corner)
					removed_corners += corner
					corner.sunlight = SUNLIGHT_POSSIBLE
			if(SUNLIGHT_ONLY)
				sunlightonly_corners++
				if(!(sunlight == SUNLIGHT_OVERHEAD) && (corner in only_sun))
					remove_from_only_sun(corner)
					sunlightonly_corners--
					if(sunlight)
						new_corners += corner
						corner.sunlight = SUNLIGHT_CURRENT
						continue
					corner.lum_r = 0
					corner.lum_g = 0
					corner.lum_b = 0
					continue
				sleepable_corners += corner.all_onlysun()
			if(SUNLIGHT_ONLY_SHADE)
				sunlightonly_shade_corners++
				if(!(sunlight == TRUE) && (corner in only_sun))
					remove_from_only_sun(corner)
					sunlightonly_shade_corners--
					if(sunlight)
						new_corners += corner
						corner.sunlight = SUNLIGHT_CURRENT
						continue
					corner.lum_r = 0
					corner.lum_g = 0
					corner.lum_b = 0
					continue
				sleepable_corners += corner.all_onlysun()

	if(!try_get_sun()) return

	var/sunonly_val = (sunlight == SUNLIGHT_OVERHEAD) ? SUNLIGHT_ONLY : SUNLIGHT_ONLY_SHADE

	if(sunlight)
		for(var/datum/lighting_corner/corner in affected)
			if(!LAZYLEN(corner.affecting))
				remove_from_affected(corner)
				removed_corners += corner
				add_to_only_sun(corner)
				corner.sunlight = sunonly_val
		for(var/datum/lighting_corner/corner in new_corners)
			if(!LAZYLEN(corner.affecting))
				new_corners -= corner
				add_to_only_sun(corner)
				corner.sunlight = sunonly_val

	if((sunlightonly_corners == 4 || sunlightonly_shade_corners == 4) && !only_sun_object())
		var/datum/lighting_object/holder_object = holder.lighting_object
		if(holder_object && !holder_object.sunlight_only)
			rel_set(src, nameof(only_sun_object), holder_object)
			only_sun_object().set_sunonly(sunonly_val, pshandler())


	if(sunlightonly_corners < 4 && sunlightonly_shade_corners < 4 && only_sun_object())
		only_sun_object().set_sunonly(FALSE, pshandler())
		rel_clear(src, nameof(only_sun_object))

	if(only_sun_object())
		//Edge cases but needed to make sure that the correct overlay is used in the case that all corners switch from shade to overhead or vice versa between updates
		if(only_sun_object().sunlight_only == SUNLIGHT_ONLY_SHADE && sunlight == SUNLIGHT_OVERHEAD)
			only_sun_object().set_sunonly(SUNLIGHT_ONLY, pshandler())
		else if(only_sun_object().sunlight_only == SUNLIGHT_ONLY && sunlight == SUNLIGHT_CURRENT)
			only_sun_object().set_sunonly(SUNLIGHT_ONLY_SHADE, pshandler())
		only_sun_object().update_sun()

	for(var/datum/lighting_corner/corner in only_sun)
		corner.update_sun(pshandler())

	if(sleepable_corners == 4)
		set_sleeping(TRUE)
	else
		set_sleeping(FALSE)

	if(!affected.len && !new_corners.len && !removed_corners.len)
		return //Nothing to do, avoid wasting time.

	var/sunlight_mult = 0
	switch(sunlight)
		if(TRUE)
			sunlight_mult = 0.6
		if(SUNLIGHT_OVERHEAD)
			sunlight_mult = 1.0
	var/brightness = sun().brightness * sunlight_mult * SSlighting.sun_mult
	var/list/color = hex2rgb(sun().color)
	var/red = brightness * (color[1] / 255.0)
	var/green = brightness * (color[2] / 255.0)
	var/blue = brightness * (color[3] / 255.0)
	var/delta_r = red - effect_str_r
	var/delta_g = green - effect_str_g
	var/delta_b = blue - effect_str_b

	for(var/datum/lighting_corner/corner in affected)
		corner.update_lumcount(delta_r,delta_g,delta_b,from_sholder=TRUE)

	for(var/datum/lighting_corner/corner in new_corners)
		corner.update_lumcount(red,green,blue,from_sholder=TRUE)
		add_to_affected(corner)

	for(var/datum/lighting_corner/corner in removed_corners)
		corner.update_lumcount(-effect_str_r,-effect_str_g,-effect_str_b,from_sholder=TRUE)

	if(!affected.len)
		effect_str_r = 0
		effect_str_g = 0
		effect_str_b = 0
		return

	effect_str_r = red
	effect_str_g = green
	effect_str_b = blue

/datum/sunlight_handler/proc/corner_sunlight_change(datum/lighting_corner/sender)
	if(only_sun_object())
		only_sun_object().set_sunonly(FALSE, pshandler())
		rel_clear(src, nameof(only_sun_object))

	set_sleeping(FALSE)
	wake_sleepers()

	if(!(sender in get_only_sun_list()))
		return

	sender.sunlight = SUNLIGHT_CURRENT

	sender.update_lumcount(effect_str_r,effect_str_g,effect_str_b,from_sholder=TRUE)
	remove_from_only_sun(sender)
	add_to_affected(sender)

/datum/sunlight_handler/proc/set_sleeping(val)
	if(sleeping == val)
		return
	sleeping = val
	if(val)
		if(pshandler)
			rel_remove(pshandler, nameof(pshandler.shandlers), src)
		SSlighting.sunlight_queue -= src
	else
		if(pshandler)
			rel_add(pshandler, nameof(pshandler.shandlers), src)
		SSlighting.sunlight_queue |= src //Just in case somehow gets set to false twice use |=

/datum/sunlight_handler/proc/wake_sleepers(val)
	var/list/corners = list(holder.lighting_corner_NE,holder.lighting_corner_NW,holder.lighting_corner_SE,holder.lighting_corner_SW)
	for(var/datum/lighting_corner/corner in corners)
		corner.wake_sleepers()

/datum/sunlight_handler/proc/try_get_sun()
	if(sun()) return TRUE
	if(!sleeping && SSlighting.get_pshandler_z(holder.z))
		rel_set(src, nameof(pshandler), SSlighting.get_pshandler_z(holder.z))
		rel_add(pshandler, nameof(pshandler.shandlers), src)
		rel_set(src, nameof(sun), pshandler().sun())
		return TRUE
	else
		return FALSE

// A simulated turf owns its sunlight handler (turf.shandler, OWN); holder is the one-sided back
// view. The handler moves to the replacement turf through ChangeTurf (turf_changing.dm).
/datum/planet_sunlight_handler/relations()
	. = ..()
	. += rel_many(nameof(shandlers))

/// The sun (a relation view).
/datum/sunlight_handler/proc/sun() as /datum/simple_sun
	return sun

/// The only_sun_object (a relation view).
/datum/sunlight_handler/proc/only_sun_object() as /datum/lighting_object
	return only_sun_object

/// The affected_NE (a relation view).
/datum/sunlight_handler/proc/affected_NE() as /datum/lighting_corner
	return affected_NE

/// The affected_NW (a relation view).
/datum/sunlight_handler/proc/affected_NW() as /datum/lighting_corner
	return affected_NW

/// The affected_SW (a relation view).
/datum/sunlight_handler/proc/affected_SW() as /datum/lighting_corner
	return affected_SW

/// The affected_SE (a relation view).
/datum/sunlight_handler/proc/affected_SE() as /datum/lighting_corner
	return affected_SE

/// The only_sun_NE (a relation view).
/datum/sunlight_handler/proc/only_sun_NE() as /datum/lighting_corner
	return only_sun_NE

/// The only_sun_NW (a relation view).
/datum/sunlight_handler/proc/only_sun_NW() as /datum/lighting_corner
	return only_sun_NW

/// The only_sun_SW (a relation view).
/datum/sunlight_handler/proc/only_sun_SW() as /datum/lighting_corner
	return only_sun_SW

/// The only_sun_SE (a relation view).
/datum/sunlight_handler/proc/only_sun_SE() as /datum/lighting_corner
	return only_sun_SE

/// The pshandler (a relation view).
/datum/sunlight_handler/proc/pshandler() as /datum/planet_sunlight_handler
	return pshandler
