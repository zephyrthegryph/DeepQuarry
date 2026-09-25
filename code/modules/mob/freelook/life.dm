/mob/observer/eye/upkeep()
	..()
	// If we lost our client, reset the list of visible chunks so they update properly on return
	if(owner == src && !client)
		visibleChunks.Cut()
	/*else if(owner && !owner.client)
		visibleChunks.Cut()*/
