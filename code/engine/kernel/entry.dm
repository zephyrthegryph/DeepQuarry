// BYOND's native input callbacks (doc/rewrite/final_api.html, section 2 "The input inbox").
//
// Every callback BYOND makes for a player's input hands the acting mob over as `usr`. This file is where that happens: each callback below reads the
// actor once, builds the typed /datum/input_event that carries it, and hands the event to input_submit(). What resolves an event reads the actor from
// the event (E.actor, and the hooks in input_hooks.dm take it as `src`); content never reads usr for an input. The client's own procs
// (client/MouseDown, MouseUp, MouseDrag) act as the client's mob and need no usr at all.
//
// The generated native overrides of a type that declares click_on(), drag_onto(), hover() or tooltip() (code/engine/_generated/declare.dm) are the other
// readers; they run before the callbacks here and go on to them with ..().

/atom/Click(location, control, params)
	if(src)
		// The click resolves on the spot while the tick has room, and otherwise waits for phase K's drain, in arrival order, behind the clicker's own earlier inputs.
		input_submit(new /datum/input_event/click(usr, src, location, control, params))

/atom/DblClick(location, control, params)
	if(src)
		input_submit(new /datum/input_event/click/double(usr, src, location, control, params))

/atom/MouseWheel(delta_x, delta_y, location, control, params)
	if(src)
		input_submit(new /datum/input_event/click/wheel(usr, src, location, control, params, delta_x, delta_y))

/// A drop: reach is asked when the event resolves (input_resolve_drag()), then the target's ops and its MouseDrop_T answer it.
/atom/MouseDrop(atom/over, src_location, over_location, src_control, over_control, params)
	if(src && over)
		input_submit(new /datum/input_event/drag(usr, src, over, list(src_location, over_location, src_control, over_control, params), TRUE))

/atom/MouseEntered(location, control, params)
	if(src)
		input_submit(new /datum/input_event/click/hover(usr, src, location, control, params))

/// A press closes the tooltip of what declares one; nothing else wants it, so nothing else is queued.
/atom/MouseDown(location, control, params)
	if(src && input_declares_tooltip(src))
		input_submit(new /datum/input_event/click/pressed(usr, src, location, control, params))

/client/MouseDown(atom/object, atom/location, control, params)
	. = ..()
	if(mob && object)
		input_submit(new /datum/input_event/click/client_mouse(mob, INPUT_MOUSE_DOWN, object, null, location, control, params))

/client/MouseUp(atom/object, atom/location, control, params)
	. = ..()
	if(mob)
		input_submit(new /datum/input_event/click/client_mouse(mob, INPUT_MOUSE_UP, object, null, location, control, params))

/client/MouseDrag(src_object, atom/over_object, src_location, over_location, src_control, over_control, params)
	. = ..()
	if(mob && over_object)
		input_submit(new /datum/input_event/click/client_mouse(mob, INPUT_MOUSE_DRAG, src_object, over_object, over_location, over_control, params))

/// A link that reached a datum's own Topic(): the dispatch answers it as the mob that clicked (a server-side call, with nobody acting, runs at once).
// ALLOW(sys_topic_override): the one core dispatcher every href on a datum reaches.
/datum/Topic(href, list/href_list)
	var/mob/user = usr
	if(!user)
		return input_topic_dispatch(null, href_list)
	var/datum/input_event/topic/E = new(user, src, href, href_list, TRUE)
	input_submit(E)
	return E.answered

/// The acting mob of an href BYOND handed this client: its own mob, and only when BYOND says that mob is the one acting (a Topic() called on a
/// client by somebody else, or with no acting mob, has none). The client's Topic reads it before anything else.
/client/proc/topic_actor()
	if(!usr || usr != mob)
		return null
	return mob

/// world.Reboot(): the input event says who asked (server-side, nobody); the world's hook logs and closes the round down, and the native reboot
/// goes on when it says so. A world not yet booted has no inbox, and the hook runs as a server-side request.
/world/Reboot(reason = 0, fast_track = FALSE)
	var/datum/input_event/reboot/E = new(usr, reason, fast_track)
	if(SSinput)
		input_submit(E)
		if(!E.finished)
			// The hook slept (or never ran): the reboot was asked for, so it goes on rather than leave the world up.
			log_world("Reboot: the input event for [E.actor ? key_name(E.actor) : "the server"]'s request did not finish; rebooting anyway.")
			return ..()
		if(E.proceed)
			return ..()
		return
	if(input_reboot(null, reason, fast_track))
		return ..()
