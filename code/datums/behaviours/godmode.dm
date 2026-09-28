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

/// Puts `M` in godmode. FALSE if it already was.
/proc/godmode_enable(mob/M)
	if(!ismob(M) || om_has(M, EFFECT_GODMODE))
		return FALSE
	om_hold(M, EFFECT_GODMODE, godmode_source())
	return TRUE

/// Takes `M` out of godmode.
/proc/godmode_disable(mob/M)
	if(!ismob(M))
		return
	om_release(M, EFFECT_GODMODE, godmode_source())
