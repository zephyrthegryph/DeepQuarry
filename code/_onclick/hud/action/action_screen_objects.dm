/atom/movable/screen/movable/action_button
	var/linked_action_handle
	var/our_hud_handle
	var/actiontooltipstyle = ""
	screen_loc = null
	icon = null // we don't use the base icon at all, just underlays and overlays

	/// The icon state of our active overlay, used to prevent re-applying identical overlays
	var/active_overlay_icon_state
	/// The icon state of our active underlay, used to prevent re-applying identical underlays
	var/active_underlay_icon_state
	/// The overlay we have overtop our button
	var/mutable_appearance/button_overlay

	/// Where we are currently placed on the hud. SCRN_OBJ_DEFAULT asks the linked action what it thinks
	var/location = SCRN_OBJ_DEFAULT
	/// A unique bitflag, combined with the name of our linked action this lets us persistently remember any user changes to our position
	var/id
	/// An OM handle of the last thing we hovered over
	/// God I hate how dragging works
	var/last_hovored_ref

// a button leaves its hud's layout and its action's viewers.
/atom/movable/screen/movable/action_button/on_destroy(force)
	var/datum/hud/hud = our_hud()
	if(hud)
		var/mob/viewer = hud.mymob()
		hud.hide_action(src)
		viewer?.client?.screen -= src
		viewer?.update_action_buttons()
	var/datum/action/action = linked_action()
	if(action && our_hud_handle)
		action.viewers -= our_hud_handle
	..()

/atom/movable/screen/movable/action_button/proc/can_use(mob/user)

	var/datum/action/action = linked_action()
	if(action)
		if(user.hud_used && action.viewers[om_handle(user.hud_used)])
			return TRUE
		return FALSE

	return TRUE

/atom/movable/screen/movable/action_button/Click(location,control,params)
	if(!can_use(usr))
		return

	var/list/modifiers = params2list(params)
	if(GLOB.input_router.click_is(modifiers, GLOB.input_router.shift_table(), INPUT_ACTION_INSPECT))
		var/datum/hud/our_hud = usr.hud_used
		our_hud.position_action(src, SCRN_OBJ_DEFAULT)
		return TRUE
	if(!usr.checkClickCooldown())
		return
	usr.setClickCooldown(1)
	var/trigger_flags
	if(GLOB.input_router.click_is(modifiers, GLOB.input_router.secondary_table(), INPUT_ACTION_ALTERNATE_SECONDARY))
		trigger_flags |= TRIGGER_SECONDARY_ACTION
	linked_action().Trigger(trigger_flags = trigger_flags)
	return TRUE

// Entered and Exited won't fire while you're dragging something, because you're still "holding" it
// Very much byond logic, but I want nice behavior, so we fake it with drag
/atom/movable/screen/movable/action_button/MouseDrag(atom/over_object, src_location, over_location, src_control, over_control, params)
	. = ..()
	if(!can_use(usr))
		return
	if((om_handle(over_object) == last_hovored_ref))
		return

	var/atom/old_object
	if(last_hovored_ref)
		old_object = om_resolve(last_hovored_ref)
	else // If there is no current ref, we assume it was us. We also treat this as our "first go" location.
		old_object = src
		var/datum/hud/our_hud = usr.hud_used
		our_hud?.generate_landings(src)

	if(old_object)
		old_object.MouseExited(over_location, over_control, params)

	last_hovored_ref = om_handle(over_object)
	over_object?.MouseEntered(over_location, over_control, params)

/atom/movable/screen/movable/action_button/MouseEntered(location, control, params)
	. = ..()
	if(!QDELETED(src))
		openToolTip(usr, src, params, title = name, content = desc, theme = actiontooltipstyle)

/atom/movable/screen/movable/action_button/MouseExited(location, control, params)
	closeToolTip(usr, src)
	return ..()

/atom/movable/screen/movable/action_button/MouseDrop(over_object)
	last_hovored_ref = null
	if(!can_use(usr))
		return
	var/datum/hud/our_hud = usr.hud_used
	if(over_object == src)
		our_hud.hide_landings()
		return
	if(istype(over_object, /atom/movable/screen/action_landing))
		var/atom/movable/screen/action_landing/reserve = over_object
		reserve.hit_by(src)
		our_hud.hide_landings()
		save_position()
		return

	our_hud.hide_landings()
	if(istype(over_object, /atom/movable/screen/button_palette) || istype(over_object, /atom/movable/screen/palette_scroll))
		our_hud.position_action(src, SCRN_OBJ_IN_PALETTE)
		save_position()
		return
	if(istype(over_object, /atom/movable/screen/movable/action_button))
		var/atom/movable/screen/movable/action_button/button = over_object
		our_hud.position_action_relative(src, button)
		save_position()
		return
	. = ..()
	our_hud.position_action(src, screen_loc)
	save_position()

/atom/movable/screen/movable/action_button/proc/save_position()
	var/mob/user = our_hud().mymob()
	if(!user?.client)
		return
	var/position_info = ""
	switch(location)
		if(SCRN_OBJ_FLOATING)
			position_info = screen_loc
		if(SCRN_OBJ_IN_LIST)
			position_info = SCRN_OBJ_IN_LIST
		if(SCRN_OBJ_IN_PALETTE)
			position_info = SCRN_OBJ_IN_PALETTE

	LAZYSET(user.client.prefs.action_button_screen_locs, "[name]_[id]", position_info)

/atom/movable/screen/movable/action_button/proc/load_position()
	var/mob/user = our_hud().mymob()
	if(!user)
		return
	var/position_info = LAZYACCESS(user.client?.prefs?.action_button_screen_locs, "[name]_[id]") || SCRN_OBJ_DEFAULT
	user.hud_used.position_action(src, position_info)

/atom/movable/screen/movable/action_button/proc/dump_save()
	var/mob/user = our_hud().mymob()
	if(!user?.client?.prefs)
		return
	LAZYREMOVE(user.client.prefs.action_button_screen_locs, "[name]_[id]")

/**
 * This is a silly proc used in hud code code to determine what icon and icon state we should be using
 * for hud elements (such as action buttons) that don't have their own icon and icon state set.
 *
 * It returns a list, which is pretty much just a struct of info
 */
/datum/hud/proc/get_action_buttons_icons()
	. = list()
	.["bg_icon"] = 'icons/mob/actions/backgrounds.dmi' // ui_style // TODO: Implement hud-specific icon stuff
	.["bg_state"] = "bg_default"
	.["bg_state_active"] = "bg_default_on"

/**
 * Updates all action buttons this mob has.
 *
 * Arguments:
 * * update_flags - Which flags of the action should we update
 * * force - Force buttons update even if the given button icon state has not changed
 */
/mob/proc/update_mob_action_buttons(update_flags = ALL, force = FALSE)
	for(var/datum/action/current_action as anything in actions)
		current_action.build_all_button_icons(update_flags, force)

/**
 * This proc handles adding all of the mob's actions to their screen
 *
 * If you just need to update existing buttons, use [/mob/proc/update_mob_action_buttons]!
 *
 * Arguments:
 * * update_flags - reload_screen - bool, if TRUE, this proc will add the button to the screen of the passed mob as well
 */
/mob/proc/update_action_buttons(reload_screen = FALSE)
	if(!hud_used || !client)
		return

	if(!hud_used.hud_shown)	//Hud toggled to minimal
		return

	for(var/datum/action/action as anything in actions)
		var/atom/movable/screen/movable/action_button/button = action.viewers[om_handle(hud_used)]
		action.build_all_button_icons()
		if(reload_screen)
			client.screen += button

	if(reload_screen)
		hud_used.update_our_owner()
	// This holds the logic for the palette buttons
	hud_used?.palette_actions?.refresh_actions()

/**
 * Show (most) of the another mob's action buttons to this mob
 *
 * Used for observers viewing another mob's screen
 */
/mob/proc/show_other_mob_action_buttons(mob/take_from)
	if(!hud_used || !client)
		return

	for(var/datum/action/action as anything in take_from.actions)
		if(!action.show_to_observers)
			continue
		action.GiveAction(src)
	om_hook(take_from, /datum/om/event/mob_granted_action, src, PROC_REF(on_observing_action_granted))
	om_hook(take_from, /datum/om/event/mob_removed_action, src, PROC_REF(on_observing_action_removed))

/**
 * Hide another mob's action buttons from this mob
 *
 * Used for observers viewing another mob's screen
 */
/mob/proc/hide_other_mob_action_buttons(mob/take_from)
	for(var/datum/action/action as anything in take_from.actions)
		action.HideFrom(src)
	om_unhook(take_from, list(/datum/om/event/mob_granted_action, /datum/om/event/mob_removed_action), src)

/// Hook for /datum/om/event/mob_granted_action - If we're viewing another mob's action buttons,
/// we need to update with any newly added buttons granted to the mob.
/mob/proc/on_observing_action_granted(mob/living/source, datum/om/event/mob_granted_action/event)
	EVENT_HANDLER
	var/datum/action/action = event.action

	if(!action.show_to_observers)
		return
	action.GiveAction(src)

/// Hook for /datum/om/event/mob_removed_action - If we're viewing another mob's action buttons,
/// we need to update with any removed buttons from the mob.
/mob/proc/on_observing_action_removed(mob/living/source, datum/om/event/mob_removed_action/event)
	EVENT_HANDLER
	var/datum/action/action = event.action

	action.HideFrom(src)

// Button Palette
// A new way to interact with actions

/atom/movable/screen/button_palette
	desc = "<b>Drag</b> buttons to move them<br><b>Shift-click</b> any button to reset it<br><b>Alt-click</b> this to reset all buttons"
	icon = 'icons/hud/64x16_actions.dmi'
	icon_state = "screen_gen_palette"
	screen_loc = ui_action_palette
	var/our_hud_handle
	var/expanded = FALSE
	/// Id of any currently running timers that set our color matrix
	var/color_timer_id

// the hud owns us as its toggle_palette; one deleted on its own clears that var.
REF_BACK_HANDLE(/atom/movable/screen/button_palette, list("our_hud_handle" = "toggle_palette"))

/atom/movable/screen/button_palette/Initialize(mapload)
	. = ..()
	// update_appearance()
	update_name()

/atom/movable/screen/button_palette/proc/set_hud(datum/hud/our_hud)
	src.our_hud_handle = om_handle(our_hud)
	refresh_owner()

// /atom/movable/screen/button_palette/update_name(updates)
/atom/movable/screen/button_palette/proc/update_name()
	// . = ..()
	if(expanded)
		name = "Hide Buttons"
	else
		name = "Show Buttons"

/atom/movable/screen/button_palette/proc/refresh_owner()
	var/mob/viewer = our_hud().mymob()
	if(viewer.client)
		viewer.client.screen |= src

	// icon_state = "[ui_name]_palette"

/atom/movable/screen/button_palette/MouseEntered(location, control, params)
	. = ..()
	if(QDELETED(src))
		return
	show_tooltip(params)

/atom/movable/screen/button_palette/MouseExited()
	closeToolTip(usr, src)
	return ..()

/atom/movable/screen/button_palette/proc/show_tooltip(params)
	openToolTip(usr, src, params, title = name, content = desc)

GLOBAL_LIST_INIT(palette_added_matrix, list(0.4,0.5,0.2,0, 0,1.4,0,0, 0,0.4,0.6,0, 0,0,0,1, 0,0,0,0))
GLOBAL_LIST_INIT(palette_removed_matrix, list(1.4,0,0,0, 0.7,0.4,0,0, 0.4,0,0.6,0, 0,0,0,1, 0,0,0,0))

/atom/movable/screen/button_palette/proc/play_item_added()
	color_for_now(GLOB.palette_added_matrix)

/atom/movable/screen/button_palette/proc/play_item_removed()
	color_for_now(GLOB.palette_removed_matrix)

/atom/movable/screen/button_palette/proc/color_for_now(list/color)
	if(color_timer_id)
		return
	add_atom_colour(color, TEMPORARY_COLOUR_PRIORITY) //We unfortunately cannot animate matrix colors. Curse you lummy it would be ~~non~~trivial to interpolate between the two valuessssssssss
	color_timer_id = om_after(src, 2 SECONDS, PROC_REF(remove_color), color)

/atom/movable/screen/button_palette/proc/remove_color(list/to_remove)
	color_timer_id = null
	remove_atom_colour(TEMPORARY_COLOUR_PRIORITY, to_remove)

/atom/movable/screen/button_palette/proc/can_use(mob/user)
	if(isobserver(user))
		// var/mob/observer/dead/O = user
		// return !O.observetarget
		return TRUE
	return TRUE

/atom/movable/screen/button_palette/Click(location, control, params)
	if(!can_use(usr))
		return

	if(GLOB.input_router.click_is(params, GLOB.input_router.alternate_table(), INPUT_ACTION_ALTERNATE))
		for(var/datum/action/action as anything in usr.actions) // Reset action positions to default
			for(var/hud_handle in action.viewers)
				var/datum/hud/hud = om_resolve(hud_handle)
				var/atom/movable/screen/movable/action_button/button = action.viewers[hud_handle]
				hud?.position_action(button, SCRN_OBJ_DEFAULT)
		to_chat(usr, span_notice("Action button positions have been reset."))
		return TRUE

	set_expanded(!expanded)

/atom/movable/screen/button_palette/proc/clicked_while_open(datum/source, datum/om/event/client_click/event)
	EVENT_HANDLER
	var/atom/target = event.target
	if(istype(target, /atom/movable/screen/movable/action_button) || istype(target, /atom/movable/screen/palette_scroll) || target == src) // If you're clicking on an action button, or us, you can live
		return
	set_expanded(FALSE)
	if(source)
		om_unhook(source, /datum/om/event/client_click, src)

/atom/movable/screen/button_palette/proc/set_expanded(new_expanded)
	var/datum/action_group/our_group = our_hud().palette_actions
	if(!length(our_group.actions)) //Looks dumb, trust me lad
		new_expanded = FALSE
	if(expanded == new_expanded)
		return

	expanded = new_expanded
	our_group.refresh_actions()
	// update_appearance()
	update_name()

	if(!usr.client)
		return

	// Clients cannot be hooked: client clicks are emitted on the client's mob.
	if(expanded)
		om_hook(usr, /datum/om/event/client_click, src, PROC_REF(clicked_while_open))
	else
		om_unhook(usr, /datum/om/event/client_click, src)

	closeToolTip(usr, src) //Our tooltips are now invalid, can't seem to update them in one frame, so here, just close them

/atom/movable/screen/palette_scroll
	icon = 'icons/hud/screen_gen.dmi'
	screen_loc = ui_palette_scroll
	/// How should we move the palette's actions?
	/// Positive scrolls down the list, negative scrolls back
	var/scroll_direction = 0
	var/our_hud_handle

/atom/movable/screen/palette_scroll/proc/can_use(mob/user)
	if(isobserver(user))
		// var/mob/observer/dead/O = user
		// return !O.observetarget
		return TRUE
	return TRUE

/atom/movable/screen/palette_scroll/proc/set_hud(datum/hud/our_hud)
	src.our_hud_handle = om_handle(our_hud)
	refresh_owner()

/atom/movable/screen/palette_scroll/proc/refresh_owner()
	var/mob/viewer = our_hud().mymob()
	if(viewer.client)
		viewer.client.screen |= src

	// var/list/settings = our_hud.get_action_buttons_icons()
	// icon = settings["bg_icon"]

/atom/movable/screen/palette_scroll/Click(location, control, params)
	if(!can_use(usr))
		return
	our_hud().palette_actions.scroll(scroll_direction)

/atom/movable/screen/palette_scroll/MouseEntered(location, control, params)
	. = ..()
	if(QDELETED(src))
		return
	openToolTip(usr, src, params, title = name, content = desc)

/atom/movable/screen/palette_scroll/MouseExited()
	closeToolTip(usr, src)
	return ..()

/atom/movable/screen/palette_scroll/down
	name = "Scroll Down"
	desc = "<b>Click</b> on this to scroll the actions above down"
	icon_state = "scroll_down"
	scroll_direction = 1

// the hud owns us as its palette_down; one deleted on its own clears that var.
REF_BACK_HANDLE(/atom/movable/screen/palette_scroll/down, list("our_hud_handle" = "palette_down"))

/atom/movable/screen/palette_scroll/up
	name = "Scroll Up"
	desc = "<b>Click</b> on this to scroll the actions above up"
	icon_state = "scroll_up"
	scroll_direction = -1

// the hud owns us as its palette_up; one deleted on its own clears that var.
REF_BACK_HANDLE(/atom/movable/screen/palette_scroll/up, list("our_hud_handle" = "palette_up"))

/// Exists so you have a place to put your buttons when you move them around
/atom/movable/screen/action_landing
	name = "Button Space"
	desc = "<b>Drag and drop</b> a button into this spot<br>to add it to the group"
	icon = 'icons/hud/screen_gen.dmi'
	icon_state = "reserved"
	// We want our whole 32x32 space to be clickable, so dropping's forgiving
	mouse_opacity = MOUSE_OPACITY_OPAQUE
	var/owner_handle

// its palette re-lays its actions without the landing spot.
// the group owns us as its landing; one deleted on its own clears it and re-lays the group.
/atom/movable/screen/action_landing/on_destroy(force)
	var/datum/action_group/group = owner()
	if(group && !QDELETED(group))
		if(group.landing == src)
			group.landing = null
		group.refresh_actions()
	..()

/atom/movable/screen/action_landing/proc/set_owner(datum/action_group/owner)
	src.owner_handle = om_handle(owner)
	refresh_owner()

/atom/movable/screen/action_landing/proc/refresh_owner()
	var/datum/hud/our_hud = owner()?.owner()
	var/mob/viewer = our_hud.mymob()
	if(viewer.client)
		viewer.client.screen |= src

	// var/list/settings = our_hud.get_action_buttons_icons()
	// icon = settings["bg_icon"]

/// Reacts to having a button dropped on it
/atom/movable/screen/action_landing/proc/hit_by(atom/movable/screen/movable/action_button/button)
	var/datum/hud/our_hud = owner()?.owner()
	our_hud.position_action(button, owner().location)

/// LC-refs: the action this button triggers -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/movable/action_button/proc/linked_action() as /datum/action
	return om_resolve(linked_action_handle)

/// LC-refs: the hud this is shown on -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/movable/action_button/proc/our_hud() as /datum/hud
	return om_resolve(our_hud_handle)

/// LC-refs: the hud this is shown on -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/button_palette/proc/our_hud() as /datum/hud
	return om_resolve(our_hud_handle)

/// LC-refs: the hud this is shown on -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/palette_scroll/proc/our_hud() as /datum/hud
	return om_resolve(our_hud_handle)

/// LC-refs: the action group this landing belongs to -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/action_landing/proc/owner() as /datum/action_group
	return om_resolve(owner_handle)

REF_OWNED(/atom/movable/screen/movable/action_button, list("button_overlay"))
