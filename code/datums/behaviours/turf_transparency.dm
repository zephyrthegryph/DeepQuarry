/// Z transparency (was /datum/element/turf_z_transparency). Turf state, not an OM
/// behaviour: open-space turfs are numerous and the state is one number. The multiz
/// neighbour hooks (multiz_turf_del/new) call z_transparency_update() directly.
#define Z_TRANSPARENCY_OFF 0
#define Z_TRANSPARENCY_ON 1
#define Z_TRANSPARENCY_SHOW_BOTTOM 2

/turf
	/// Z_TRANSPARENCY_*: whether this turf shows the level below.
	var/z_transparency = Z_TRANSPARENCY_OFF

///Sets up viscontents of the turf below. Handle plane and layer here too so that they don't cover other obs/turfs in Dream Maker
/turf/proc/make_z_transparent(show_bottom_level = TRUE)
	z_transparency = show_bottom_level ? Z_TRANSPARENCY_SHOW_BOTTOM : Z_TRANSPARENCY_ON
	plane = OPENSPACE_PLANE
	layer = OPENSPACE_LAYER
	z_transparency_update(TRUE, TRUE)

/turf/proc/unmake_z_transparent()
	if(!z_transparency)
		return
	z_transparency = Z_TRANSPARENCY_OFF
	vis_contents.len = 0

///Updates the viscontents or underlays below this tile.
/turf/proc/z_transparency_update(prune_on_fail = FALSE, init = FALSE)
	var/turf/our_turf = src
	var/turf/below_turf = GetBelow(our_turf)
	if(!below_turf)
		our_turf.vis_contents.len = 0
		if(!z_transparency_show_bottom() && prune_on_fail) //If we cant show whats below, and we prune on fail, change the turf to plating as a fallback
			our_turf.ChangeTurf(/turf/simulated/floor/plating)
			return FALSE
		else
			return TRUE
	if(init)
		our_turf.vis_contents += below_turf

	if(is_blocked_turf(our_turf)) //Show girders below closed turfs
		var/mutable_appearance/girder_underlay = mutable_appearance('icons/obj/structures.dmi', "girder", layer = TURF_LAYER-0.01)
		girder_underlay.appearance_flags = RESET_ALPHA | RESET_COLOR
		our_turf.underlays += girder_underlay
		var/mutable_appearance/plating_underlay = mutable_appearance('icons/turf/floors.dmi', "plating", layer = TURF_LAYER-0.02)
		plating_underlay.appearance_flags = RESET_ALPHA | RESET_COLOR
		our_turf.underlays += plating_underlay
	return TRUE

///Called when there is no real turf below this turf
/turf/proc/z_transparency_show_bottom()
	var/turf/our_turf = src
	if(z_transparency != Z_TRANSPARENCY_SHOW_BOTTOM)
		return FALSE
	var/turf/path = get_base_turf_by_area(our_turf) || /turf/space
	if(!ispath(path))
		path = text2path(path)
		if(!ispath(path))
			WARNING("Z-level [our_turf] has invalid baseturf '[get_base_turf_by_area(our_turf)]' in area '[get_area(our_turf)]'")
			path = /turf/space

	var/do_plane = ispath(path, /turf/space) ? SPACE_PLANE : null
	var/do_state = ispath(path, /turf/space) ? "white" : initial(path.icon_state)

	var/mutable_appearance/underlay_appearance = mutable_appearance(initial(path.icon), do_state, layer = TURF_LAYER-0.02, plane = do_plane)
	underlay_appearance.appearance_flags = RESET_ALPHA | RESET_COLOR
	our_turf.underlays += underlay_appearance

	return TRUE

#undef Z_TRANSPARENCY_OFF
#undef Z_TRANSPARENCY_ON
#undef Z_TRANSPARENCY_SHOW_BOTTOM
