// The shared vis-contents overlay cache (was SSvis_overlays): unused overlays expire every minute. The API is in
// vis_overlay_api.dm.
SYSTEM_DEF(vis_overlays)
	name = "Vis contents overlays"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	VAR_PRIVATE/list/vis_overlay_cache = list()
	VAR_PRIVATE/list/currentrun
	/// TRUE while a sweep that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE

CAPABILITIES(/datum/system/vis_overlays)
	owns_many(nameof(vis_overlay_cache))

/datum/system/vis_overlays/reactions()
	. = ..()
	. += every(1 MINUTE, PROC_REF(expire_overlays), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/vis_overlays/proc/expire_overlays(dt)
	if(!resuming)
		currentrun = vis_overlay_cache.Copy()
	resuming = FALSE
	var/list/current_run = currentrun

	while(length(current_run))
		var/key = current_run[length(current_run)]
		var/obj/effect/overlay/vis/overlay = current_run[key]
		current_run.len--
		if(!overlay)
			continue // taken out of the cache since this sweep's snapshot
		if(!overlay.unused && !length(overlay.vis_locs))
			EXPIRY_STAMP(overlay, unused, CLOCK_WORLD)
		else if(overlay.unused && ELAPSED(overlay, unused, CLOCK_WORLD) > overlay.cache_expiration)
			own_take_member(src, nameof(vis_overlay_cache), key)
			lapsed(overlay)
		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/vis_overlays/proc/_create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags)
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

/atom/proc/add_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags = VIS_INHERIT_ID, unique)
	// The extremely minimal version where you just pass a string and nothing else
	if(istext(icon))
		iconstate = icon
		icon = src.icon

	return SSvis_overlays.add_vis_overlay(src, icon, iconstate, layer, plane, dir, alpha, add_appearance_flags, add_vis_flags, unique)

/atom/proc/remove_vis_overlay(list/overlays)
	return SSvis_overlays.remove_vis_overlay(src, overlays)
