// Look parts that name content types (an item worn on a mob, a living mob). The look builder itself is code/engine/present/appearance_builder.dm.

/// A hat on a small mob: `hat`'s worn sprite (item_state, else icon_state, from the head icon) raised by `pixel_y`, keeping its own colour. Reads the
/// hat's own state, so the mob hears a change of it; the mob's hat var is a relation or a changed() request.
/datum/look/proc/hat(obj/item/hat, pixel_y = 0, icon = 'icons/inventory/head/mob.dmi')
	touched = TRUE
	if(!hat)
		return
	watch(hat)
	LAZYADD(overlays, look_overlay_image(icon, hat.item_state ? hat.item_state : hat.icon_state, pixel_y = pixel_y, appearance_flags = RESET_COLOR))

/**
 * The base state of a living mob by what it is doing: `living` while awake and well (or while resting with no resting sprite), `dead` when dead,
 * `rest` while unconscious, resting or disabled and a resting sprite exists, else the type's own sprite. What every simple mob's legacy
 * provider wrote into icon_state; read from stat, resting and incapacitation. Returns the state chosen.
 *	look.life_state(src, icon_living, icon_rest, icon_dead)
 */
/datum/look/proc/life_state(mob/living/M, living, rest, dead)
	var/chosen
	var/disabled = M.incapacitated(INCAPACITATION_DISABLED)
	if((M.stat == CONSCIOUS) && (!rest || !M.resting || !disabled))
		chosen = living
	else if(M.stat >= DEAD)
		chosen = dead
	else if(((M.stat == UNCONSCIOUS) || M.resting || disabled) && rest)
		chosen = rest
	else
		chosen = initial(M.icon_state)
	return state(chosen)
