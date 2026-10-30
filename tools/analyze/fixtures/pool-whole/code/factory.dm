/proc/factory()
	var/datum/packet/packet = take(/datum/packet)
	packet.zone = 1
	return packet
/proc/conditional()
	var/datum/packet/packet = take(/datum/packet)
	if(ok)
		return packet
