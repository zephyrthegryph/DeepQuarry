/// A movable's generic emissive blocker is a copy of its sprite taken at init (/atom/movable/Initialize()). When a look
/// changes the sprite, the copy follows it, so the blocker keeps the shape of what is drawn rather than of the state the
/// type started in.
/proc/look_resync_emissive_blocker(atom/movable/AM, old_icon, old_state)
	if(AM.blocks_emissive != EMISSIVE_BLOCK_GENERIC || !AM.priority_overlays)
		return
	var/list/entries = islist(AM.priority_overlays) ? AM.priority_overlays : list(AM.priority_overlays)
	for(var/mutable_appearance/old in entries)
		if(old.plane != PLANE_EMISSIVE || old.icon != old_icon || old.icon_state != old_state)
			continue
		var/mutable_appearance/blocker = mutable_appearance(AM.icon, AM.icon_state, plane = PLANE_EMISSIVE, alpha = AM.alpha)
		blocker.color = GLOB.em_block_color
		blocker.dir = AM.dir
		blocker.appearance_flags |= AM.appearance_flags
		look_replace_priority_overlay(AM, old, blocker)
		return

/atom/movable/look_changed_sprite(old_icon, old_state)
	look_resync_emissive_blocker(src, old_icon, old_state)

/// The hands draw this item with its item_state. Whoever holds or wears it watches its look (look.watch_look()), so the new state is shown
/// there when this look is applied; nothing to call.
/obj/item/look_apply_held_state(state)
	if(item_state != state)
		item_state = state

/atom/look_apply_light(range, power, color)
	set_glow(src, GLOW(range, power, color))

/atom/look_remove_filter(name)
	remove_filter(name)

/atom/look_add_filter(name, priority, list/params)
	add_filter(name, priority, params)
