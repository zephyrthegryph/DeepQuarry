/proc/release_hidden()
	return take(/datum/packet)
	packet.release() // ALLOW(pool)
