// The shared vis-contents overlay cache (was SSvis_overlays): unused overlays expire every minute.
GLOBAL_DATUM_INIT(vis_overlays_service, /datum/world_service/vis_overlays, new)

/datum/world_service/vis_overlays
	name = "Vis contents overlays"
	lane = /datum/om/behaviour/world/vis_overlays

	var/list/vis_overlay_cache = list()
	var/list/currentrun

/datum/world_service/vis_overlays/service_step(resumed)
	if(!resumed)
		currentrun = vis_overlay_cache.Copy()
	var/list/current_run = currentrun

	while(length(current_run))
		var/key = current_run[length(current_run)]
		var/obj/effect/overlay/vis/overlay = current_run[key]
		current_run.len--
		if(!overlay.unused && !length(overlay.vis_locs))
			overlay.unused = world.time
		else if(overlay.unused && overlay.unused + overlay.cache_expiration < world.time)
			vis_overlay_cache -= key
			qdel(overlay)
		if(TICK_CHECK)
			return FALSE
	return TRUE

//the "thing" var can be anything with vis_contents which includes images - in the future someone should totally allow vis overlays to be passed in as an arg instead of all this bullshit
/datum/world_service/vis_overlays/proc/add_vis_overlay(atom/movable/thing, icon, iconstate, layer, plane, dir, alpha = 255, add_appearance_flags = NONE, add_vis_flags = NONE, unique = FALSE)
	var/obj/effect/overlay/vis/overlay
	if(!unique)
		. = "[icon]|[iconstate]|[layer]|[plane]|[dir]|[alpha]|[add_appearance_flags]"
		overlay = vis_overlay_cache[.]
		if(!overlay)
			overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags)
			vis_overlay_cache[.] = overlay
		else
			overlay.unused = 0
	else
		overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags)
		overlay.cache_expiration = -1
		var/cache_id = "\ref[overlay]@{[world.time]}"
		vis_overlay_cache[cache_id] = overlay
		. = overlay
	thing.vis_contents += overlay

	if(!isatom(thing))
		return overlay

	if(!thing.managed_vis_overlays)
		thing.managed_vis_overlays = list(overlay)
	else
		thing.managed_vis_overlays += overlay
	return overlay

/datum/world_service/vis_overlays/proc/_create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags)
	var/obj/effect/overlay/vis/overlay = new
	overlay.icon = icon
	overlay.icon_state = iconstate
	overlay.layer = layer
	overlay.plane = plane
	overlay.dir = dir
	overlay.alpha = alpha
	overlay.appearance_flags |= add_appearance_flags
	overlay.vis_flags |= add_vis_flags
	return overlay


/datum/world_service/vis_overlays/proc/remove_vis_overlay(atom/movable/thing, list/overlays)
	thing.vis_contents -= overlays
	if(!isatom(thing))
		return
	thing.managed_vis_overlays -= overlays
	if(!length(thing.managed_vis_overlays))
		thing.managed_vis_overlays = null

/atom/proc/add_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags = VIS_INHERIT_ID, unique)
	// The extremely minimal version where you just pass a string and nothing else
	if(istext(icon))
		iconstate = icon
		icon = src.icon

	return GLOB.vis_overlays_service.add_vis_overlay(src, icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags, unique)

/atom/proc/remove_vis_overlay(list/overlays)
	return GLOB.vis_overlays_service.remove_vis_overlay(src, overlays)

/// vis_overlays (was SSvis_overlays).
/datum/om/behaviour/world/vis_overlays
	name = "world: vis_overlays"
	every = 1 MINUTE
	lane = LANE_BACKGROUND

/datum/om/behaviour/world/vis_overlays/service()
	return GLOB.vis_overlays_service

DECLARE_REF(/datum/world_service/vis_overlays, "vis_overlay_cache", OWNED_VALUES, null)
