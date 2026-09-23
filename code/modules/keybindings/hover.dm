// Hover tracking (doc/rewrite/interactions.md §3). MouseEntered on map atoms
// records the hovered atom for category keys, the Menu key and screentips. It
// is throttled per client and does nothing for clients that don't use it.

/// The atom this client last hovered on the map, when hover tracking is on.
/client/var/tmp/datum/weakref/hovered_ref
/// world.time before which hover updates are ignored.
/client/var/tmp/hover_next_update = 0

/atom/MouseEntered(location, control, params)
	usr?.client?.note_hover(src)

/client/proc/note_hover(atom/hovered)
	if(!hover_tracking || world.time < hover_next_update)
		return
	if(istype(hovered, /atom/movable/screen))
		return
	hover_next_update = world.time + INPUT_HOVER_THROTTLE
	hovered_ref = WEAKREF(hovered)
	if(screentip || screentips_enabled())
		update_screentip()

/// The hovered atom if it is still valid and on the mob's z-level, else null.
/client/proc/hovered_atom()
	var/atom/hovered = hovered_ref?.resolve()
	if(!hovered || QDELETED(hovered) || !mob)
		return null
	var/turf/hovered_turf = get_turf(hovered)
	var/turf/mob_turf = get_turf(mob)
	if(!hovered_turf || !mob_turf || hovered_turf.z != mob_turf.z)
		return null
	return hovered

/// Runs the best interaction of a category on the hovered atom, or the tile in front of the mob.
/client/verb/input_category(category as text)
	set name = ".input-category"
	set hidden = TRUE
	set instant = FALSE

	if(!(category in INTERACTION_CATEGORIES) || !mob)
		return
	var/atom/target = hovered_atom() || get_step(mob, mob.dir)
	if(!target)
		return
	GLOB.input_router.route_category(mob, target, category)
