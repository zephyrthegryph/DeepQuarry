// The chat input row's long entries arrive in packets (tgui's sendMessage splits them); the panel reassembles them here. What the row's
// messages mean (speech, typing bubbles, the live preview's rules) is the client's, in code/content/client/chat_speech.dm.

/// A long entry arrives in packets (tgui's sendMessage splits it); returns the whole payload once the last one is in, else null.
/datum/tgui_panel/proc/handle_packets(id, total_packets, packet, mob/user)
	id = text2num(id)

	var/total = text2num(total_packets)
	if(id == 1)
		if(total > MAX_MESSAGE_CHUNKS)
			return null

		partial_packets = list("chunks" = new /list(total))
		after(src, 10 SECONDS, PROC_REF(clear_oversized_payload), key = "packet_timeout")

	if(!partial_packets)
		return null
	var/list/chunks = partial_packets["chunks"]
	chunks[id] = packet

	if(id != total)
		if(id > 1)
			after(src, 10 SECONDS, PROC_REF(clear_oversized_payload), key = "packet_timeout")
		return null

	var/assembled_payload = ""
	for(var/received_packet in partial_packets["chunks"])
		assembled_payload += received_packet

	cancel_after(src, "packet_timeout")
	partial_packets = null
	if (!rustg_json_is_valid(assembled_payload))
		log_tgui(user, "Error: Invalid JSON")
		return null
	return json_decode(assembled_payload)

/datum/tgui_panel/proc/clear_oversized_payload()
	partial_packets = null
