/proc/log_href(text, list/data)
	logger.Log(LOG_CATEGORY_HREF, text, data)

/**
 * Appends a tgui-related log entry. All arguments are optional.
 */
/proc/log_tgui(
	user,
	message,
	context,
	datum/tgui_window/window,
	datum/src_object,
)

	var/entry = ""
	// Insert user info
	if(!user)
		entry += "<nobody>"
	else if(istype(user, /mob))
		var/mob/mob = user
		entry += "[mob.ckey] (as [mob] at [mob.x],[mob.y],[mob.z])"
	else if(istype(user, /client))
		var/client/client = user
		entry += "[client.ckey]"
	// Insert context
	if(context)
		entry += " in [context]"
	else if(window)
		entry += " in [window.id]"
	// Resolve src_object
	if(!src_object && window?.locked_by())
		src_object = window.locked_by().src_object()
	// Insert src_object info
	if(src_object)
		entry += "\nUsing: [src_object.type] [REF(src_object)]"
	// Insert message
	if(message)
		entry += "\n[message]"
	logger.Log(LOG_CATEGORY_HREF_TGUI, entry)

/// A failure a tgui page reported (tgui/errors.ts): one context to grep, bounded whatever the page sends.
/proc/log_tgui_client_error(user, list/payload, datum/tgui_window/window)
	log_tgui(user, "[copytext(json_encode(payload), 1, 8001)]", context = "tgui_error", window = window)
