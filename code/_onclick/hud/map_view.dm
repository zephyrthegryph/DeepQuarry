/**
 * /atom/movable/screen/map_view_tg is map_view on steroids, existing simultaneously for compatibility and not driving me crazy
 * during implementation
 */
INITIALIZE_IMMEDIATE(/atom/movable/screen/map_view_tg)
/atom/movable/screen/map_view_tg
	name = "screen"
	icon_state = "blank"
	// Map view has to be on the lowest plane to enable proper lighting
	layer = MAP_VIEW_LAYER
	plane = MAP_VIEW_PLANE
	del_on_map_removal = FALSE

	// The ckeys of all our viewers (clients are not datums, so they are held by key)
	var/list/viewing_clients
	var/list/popup_plane_masters

CAPABILITIES(/atom/movable/screen/map_view_tg)
	owns_many(nameof(popup_plane_masters))


// hides itself from every client still viewing it (held by ckey).
/atom/movable/screen/map_view_tg/on_destroy(force)
	for(var/viewer_ckey in viewing_clients)
		hide_from_client(GLOB.directory[viewer_ckey])
	..()

/atom/movable/screen/map_view_tg/proc/generate_view(map_key)
	// Map keys have to start and end with an A-Z character,
	// and definitely NOT with a square bracket or even a number.
	// I wasted 6 hours on this. :agony:
	// -- Stylemistake
	assigned_map = map_key
	set_position(1, 1)

	rel_clear(src, nameof(popup_plane_masters))
	for(var/atom/movable/screen/fresh as anything in get_tgui_plane_masters())
		rel_add(src, nameof(popup_plane_masters), fresh)

	for(var/atom/movable/screen/instance as anything in popup_plane_masters)
		instance.assigned_map = assigned_map
		instance.del_on_map_removal = FALSE
		instance.screen_loc = "[assigned_map]:1,1"

/**
 * Generates and displays the map view to a client
 * Make sure you at least try to pass tgui_window if map view needed on UI,
 * so it will wait a signal from TGUI, which tells windows is fully visible.
 *
 * If you use map view not in TGUI, just call it as usualy.
 * If UI needs planes, call display_to_client.
 *
 * * show_to - Mob which needs map view
 * * window - Optional. TGUI window which needs map view
 */
/atom/movable/screen/map_view_tg/proc/display_to(mob/show_to, datum/tgui_window/window)
	if(window && !window.visible)
		observe(window, /datum/notice/tgui_window_visible, src, then(PROC_REF(display_on_ui_visible)))
	else
		display_to_client(show_to.client)

/atom/movable/screen/map_view_tg/proc/display_on_ui_visible(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/tgui_window/window = A.target
	var/datum/notice/tgui_window_visible/event = A
	display_to_client(event.client)
	unobserve(window, /datum/notice/tgui_window_visible, src)

/atom/movable/screen/map_view_tg/proc/display_to_client(client/show_to)
	show_to.register_map_obj(src)

	for(var/plane in popup_plane_masters)
		show_to.register_map_obj(plane)

	LAZYOR(viewing_clients, show_to.ckey)

/atom/movable/screen/map_view_tg/proc/hide_from(mob/hide_from)
	hide_from_client(hide_from?.client)

/atom/movable/screen/map_view_tg/proc/hide_from_client(client/hide_from)
	if(!hide_from)
		return
	hide_from.clear_map(assigned_map)
	LAZYREMOVE(viewing_clients, hide_from.ckey)
