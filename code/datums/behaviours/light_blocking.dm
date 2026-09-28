/**
 * Light blocking (was /datum/element/light_blocking). Movable state, not an OM
 * behaviour: opaque movables are common and the state is one flag. While set, the
 * movable is an opacity source of its turf; Moved() hands it from the old turf to
 * the new one.
 */
/atom/movable
	/// TRUE while this movable is an opacity source of its turf.
	var/blocks_light = FALSE

/proc/start_blocking_light(atom/movable/AM)
	if(AM.blocks_light)
		return
	AM.blocks_light = TRUE
	if(isturf(AM.loc))
		var/turf/turf_loc = AM.loc
		turf_loc.add_opacity_source(AM)

/proc/stop_blocking_light(atom/movable/AM)
	if(!AM.blocks_light)
		return
	AM.blocks_light = FALSE
	if(isturf(AM.loc))
		var/turf/turf_loc = AM.loc
		turf_loc.remove_opacity_source(AM)

///Updates old and new turf loc opacities. Called from Moved() while blocks_light.
/proc/light_blocking_moved(atom/movable/AM, atom/old_loc)
	if(isturf(old_loc))
		var/turf/old_turf = old_loc
		old_turf.remove_opacity_source(AM)
	if(isturf(AM.loc))
		var/turf/new_turf = AM.loc
		new_turf.add_opacity_source(AM)
