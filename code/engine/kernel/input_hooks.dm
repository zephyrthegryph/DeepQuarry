// The inbox schedules input; downstream implementations perform gameplay dispatch.
/client/proc/input_topic(hsrc, href, list/href_list)
	return

/mob/proc/input_say(message)
	return

/mob/proc/input_point(atom/target)
	return

/client/proc/input_key_loop()
	return

/// A double click on `target` (the actor is src).
/mob/proc/input_double_click(atom/target, params)
	return

/// The mouse wheel over `target`.
/mob/proc/input_wheel(atom/target, delta_x, delta_y, params)
	return

/// The mouse entering `target`.
/mob/proc/input_hover(atom/target, params)
	return

/// A press on `target` that declares a tooltip.
/mob/proc/input_pressed(atom/target, params)
	return

/// The client's mouse: INPUT_MOUSE_DOWN / UP on `target`, INPUT_MOUSE_DRAG from `target` over `over`.
/mob/proc/input_client_mouse(kind, atom/target, atom/over, params)
	return

/// world.Reboot() as `actor` (null: asked server-side). Returns TRUE when the native reboot goes on.
/world/proc/input_reboot(mob/actor, reason, fast_track)
	return TRUE

/// A link that reached this datum's own Topic(), answered as `user` (null: a server-side call). TRUE when an op took it.
/datum/proc/input_topic_dispatch(mob/user, list/href_list)
	return null

/// A client's inbox refused an input (over its hard cap or its rate limit), the first of a burst: staff are told, with the ckey (`kind` is the event's key,
/// `why` what it ran into). The engine has logged it already.
/world/proc/input_flood_report(mob/actor, kind, why)
	return

/// A click the client sent, before it goes on to the clicked atom: TRUE lets it go on, FALSE ends it (a click over the client's limits).
/client/proc/input_click_allowed(atom/object, atom/location, control, params)
	return TRUE

/// A drag-and-drop the client sent: TRUE when something took it before the dragged atom's MouseDrop() (the build mode's map drag).
/client/proc/input_map_drop(start_object, end_object, start_location, end_location, start_control, end_control, params)
	return FALSE
