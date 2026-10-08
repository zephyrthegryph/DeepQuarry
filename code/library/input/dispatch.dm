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

/// The admin token of the link's clicker: their own holder's, or the world's (the token a server-side caller without a holder carries).
/datum/op_topic_token_ok(mob/actor, token)
	if(!istext(token) || !length(token))
		return FALSE
	var/datum/admins/holder = actor?.client?.holder
	return token == (holder ? holder.href_token : GLOB.href_token)

/datum/op_topic_refused(mob/actor, key, reason, list/href_list)
	if(reason != /datum/msg/op/topic_token)
		return
	var/token = href_list?["admin_token"]
	var/kind = token ? "a bad" : "no"
	var/attempt = "[key_name(actor)] clicked href action '[key]' on [type] with [kind] authorization key"
	log_admin(attempt)
	log_href("TOPIC token refused: [attempt]")
	message_admins("[key_name_admin(actor)] clicked an href with [kind] authorization key!")
