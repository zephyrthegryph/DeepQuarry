/// The screentip for `target`: its name. Null for nothing to show.
/proc/interaction_screentip_text(mob/user, atom/target, obj/item/held)
	if(!user || !target)
		return null
	return capitalize(target.name)

// ---------------------------------------------------------------------------
// Screentips: one screen object per client, updated when the hovered atom or
// the held item changes.

/atom/movable/screen/interaction_screentip
	name = ""
	icon = null
	icon_state = null
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	screen_loc = "TOP,LEFT"
	plane = PLANE_PLAYER_HUD_ABOVE
	maptext_height = 64
	maptext_width = 480
	maptext_x = 0
	maptext_y = -48

/// This client's screentip, when screentips are on.
/client/var/tmp/atom/movable/screen/interaction_screentip/screentip
/// What the screentip was made from, so it only updates when the hovered atom or the held item changes.
/client/var/tmp/screentip_key

/// Are screentips on for this client?
/client/proc/screentips_enabled()
	return prefs?.read_preference(/datum/preference/toggle/screentips) ? TRUE : FALSE

/// Refreshes the screentip for the hovered atom. Cheap when nothing changed.
/client/proc/update_screentip()
	if(!screentips_enabled() || !mob)
		clear_screentip()
		return
	var/atom/hovered = hovered_atom()
	var/obj/item/held = mob.get_active_hand()
	var/key = "[hovered ? REF(hovered) : "none"]|[held ? REF(held) : "none"]"
	if(key == screentip_key && screentip && (screentip in screen))
		return
	screentip_key = key
	var/text = hovered ? interaction_screentip_text(mob, hovered, held) : null
	if(!screentip)
		screentip = new /atom/movable/screen/interaction_screentip // ALLOW(ownership): /client is not a datum and is the one owner of this by design
	if(!(screentip in screen))
		screen += screentip
	screentip.maptext = text ? MAPTEXT("<span style='text-align:center'>[replacetext(html_encode(text), "\n", "<br>")]</span>") : null

/client/proc/clear_screentip()
	screentip_key = null
	if(screentip)
		screen -= screentip
		screentip.maptext = null

