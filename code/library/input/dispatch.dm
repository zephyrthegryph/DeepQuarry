/client/input_topic(hsrc, href, list/href_list)
	return _Topic(hsrc, href, href_list)

/mob/input_say(message)
	return say(message)

/mob/input_point(atom/target)
	return _pointed(target)

/client/input_key_loop()
	return keyLoop()


/datum/op_topic_resolve_ref(raw, wanted, source)
	return topic_resolve_ref(src, raw, wanted, source)

/datum/op_topic_rights_denied(mob/actor, key, wanted)
	admin_log_denial(actor.client, "topic:[key]", wanted)
	var/attempt = "[key_name(actor)] tried href action '[key]' on [type] without sufficient rights"
	log_admin(attempt)
	log_href("TOPIC rights refused: [attempt]")
	message_admins("[key_name_admin(actor)] tried href action '[key]' on [type] without sufficient rights.")
