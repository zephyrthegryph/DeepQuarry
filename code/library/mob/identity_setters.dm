// Registered setters cover explicit assignments, including disconnected stored identities.
// BYOND-origin client transfers are observed by generic Login/Logout instead.
SETTER(/mob, key)
SETTER(/mob, ckey)

/mob/proc/set_key(value)
	var/old_key = key
	var/old_ckey = ckey
	var/had_client = !!client
	key = value
	return identity_assignment_finished(old_key, old_ckey, had_client)

/mob/proc/set_ckey(value)
	var/old_key = key
	var/old_ckey = ckey
	var/had_client = !!client
	ckey = value
	return identity_assignment_finished(old_key, old_ckey, had_client)

/mob/proc/identity_assignment_finished(old_key, old_ckey, had_client)
	var/different = FALSE
	if(!TRACKED_UNCHANGED(old_key, key))
		tracked_changed(src, nameof(key))
		different = TRUE
	if(!TRACKED_UNCHANGED(old_ckey, ckey))
		tracked_changed(src, nameof(ckey))
		different = TRUE
		// Connected transfer already published from Login/Logout. Stored offline
		// identity has no such callback, so publish its actual change here.
		if(!had_client && !client)
			PUBLISH_CHANGE(src, MOB_KEY_CLIENT)
	return different
