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
