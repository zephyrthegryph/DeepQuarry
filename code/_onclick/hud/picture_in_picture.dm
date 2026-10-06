/atom/movable/screen/movable/pic_in_pic
	name = "Picture-in-picture"
	screen_loc = "CENTER"
	plane = PLANE_WORLD
	var/atom/center
	var/width = 0
	var/height = 0
	var/list/shown_to
	var/list/viewing_turfs
	var/atom/movable/screen/component_button/button_x
	var/atom/movable/screen/component_button/button_expand
	var/atom/movable/screen/component_button/button_shrink
	var/atom/movable/screen/component_button/button_pop
	var/atom/movable/screen/map_view_tg/popup_screen

	var/mutable_appearance/standard_background

CAPABILITIES(/atom/movable/screen/movable/pic_in_pic)
	owns_one(nameof(button_expand), /atom/movable/screen/component_button)
	owns_one(nameof(button_pop), /atom/movable/screen/component_button)
	owns_one(nameof(button_shrink), /atom/movable/screen/component_button)
	owns_one(nameof(button_x), /atom/movable/screen/component_button)
	owns_one(nameof(popup_screen), /atom/movable/screen/map_view_tg)

// ALLOW(init/INSTANCE_STATE): its map view is made per window and named after this instance
/atom/movable/screen/movable/pic_in_pic/Initialize(mapload)
	. = ..()
	make_backgrounds()
	rel_set(src, nameof(popup_screen), new /atom/movable/screen/map_view_tg)
	popup_screen.generate_view("camera-[REF(src)]_map")


// hides itself from every client it is shown to.
/atom/movable/screen/movable/pic_in_pic/on_destroy(force)
	for(var/C in shown_to)
		unshow_to(C)
	..()

/atom/movable/screen/movable/pic_in_pic/component_click(atom/movable/screen/component_button/component, params, mob/user)
	if(component == button_x)
		user?.client?.close_popup("camera-[REF(src)]")
		spent(src, user)
	else if(component == button_expand)
		set_view_size(width+1, height+1)
	else if(component == button_shrink)
		set_view_size(width-1, height-1)
	else if(component == button_pop)
		pop_to_screen(user)

/atom/movable/screen/movable/pic_in_pic/proc/make_backgrounds()
	standard_background = new /mutable_appearance()
	standard_background.icon = 'icons/hud/pic_in_pic.dmi'
	standard_background.icon_state = "background"
	standard_background.layer = DISPOSAL_LAYER
	standard_background.plane = PLATING_PLANE
	standard_background.appearance_flags = PIXEL_SCALE

/atom/movable/screen/movable/pic_in_pic/proc/add_buttons()
	var/static/mutable_appearance/move_tab
	if(!move_tab)
		move_tab = new /mutable_appearance()
		//all these properties are always the same, and since adding something to the overlay
		//list makes a copy, there is no reason to make a new one each call
		move_tab.icon = 'icons/hud/pic_in_pic.dmi'
		move_tab.icon_state = "move"
		move_tab.plane = PLANE_PLAYER_HUD
	var/matrix/M = matrix()
	M.Translate(0, (height + 0.25) * world.icon_size)
	move_tab.transform = M
	add_overlay(move_tab)

	if(!button_x)
		rel_set(src, nameof(button_x), make(/atom/movable/screen/component_button, at = null, parent = src))
		var/mutable_appearance/MA = new /mutable_appearance()
		MA.name = "close"
		MA.icon = 'icons/hud/pic_in_pic.dmi'
		MA.icon_state = "x"
		MA.plane = PLANE_PLAYER_HUD
		button_x.appearance = MA
	M = matrix()
	M.Translate((max(4, width) - 0.75) * world.icon_size, (height + 0.25) * world.icon_size)
	button_x.transform = M
	vis_contents += button_x

	if(!button_expand)
		rel_set(src, nameof(button_expand), make(/atom/movable/screen/component_button, at = null, parent = src))
		var/mutable_appearance/MA = new /mutable_appearance()
		MA.name = "expand"
		MA.icon = 'icons/hud/pic_in_pic.dmi'
		MA.icon_state = "expand"
		MA.plane = PLANE_PLAYER_HUD
		button_expand.appearance = MA
	M = matrix()
	M.Translate(world.icon_size, (height + 0.25) * world.icon_size)
	button_expand.transform = M
	vis_contents += button_expand

	if(!button_shrink)
		rel_set(src, nameof(button_shrink), make(/atom/movable/screen/component_button, at = null, parent = src))
		var/mutable_appearance/MA = new /mutable_appearance()
		MA.name = "shrink"
		MA.icon = 'icons/hud/pic_in_pic.dmi'
		MA.icon_state = "shrink"
		MA.plane = PLANE_PLAYER_HUD
		button_shrink.appearance = MA
	M = matrix()
	M.Translate(2 * world.icon_size, (height + 0.25) * world.icon_size)
	button_shrink.transform = M
	vis_contents += button_shrink

	if(!button_pop)
		rel_set(src, nameof(button_pop), make(/atom/movable/screen/component_button, at = null, parent = src))
		var/mutable_appearance/MA = new /mutable_appearance()
		MA.name = "pop"
		MA.icon = 'icons/hud/pic_in_pic.dmi'
		MA.icon_state = "pop"
		MA.plane = PLANE_PLAYER_HUD
		button_pop.appearance = MA
	M = matrix()
	M.Translate((max(4, width) - 0.75) * ICON_SIZE_X, (height + 0.25) * ICON_SIZE_Y + 16)
	button_pop.transform = M
	vis_contents += button_pop

/atom/movable/screen/movable/pic_in_pic/proc/add_background()
	if((width > 0) && (height > 0))
		var/matrix/M = matrix()
		M.Scale(width + 0.5, height + 0.5)
		M.Translate((width-1)/2 * ICON_SIZE_X, (height-1)/2 * ICON_SIZE_Y)
		standard_background.transform = M
		add_overlay(standard_background)

/atom/movable/screen/movable/pic_in_pic/proc/set_view_size(width, height, do_refresh = TRUE)
	width = CLAMP(width, 0, 10)
	height = CLAMP(height, 0, 10)
	src.width = width
	src.height = height

	y_off = (-height * ICON_SIZE_Y) - (ICON_SIZE_Y / 2)

	cut_overlays()
	add_background()
	add_buttons()
	if(do_refresh)
		refresh_view()

/atom/movable/screen/movable/pic_in_pic/proc/set_view_center(atom/target, do_refresh = TRUE)
	rel_set(src, nameof(center), target)
	if(do_refresh)
		refresh_view()

/atom/movable/screen/movable/pic_in_pic/proc/refresh_view()
	vis_contents -= viewing_turfs
	if(!width || !height)
		return
	viewing_turfs = get_visible_turfs()
	if(length(viewing_turfs)) vis_contents += viewing_turfs
	if(popup_screen)
		popup_screen.vis_contents.Cut()
		if(length(viewing_turfs)) popup_screen.vis_contents += viewing_turfs

/atom/movable/screen/movable/pic_in_pic/proc/get_visible_turfs()
	var/turf/T = get_turf(center())
	if(!T)
		return list()
	var/turf/lowerleft = locate(max(1, T.x - round(width/2)), max(1, T.y - round(height/2)), T.z)
	var/turf/upperright = locate(min(world.maxx, lowerleft.x + width - 1), min(world.maxy, lowerleft.y + height - 1), lowerleft.z)
	return block(lowerleft, upperright)

/atom/movable/screen/movable/pic_in_pic/proc/show_to(client/C)
	if(C)
		LAZYSET(shown_to, C, 1)
		C.screen += src

/atom/movable/screen/movable/pic_in_pic/proc/unshow_to(client/C)
	if(C)
		LAZYREMOVE(shown_to, C)
		C.screen -= src

/atom/movable/screen/movable/pic_in_pic/proc/pop_to_screen(mob/user)
	if(!user?.client)
		return
	if(user.client.screen_maps["camera-[REF(src)]_map"])
		return
	user.client.setup_popup("camera-[REF(src)]", width, height, 2, "1984")
	popup_screen.display_to(user)
	observe(user, /datum/notice/popup_cleared, src, then(PROC_REF(on_popup_clear)))

/atom/movable/screen/movable/pic_in_pic/proc/on_popup_clear(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/source = A.target
	var/datum/notice/popup_cleared/event = A
	if(event.window_id == "camera-[REF(src)]")
		unobserve(source, /datum/notice/popup_cleared, src)
		popup_screen.hide_from(source)

/// The atom this view is centred on (a relation view: null once that is deleted).
/atom/movable/screen/movable/pic_in_pic/proc/center() as /atom
	return center

