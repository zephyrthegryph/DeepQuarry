// The vis overlay cache system's API (code/datums/vis_overlay_service.dm declares the system).
//
//   SSvis_overlays.add_vis_overlay(thing, icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags, unique)
//   SSvis_overlays.remove_vis_overlay(thing, overlays)
//
// Atoms use /atom/proc/add_vis_overlay() and remove_vis_overlay(), which call these.

//the "thing" var can be anything with vis_contents which includes images - in the future someone should totally allow vis overlays to be passed in as an arg instead of all this bullshit
/datum/system/vis_overlays/proc/add_vis_overlay(atom/movable/thing, icon, iconstate, layer, plane, dir, alpha = 255, add_appearance_flags = NONE, add_vis_flags = NONE, unique = FALSE)
	var/obj/effect/overlay/vis/overlay
	if(!unique)
		. = "[icon]|[iconstate]|[layer]|[plane]|[dir]|[alpha]|[add_appearance_flags]"
		overlay = vis_overlay_cache[.]
		if(!overlay)
			overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags)
			own_put(src, nameof(vis_overlay_cache), ., overlay)
		else
			overlay.unused = 0
	else
		overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags)
		overlay.cache_expiration = -1
		var/cache_id = "\ref[overlay]@{[world.time]}"
		own_put(src, nameof(vis_overlay_cache), cache_id, overlay)
		. = overlay
	thing.vis_contents += overlay

	if(!isatom(thing))
		return overlay

	rel_add(thing, nameof(thing.managed_vis_overlays), overlay)
	return overlay

/datum/system/vis_overlays/proc/remove_vis_overlay(atom/movable/thing, list/overlays)
	thing.vis_contents -= overlays
	if(!isatom(thing))
		return
	// `overlays` may be a single overlay, or a list (even thing.managed_vis_overlays itself).
	var/list/removing = islist(overlays) ? overlays.Copy() : list(overlays)
	for(var/obj/effect/overlay/vis/overlay as anything in removing)
		rel_remove(thing, nameof(thing.managed_vis_overlays), overlay)
