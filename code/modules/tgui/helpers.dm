OM_TIMER_SLOT(/datum/tgui_say, packet_timeout)

/datum/tgui_say/proc/handle_packets(id, total_packets, packet)
	id = text2num(id)

	var/total = text2num(total_packets)
	if(id == 1)
		if(total > MAX_MESSAGE_CHUNKS)
			return null

		partial_packets = list("chunks" = new /list(total))
		om_after_slot(src, "packet_timeout", 10 SECONDS, PROC_REF(clear_oversized_payload))

	if(!partial_packets)
		return null
	var/list/chunks = partial_packets["chunks"]
	chunks[id] = packet

	if(id != total)
		if(id > 1)
			om_after_slot(src, "packet_timeout", 10 SECONDS, PROC_REF(clear_oversized_payload))
		return null

	var/assembled_payload = ""
	for(var/received_packet in partial_packets["chunks"])
		assembled_payload += received_packet

	om_cancel_timer_slot(src, "packet_timeout")
	partial_packets = null
	if (!rustg_json_is_valid(assembled_payload))
		log_tgui(usr, "Error: Invalid JSON")
		return
	return json_decode(assembled_payload)

/datum/tgui_say/proc/clear_oversized_payload()
	partial_packets = null
