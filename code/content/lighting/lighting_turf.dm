/turf
	///Lumcount added by sources other than lighting datum objects, such as the overlay lighting component.
	var/dynamic_lumcount = 0

	var/dynamic_lighting = TRUE

	var/tmp/lighting_corners_initialised = FALSE

	var/tmp/outdoors_adjacent = FALSE
	///Our lighting object.
	var/tmp/datum/lighting_object/lighting_object
	///Lighting Corner datums.
	var/tmp/datum/lighting_corner/lighting_corner_NE
	var/tmp/datum/lighting_corner/lighting_corner_SE
	var/tmp/datum/lighting_corner/lighting_corner_SW
	var/tmp/datum/lighting_corner/lighting_corner_NW

	///Which directions does this turf block the vision of, taking into account both the turf's opacity and the movable opacity_sources.
	var/directional_opacity = NONE
	///Lazylist of movable atoms providing opacity sources.
	/// A relation list view (REL_LIST below): each opaque movable adds and removes itself on move, and a deleted one leaves it.
	var/list/atom/movable/opacity_sources

// Causes any affecting light sources to be queued for a visibility update, for example a door got opened.
/turf/proc/reconsider_lights()
	lighting_corner_NE?.vis_update()
	lighting_corner_SE?.vis_update()
	lighting_corner_SW?.vis_update()
	lighting_corner_NW?.vis_update()

/turf/proc/lighting_clear_overlay()
	if(lighting_object)
		// qdel() is deferred. Remove the appearance synchronously so callers that
		// snapshot this turf's underlays (notably shuttle landing) cannot preserve
		// a stale lighting gradient as part of the turf's permanent appearance.
		lighting_object.removefromturf()
		spent(lighting_object, force = TRUE)
	else
		set_luminosity(1) // what a removed lighting object leaves (lighting_object on_destroy)

/// A copy of this turf's underlays without its lighting underlay: what a snapshot of the turf's appearance keeps. The lighting object stays.
/turf/proc/underlays_without_lighting()
	if(!lighting_object)
		return underlays.Copy()
	lighting_object.removefromturf()
	. = underlays.Copy()
	lighting_object.addtoturf()

/// Replaces this turf's underlays with a snapshot, keeping its lighting underlay.
/turf/proc/set_underlays_keeping_lighting(list/snapshot)
	underlays = snapshot.Copy()
	lighting_object?.addtoturf()

// Readies a dynamic turf for lighting, but only if our area is dynamic. The lighting object itself is made on first need
// (lighting_ensure_object): an unlit turf without one looks the same as one showing "dark" (luminosity 0 over the black
// lighting backdrop), so a map of mostly dark turfs costs no object, underlay or update for them.
/turf/proc/lighting_build_overlay()
	if(!has_dynamic_lighting())
		return

	lighting_clear_overlay()
	if(lighting_needs_object())
		new/datum/lighting_object(src)
		return
	set_luminosity(0)
	if(CONFIG_GET(number/starlight))
		for(var/turf/space/space_tile in RANGE_TURFS(1, src))
			space_tile.update_starlight()

/// TRUE when this dynamic turf must show a lighting object now rather than on first light: a corner already carries light.
/turf/proc/lighting_needs_object()
	return lighting_corners_lit()

/// TRUE when any of this turf's lighting corners carries light.
/turf/proc/lighting_corners_lit()
	var/datum/lighting_corner/C = lighting_corner_NE
	if(C && (C.lum_r || C.lum_g || C.lum_b))
		return TRUE
	C = lighting_corner_SE
	if(C && (C.lum_r || C.lum_g || C.lum_b))
		return TRUE
	C = lighting_corner_SW
	if(C && (C.lum_r || C.lum_g || C.lum_b))
		return TRUE
	C = lighting_corner_NW
	return C && (C.lum_r || C.lum_g || C.lum_b)

/// This turf's lighting object, made now if the turf is dynamic and has none yet (a light reached it, or a reader needs its lum).
/turf/proc/lighting_ensure_object() as /datum/lighting_object
	if(!lighting_object && SSlighting.is_initialized() && has_dynamic_lighting())
		new/datum/lighting_object(src)
	return lighting_object

// Used to get a scaled lumcount.
/turf/proc/get_lumcount(minlum = 0, maxlum = 1)
	if (!lighting_object && (!SSlighting.is_initialized() || !has_dynamic_lighting()))
		return 1

	var/totallums = 0
	var/datum/lighting_corner/L
	L = lighting_corner_NE
	if (L)
		totallums += L.lum_r + L.lum_b + L.lum_g
	L = lighting_corner_SE
	if (L)
		totallums += L.lum_r + L.lum_b + L.lum_g
	L = lighting_corner_SW
	if (L)
		totallums += L.lum_r + L.lum_b + L.lum_g
	L = lighting_corner_NW
	if (L)
		totallums += L.lum_r + L.lum_b + L.lum_g


	totallums /= 12 // 4 corners, each with 3 channels, get the average.

	totallums = (totallums - minlum) / (maxlum - minlum)

	totallums += dynamic_lumcount

	return CLAMP01(totallums)

// Returns a boolean whether the turf is on soft lighting.
// Soft lighting being the threshold at which point the overlay considers
// itself as too dark to allow sight and see_in_dark becomes useful.
// So basically if this returns true the tile is unlit black.
///Proc to add movable sources of opacity on the turf and let it handle lighting code.
/turf/proc/add_opacity_source(atom/movable/new_source)
	rel_add(src, nameof(opacity_sources), new_source)
	if(opacity)
		return
	recalculate_directional_opacity()


///Proc to remove movable sources of opacity on the turf and let it handle lighting code.
/turf/proc/remove_opacity_source(atom/movable/old_source)
	rel_remove(src, nameof(opacity_sources), old_source)
	if(opacity) //Still opaque, no need to worry on updating.
		return
	recalculate_directional_opacity()

///Setter for the byond luminosity var
/turf/proc/set_luminosity(new_luminosity, force)
	if(((is_outdoors() && !force) || outdoors_adjacent) && (z in GLOB.fake_sunlight_zs)) //Special exception for fakesun lit tiles
		return

	luminosity = new_luminosity

///Calculate on which directions this turfs block view.
/turf/proc/recalculate_directional_opacity()
	. = directional_opacity
	if(opacity)
		directional_opacity = ALL_CARDINALS
		if(. != directional_opacity)
			sight_opacity_changed(src)
			reconsider_lights()
		return
	directional_opacity = NONE
	for(var/atom/movable/opacity_source as anything in opacity_sources)
		if(opacity_source && opacity_source.flags & ON_BORDER)
			directional_opacity |= opacity_source.dir
		else //If fulltile and opaque, then the whole tile blocks view, no need to continue checking.
			directional_opacity = ALL_CARDINALS
			break
	if(. != directional_opacity)
		sight_opacity_changed(src)
	if(. != directional_opacity && (. == ALL_CARDINALS || directional_opacity == ALL_CARDINALS))
		reconsider_lights() //The lighting system only cares whether the tile is fully concealed from all directions or not.


/turf/proc/change_area(area/old_area, area/new_area)
	reactor_area_changed()
	if(SSlighting.is_initialized())
		if (new_area.dynamic_lighting != old_area.dynamic_lighting)
			if (new_area.dynamic_lighting)
				lighting_build_overlay()
			else
				lighting_clear_overlay()

/turf/proc/has_dynamic_lighting()
	var/area/A = loc
	return (IS_DYNAMIC_LIGHTING(src) && IS_DYNAMIC_LIGHTING(A))

/// The turf moved to another area: lights on it follow the new area's power key
/// (KEY_AREA_POWER). Paths that move turfs with a bare `area.contents +=` skip this
/// until M3's area channel event replaces the key.
/turf/proc/reactor_area_changed()
	for(var/obj/machinery/light/L in turf_contents_of_type(src, /obj/machinery/light))
		L.refresh_area()

// Held: corners are shared by four turfs and freed by the lighting subsystem; turfs are never destroyed.



