POOL_DECLARE(/datum/exempt_packet)
/proc/exempt()
	var/a = new /datum/packet
	return take(/datum/packet)
