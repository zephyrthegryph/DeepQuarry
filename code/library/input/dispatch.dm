/client/input_topic(hsrc, href, list/href_list)
	return _Topic(hsrc, href, href_list)

/mob/input_say(message)
	return say(message)

/mob/input_point(atom/target)
	return _pointed(target)

/client/input_key_loop()
	return keyLoop()

/mob/input_double_click(atom/target, params)
	return DblClickOn(target, params)

/mob/input_wheel(atom/target, delta_x, delta_y, params)
	return MouseWheelOn(target, delta_x, delta_y, params)

/mob/input_hover(atom/target, params)
	client?.note_hover(target)

/// A press closes the tooltip of what declares one ("No reason not to, really").
/mob/input_pressed(atom/target, params)
	closeToolTip(src, target)


/datum/op_topic_resolve_ref(raw, wanted, source)
	return topic_resolve_ref(src, raw, wanted, source)

/datum/op_topic_rights_denied(mob/actor, key, wanted)
	admin_log_denial(actor.client, "topic:[key]", wanted)
	var/attempt = "[key_name(actor)] tried href action '[key]' on [type] without sufficient rights"
	log_admin(attempt)
	log_href("TOPIC rights refused: [attempt]")
	message_admins("[key_name_admin(actor)] tried href action '[key]' on [type] without sufficient rights.")

/// The admin token of the link's clicker: their own holder's, or the world's (the token a server-side caller without a holder carries). Another
/// admin's token is refused, and so is the world's for a clicker who has a holder.
/datum/op_topic_token_ok(mob/actor, token)
	if(!istext(token) || !length(token))
		return FALSE
	return token == op_topic_token_held(actor)

/// The token `actor` holds for admin links: their own holder's, or the world's when they have no holder.
/datum/proc/op_topic_token_held(mob/actor)
	var/datum/admins/holder = actor?.client?.holder
	return holder ? holder.href_token : GLOB.href_token

/datum/op_topic_refused(mob/actor, key, reason, list/href_list)
	if(reason != /datum/msg/op/topic_token)
		return
	var/token = href_list?["admin_token"]
	var/kind = token ? "a bad" : "no"
	var/attempt = "[key_name(actor)] clicked href action '[key]' on [type] with [kind] authorization key"
	log_admin(attempt)
	log_href("TOPIC token refused: [attempt]")
	message_admins("[key_name_admin(actor)] clicked an href with [kind] authorization key!")
