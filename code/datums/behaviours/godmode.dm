/**
 * Godmode (was /datum/element/godmode). Holds EFFECT_GODMODE (which implies the
 * incapacitation immunities); injure(), apply_effects(), electrocute_act(), embedding
 * and silicon EMPs check om_has(mob, EFFECT_GODMODE) themselves, so nothing listens.
 */
/datum/godmode_source

/// The one contribution source for godmode holds.
/proc/godmode_source()
	var/static/datum/godmode_source/source = new
	return source

/// Puts the mob in godmode. FALSE if it already was.
/mob/proc/enable_godmode()
	if(om_has(src, EFFECT_GODMODE))
		return FALSE
	om_hold(src, EFFECT_GODMODE, godmode_source())
	return TRUE

/// Takes the mob out of godmode.
/mob/proc/disable_godmode()
	om_release(src, EFFECT_GODMODE, godmode_source())
