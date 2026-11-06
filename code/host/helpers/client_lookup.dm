//Returns whether or not a player is a guest using their ckey as an input
/proc/IsGuestKey(key)
	READS_FROM() // a key's text only
	if (findtext(key, "Guest-", 1, 7) != 1) //was findtextEx
		return 0

	var/i = 7, ch, len = length(key)

	if(copytext(key, 7, 8) == "W") //webclient
		i++

	for (, i <= len, ++i)
		ch = text2ascii(key, i)
		if (ch < 48 || ch > 57)
			return 0
	return 1

/proc/get_mob_with_client_list()
	var/list/mobs = list()
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if (M.client)
			mobs += M
	return mobs
