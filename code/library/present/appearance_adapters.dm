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

/// The mob that holds or wears `I` redraws that slot (its hand, belt, back...) through the slot's own redraw proc: a look that state_changed the
/// item's sprite or inhand state is shown there too. Nothing when the item is not on a mob.
/proc/look_redraw_worn(obj/item/I)
	var/mob/M = I.loc
	if(!ismob(M))
		return
	var/datum/relation_definition/slot/body/def = dq_ledger(M)?.def_by_id(M.inventory_slot_id(I))
	if(istype(def))
		def.redraw_on(M)

/atom/movable/look_changed_sprite(old_icon, old_state)
	look_resync_emissive_blocker(src, old_icon, old_state)

/obj/item/look_changed_sprite(old_icon, old_state)
	..()
	look_redraw_worn(src)

/obj/item/look_apply_held_state(state)
	if(item_state != state)
		item_state = state
		look_redraw_worn(src)

/atom/look_apply_light(range, power, color)
	set_light(arglist(args))

/atom/look_remove_filter(name)
	remove_filter(name)

/atom/look_add_filter(name, priority, list/params)
	add_filter(name, priority, params)
