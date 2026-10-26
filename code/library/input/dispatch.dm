/client/input_topic(hsrc, href, list/href_list)
	return _Topic(hsrc, href, href_list)

/mob/input_say(message)
	return say(message)

/mob/input_point(atom/target)
	return _pointed(target)

/client/input_key_loop()
	return keyLoop()

/// Staff hear of a client flooding its inbox, once per burst.
/world/input_flood_report(mob/actor, kind, why)
	var/who = actor ? key_name(actor) : "An unknown client"
	var/report = "[who] is flooding the input inbox with [kind] inputs: [why]."
	log_admin(report)
	message_admins(report)

/// The click limits (a minute's and a second's worth), the open interaction menu closing and the click notice on the client's mob.
/client/input_click_allowed(atom/object, atom/location, control, params)
	var/mcl = CONFIG_GET(number/minute_click_limit)
	if (!check_rights_for(src, R_HOLDER) && mcl)
		var/minute = round(world.time, 600)

		if (!clicklimiter)
			clicklimiter = new(LIMITER_SIZE)

		if (minute != clicklimiter[CURRENT_MINUTE])
			clicklimiter[CURRENT_MINUTE] = minute
			clicklimiter[MINUTE_COUNT] = 0

		clicklimiter[MINUTE_COUNT] += 1

		if (clicklimiter[MINUTE_COUNT] > mcl)
			var/msg = "Your previous click was ignored because you've done too many in a minute."
			if (minute != clicklimiter[ADMINSWARNED_AT]) //only one admin message per-minute. (if they spam the admins can just boot/ban them)
				clicklimiter[ADMINSWARNED_AT] = minute

				msg += " Administrators have been informed."
				log_and_message_admins("Has hit the per-minute click limit of [mcl] clicks in a given game minute", src)
			to_chat(src, span_danger("[msg]"))
			return FALSE

	var/scl = CONFIG_GET(number/second_click_limit)
	if (!check_rights_for(src, R_HOLDER) && scl)
		var/second = round(world.time, 10)
		if (!clicklimiter)
			clicklimiter = new(LIMITER_SIZE)

		if (second != clicklimiter[CURRENT_SECOND])
			clicklimiter[CURRENT_SECOND] = second
			clicklimiter[SECOND_COUNT] = 0

		clicklimiter[SECOND_COUNT] += 1

		if (clicklimiter[SECOND_COUNT] > scl)
			to_chat(src, span_danger("Your previous click was ignored because you've done too many in a second"))
			return FALSE
	// Any click on the map dismisses an open interaction menu, as one dismisses BYOND's native popup
	// (a right-click then opens the new one).
	if(interaction_menu?.visible)
		interaction_menu.hide()
	// Clients cannot be hooked: the click event is emitted on the client's mob.
	if(mob)
		PUBLISH_LEGACY(mob, /datum/notice/client_click, object, location, control, params, mob)
	return TRUE

/// In build mode a drag on the map is the builder's.
/client/input_map_drop(start_object, end_object, start_location, end_location, start_control, end_control, params)
	if(buildmode && start_control == SKIN_MAP && start_control == end_control)
		build_drag(src, buildmode, start_object, end_object, start_location, end_location, start_control, end_control, params)
		return TRUE
	return FALSE

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
