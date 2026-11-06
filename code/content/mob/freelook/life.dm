/mob/observer/eye/upkeep()
	var/mob/owner = src?.eye_owner()
	..()
	// If we lost our client, reset the list of visible chunks so they update properly on return
	if(owner == src && !client)
		rel_clear(src, nameof(visibleChunks))
	/*else if(owner && !owner.client)
		visibleChunks.Cut()*/
