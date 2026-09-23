/turf/proc/ReplaceWithLattice()
	src.ChangeTurf(get_base_turf_by_area(src))
	spawn()
		new /obj/structure/lattice( locate(src.x, src.y, src.z) )

// Removes all signs of lattice on the pos of the turf -Donkieyo
/turf/proc/RemoveLattice()
	var/obj/structure/lattice/L = locate(/obj/structure/lattice, src)
	if(L)
		qdel(L)

// Called after turf replaces old one
/turf/proc/post_change()
	levelupdate()

	var/turf/simulated/open/above = GetAbove(src)
	if(istype(above))
		above.update_icon()

	var/turf/simulated/below = GetBelow(src)
	if(istype(below))
		below.update_icon() // To add or remove the 'ceiling-less' overlay.

// Under LINDA, a turf is "simulated" if it's /turf/simulated. Stub returns simulated-ness.
/proc/has_valid_atmos_zone(turf/simulated/T)
	return istype(T)

//Creates a new turf
/turf/proc/ChangeTurf(turf/N, tell_universe=1, force_lighting_update = 0, preserve_outdoors = FALSE)
	if (!N)
		return
	RAD_SHIELDING_CHANGED(src)

	if(N == /turf/space)
		var/turf/below = GetBelow(src)
		var/zones_present = has_valid_atmos_zone(below) || has_valid_atmos_zone(src)
		if(istype(below) && zones_present && !(src.z in using_map.below_blocked_levels) && (!istype(below, /turf/unsimulated/wall) && !istype(below, /turf/simulated/sky))) // Weird open space
			N = /turf/simulated/open

	// was `var/obj/fire/old_fire = fire`; ZAS /obj/fire is a stub now
	// and turf.fire isn't set under LINDA. Just drop the var since it's only
	// referenced again at line 92 (commented out).
	// var/obj/old_fire = null
	var/old_lighting_corners_initialized = lighting_corners_initialised
	var/old_dynamic_lighting = dynamic_lighting
	var/old_lighting_object = lighting_object
	var/old_lighting_corner_NE = lighting_corner_NE
	var/old_lighting_corner_SE = lighting_corner_SE
	var/old_lighting_corner_SW = lighting_corner_SW
	var/old_lighting_corner_NW = lighting_corner_NW
	var/old_directional_opacity = directional_opacity
	var/old_outdoors = outdoors
	var/old_dangerous_objects = dangerous_objects
	var/old_dynamic_lumcount = dynamic_lumcount
	var/oldtype = src.type
	var/old_density = src.density
	var/was_open = isopenturf(src)
	var/datum/gas_mixture/old_air
	var/turf/open/old_open_turf = src
	if(istype(old_open_turf) && old_open_turf.air)
		// Space turfs share one immutable vacuum that outlives this turf, so read
		// it directly instead of allocating a throwaway copy.
		old_air = old_open_turf.immutable_atmos ? old_open_turf.air : old_open_turf.air.copy()
	var/old_air_shared = istype(old_open_turf) && old_open_turf.immutable_atmos
	var/datum/sunlight_handler/old_shandler
	var/turf/simulated/simself = src
	if(istype(simself) && simself.shandler)
		old_shandler = simself.shandler

	var/turf/Ab = GetAbove(src)
	if(Ab)
		Ab.multiz_turf_del(src, DOWN)
	var/turf/Be = GetBelow(src)
	if(Be)
		Be.multiz_turf_del(src, UP)

	// `connections` (turf-to-turf ZAS edge list) and `S.zone` (ZAS zone
	// reference) are both ZAS-only. Under LINDA, turf air adjacency is rebuilt
	// via SSair.add_to_active() on the changed turf, called below.

	// Listeners may append callbacks; each is invoked with the new turf.
	var/list/post_change_callbacks
	if(_listen_lookup?[COMSIG_TURF_CHANGE])
		post_change_callbacks = list()
		SEND_SIGNAL(src, COMSIG_TURF_CHANGE, N, null, NONE, post_change_callbacks)

	cut_overlays(TRUE)
	RemoveElement(/datum/element/turf_z_transparency)
	changing_turf = TRUE
	qdel(src)

	var/turf/W = new N( locate(src.x, src.y, src.z) )
	for(var/datum/callback/post_change as anything in post_change_callbacks)
		post_change.InvokeAsync(W)
	var/turf/open/new_open_turf = W
	if(old_air && istype(new_open_turf) && new_open_turf.air)
		new_open_turf.air.copy_from(old_air)
	if(old_air_shared)
		old_air = null
	else
		QDEL_NULL(old_air)
	if(ispath(N, /turf/simulated/floor))
		// W.fire was a ZAS hotspot pointer; LINDA hotspots are tracked
		// in SSair.active_hotspots, not as a turf var.
		W.RemoveLattice()
	W.lighting_corners_initialised = old_lighting_corners_initialized
	var/turf/simulated/W_sim = W
	if(istype(W_sim) && old_shandler)
		W_sim.shandler = old_shandler
		old_shandler.holder = W
	else if(istype(W_sim) && (SSplanets && SSplanets.z_to_planet.len >= z && SSplanets.z_to_planet[z]) && has_dynamic_lighting())
		W_sim.shandler = new(src)
		W_sim.shandler.manualInit()
	// old_fire was ZAS-only; no-op under LINDA (no old fire to remove).

	if(tell_universe)
		GLOB.universe.OnTurfChange(W)

	if(SSair)
		SSair.mark_for_update(W)

	var/defer_explosion_appearance = SSexplosions?.is_bulk_resolving()
	if(CONFIG_GET(number/starlight) && !defer_explosion_appearance)
		for(var/turf/space/S in range(W, 1))
			S.update_starlight()
	if(defer_explosion_appearance)
		SSexplosions.defer_turf_update(W)
	else
		W.levelupdate()
		W.update_icon(1)
		W.post_change()
	. =  W

	dangerous_objects = old_dangerous_objects

	lighting_corner_NE = old_lighting_corner_NE
	lighting_corner_SE = old_lighting_corner_SE
	lighting_corner_SW = old_lighting_corner_SW
	lighting_corner_NW = old_lighting_corner_NW

	dynamic_lumcount = old_dynamic_lumcount

	if(SSlighting.initialized)
		lighting_object = old_lighting_object

		directional_opacity = old_directional_opacity
		if(!defer_explosion_appearance)
			recalculate_directional_opacity()

		if (!defer_explosion_appearance && dynamic_lighting != old_dynamic_lighting)
			if (IS_DYNAMIC_LIGHTING(src))
				lighting_build_overlay()
			else
				lighting_clear_overlay()
		else if(!defer_explosion_appearance && lighting_object && !lighting_object.needs_update)
			lighting_object.update()

		if(CONFIG_GET(number/starlight) && !defer_explosion_appearance)
			for(var/turf/space/space_tile in RANGE_TURFS(1, src))
				space_tile.update_starlight()

	var/turf/simulated/sim_self = src
	if(lighting_object && istype(sim_self) && sim_self.shandler) //sanity check, but this should never be null for either of the switch cases (lighting_object will be null during initializations sometimes)
		switch(lighting_object.sunlight_only)
			if(SUNLIGHT_ONLY)
				vis_contents += sim_self.shandler.pshandler.vis_overhead
			if(SUNLIGHT_ONLY_SHADE)
				vis_contents += sim_self.shandler.pshandler.vis_shade

	var/is_open = isopenturf(W)


	var/turf/simulated/cur_turf = src
	if(istype(cur_turf))
		var/area/A = cur_turf.loc
		if(is_outdoors() && !A.isAlwaysIndoors())
			propogate_sunlight_changes(oldtype, old_density, W)
		if(is_open != was_open)
			do
				cur_turf = GetBelow(cur_turf)
				if(!istype(cur_turf, /turf/simulated))
					break
				A = cur_turf.loc
				if(is_open && !A.isAlwaysIndoors())
					cur_turf.make_outdoors()
					cur_turf.propogate_sunlight_changes(oldtype, old_density, W, above = TRUE)
				else
					cur_turf.make_indoors()
			while(isopenturf(cur_turf) && HasBelow(cur_turf.z))

	if(old_shandler) old_shandler.holder_change()
	if(preserve_outdoors)
		outdoors = old_outdoors

/turf/proc/finalize_explosion_deferred_change(update_appearance = TRUE)
	levelupdate()
	post_change()
	if(SSlighting.initialized)
		recalculate_directional_opacity()
		if(lighting_object && !lighting_object.needs_update)
			lighting_object.update()
	if(update_appearance)
		finalize_explosion_deferred_appearance()

/turf/proc/finalize_explosion_deferred_appearance()
	// The subsystem already deduplicated the complete one-tile neighborhood, so
	// do not recursively update the same nine turfs for every changed floor.
	update_icon(FALSE)
	if(CONFIG_GET(number/starlight))
		if(istype(src, /turf/space))
			var/turf/space/S = src
			S.update_starlight()


/turf/proc/propogate_sunlight_changes(oldtype, old_density, new_turf, above = FALSE)
	//SEND_SIGNAL(src, COMSIG_TURF_UPDATE, oldtype, old_density, W)
	//Sends signals in a cross pattern to all tiles that may have their sunlight var affected including this tile.
	for(var/i = - SUNLIGHT_RADIUS, i <= SUNLIGHT_RADIUS, i++)
		var/turf/simulated/T = locate(src.x + i, src.y, src.z)
		if(istype(T) && T.shandler)
			T.shandler.turf_update(old_density, new_turf, above)

	for(var/i = - SUNLIGHT_RADIUS, i <= SUNLIGHT_RADIUS, i++)
		if(i == 0) //Don't send the signal to ourselves twice.
			continue
		var/turf/simulated/T = locate(src.x, src.y + i, src.z)
		if(istype(T) && T.shandler)
			T.shandler.turf_update(old_density, new_turf, above)

	//Also need to send signals diagonally too now.
	var/radius = ONE_OVER_SQRT_2 * SUNLIGHT_RADIUS + 1
	for(var/dir in GLOB.cornerdirs)
		var/steps = 1
		var/turf/cur_turf = get_step(src,dir)

		while(steps < radius)
			if(cur_turf)
				var/turf/simulated/T = cur_turf
				if(istype(T) && T.shandler)
					T.shandler.turf_update(old_density, new_turf, above)
			steps += 1
			cur_turf = get_step(cur_turf,dir)
