/**
 * Light blocking (was /datum/element/light_blocking). Movable state, not an OM
 * behaviour: opaque movables are common and the state is one flag. While set, the
 * movable is an opacity source of its turf; Moved() hands it from the old turf to
 * the new one.
 */
/atom/movable
	/// TRUE while this movable is an opacity source of its turf.

/atom/movable/proc/start_blocking_light()
	if(sparse_get_or(src, blocks_light, FALSE))
		return
	sparse_set_or(src, blocks_light, TRUE, FALSE)
	if(isturf(loc))
		var/turf/turf_loc = loc
		turf_loc.add_opacity_source(src)

/atom/movable/proc/stop_blocking_light()
	if(!sparse_get_or(src, blocks_light, FALSE))
		return
	sparse_set_or(src, blocks_light, FALSE, FALSE)
	if(isturf(loc))
		var/turf/turf_loc = loc
		turf_loc.remove_opacity_source(src)

///Updates old and new turf loc opacities. Called from Moved() while blocks_light.
/atom/movable/proc/light_blocking_moved(atom/old_loc)
	if(isturf(old_loc))
		var/turf/old_turf = old_loc
		old_turf.remove_opacity_source(src)
	if(isturf(loc))
		var/turf/new_turf = loc
		new_turf.add_opacity_source(src)
