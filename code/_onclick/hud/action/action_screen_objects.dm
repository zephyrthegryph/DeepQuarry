/atom/movable/screen/movable/action_button
	var/datum/action/linked_action
	var/datum/hud/our_hud
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
	/// The last thing we hovered over (a relation view)
	/// God I hate how dragging works
	var/atom/last_hovored

// a button leaves its hud's layout and its action's viewers.
/atom/movable/screen/movable/action_button/on_destroy(force)
	var/datum/hud/hud = our_hud()
	if(hud)
		var/mob/viewer = hud.mymob()
		hud.hide_action(src)
		viewer?.client?.screen -= src
		viewer?.update_action_buttons()
	..()

/atom/movable/screen/movable/action_button/proc/can_use(mob/user)

	var/datum/action/action = linked_action()
	if(action)
		if(action.button_for(user.hud_used))
			return TRUE
		return FALSE

	return TRUE

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/movable/action_button/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/movable/action_button/click_with_actor(mob/user, location, control, params)
	if(!user)
		return
	if(!can_use(user))
		return

	var/list/modifiers = params2list(params)
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, shift_table), INPUT_ACTION_INSPECT))
		var/datum/hud/our_hud = user.hud_used
		our_hud.position_action(src, SCRN_OBJ_DEFAULT)
		return TRUE
	if(!user.checkClickCooldown())
		return
	user.setClickCooldown(0.1 SECONDS)
	var/trigger_flags
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, secondary_table), INPUT_ACTION_ALTERNATE_SECONDARY))
		trigger_flags |= TRIGGER_SECONDARY_ACTION
	linked_action().Trigger(trigger_flags = trigger_flags)
	return TRUE

// Entered and Exited won't fire while you're dragging something, because you're still "holding" it
// Very much byond logic, but I want nice behavior, so we fake it with drag
/atom/movable/screen/movable/action_button/proc/drag_with_actor(mob/user, atom/over_object, over_location, over_control, params)
	if(!can_use(user))
		return
	if(over_object == last_hovored)
		return

	var/atom/old_object
	if(last_hovored)
		old_object = last_hovored
	else // If there is no current ref, we assume it was us. We also treat this as our "first go" location.
		old_object = src
		var/datum/hud/our_hud = user.hud_used
		our_hud?.generate_landings(src)

	if(old_object)
		old_object.MouseExited(over_location, over_control, params)

	if(over_object)
		rel_set(src, nameof(last_hovored), over_object)
	else
		rel_clear(src, nameof(last_hovored))
	over_object?.MouseEntered(over_location, over_control, params)

CAPABILITIES(/atom/movable/screen/movable/action_button)
	tooltip(PROC_REF(input_tooltip), theme = nameof(actiontooltipstyle))
	click_on(PROC_REF(click_input))
	drag_onto(PROC_REF(action_drop_input))
	drag_over(PROC_REF(action_drag_input))

/// The tooltip the hovering mob sees (tooltip(), code/engine/lifeforms/input.dm).
/atom/movable/screen/movable/action_button/proc/input_tooltip(mob/user)
	return list(name, desc)

/// The native drop's actor (drag_onto(), code/engine/lifeforms/input.dm): onto another button or the palette it is handled there; anywhere
/// else the button moves to the drop and its hud records the new position.
/atom/movable/screen/movable/action_button/proc/action_drop_input(datum/act/input/A)
	var/mob/user = A.actor
	var/datum/hud/our_hud = user?.hud_used
	if(drop_with_actor(user, A.over))
		return TRUE
	move_to_drop(A.params, user)
	our_hud?.position_action(src, screen_loc)
	save_position()
	return TRUE

/// The native drag's actor while the button is dragged (drag_over()): the hover feedback over what it would be dropped on.
/atom/movable/screen/movable/action_button/proc/action_drag_input(datum/act/input/A)
	drag_with_actor(A.actor, A.over, A.native?["over_location"], A.native?["over_control"], A.params)
	return INPUT_FALLTHROUGH

/atom/movable/screen/movable/action_button/proc/drop_with_actor(mob/user, atom/over_object)
	rel_clear(src, nameof(last_hovored))
	if(!can_use(user))
		return TRUE
	var/datum/hud/our_hud = user.hud_used
	if(over_object == src)
		our_hud.hide_landings()
		return TRUE
	if(istype(over_object, /atom/movable/screen/action_landing))
		var/atom/movable/screen/action_landing/reserve = over_object
		reserve.hit_by(src)
		our_hud.hide_landings()
		save_position()
		return TRUE

	our_hud.hide_landings()
	if(istype(over_object, /atom/movable/screen/button_palette) || istype(over_object, /atom/movable/screen/palette_scroll))
		our_hud.position_action(src, SCRN_OBJ_IN_PALETTE)
		save_position()
		return TRUE
	if(istype(over_object, /atom/movable/screen/movable/action_button))
		var/atom/movable/screen/movable/action_button/button = over_object
		our_hud.position_action_relative(src, button)
		save_position()
		return TRUE
	return FALSE

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
		var/atom/movable/screen/movable/action_button/button = action.button_for(hud_used)
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
	global.observe(take_from, /datum/notice/mob_granted_action, src, then(PROC_REF(on_observing_action_granted)))
	global.observe(take_from, /datum/notice/mob_removed_action, src, then(PROC_REF(on_observing_action_removed)))

/**
 * Hide another mob's action buttons from this mob
 *
 * Used for observers viewing another mob's screen
 */
/mob/proc/hide_other_mob_action_buttons(mob/take_from)
	for(var/datum/action/action as anything in take_from.actions)
		action.HideFrom(src)
	unobserve(take_from, /datum/notice/mob_granted_action, src)
	unobserve(take_from, /datum/notice/mob_removed_action, src)

/// Hook for /datum/om/event/mob_granted_action - If we're viewing another mob's action buttons,
/// we need to update with any newly added buttons granted to the mob.
/mob/proc/on_observing_action_granted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/mob_granted_action/event = A
	var/datum/action/action = event.action

	if(!action.show_to_observers)
		return
	action.GiveAction(src)

/// Hook for /datum/om/event/mob_removed_action - If we're viewing another mob's action buttons,
/// we need to update with any removed buttons from the mob.
/mob/proc/on_observing_action_removed(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/mob_removed_action/event = A
	var/datum/action/action = event.action

	action.HideFrom(src)

// Button Palette
// A new way to interact with actions

/atom/movable/screen/button_palette
	desc = "<b>Drag</b> buttons to move them<br><b>Shift-click</b> any button to reset it<br><b>Alt-click</b> this to reset all buttons"
	icon = 'icons/hud/64x16_actions.dmi'
	icon_state = "screen_gen_palette"
	screen_loc = ui_action_palette
	var/datum/hud/our_hud
	var/expanded = FALSE

// the hud owns us as its toggle_palette; one deleted on its own clears that var.

/atom/movable/screen/button_palette/Initialize(mapload)
	. = ..()
	update_name()

/atom/movable/screen/button_palette/proc/set_hud(datum/hud/our_hud)
	rel_set(src, nameof(our_hud), our_hud)
	refresh_owner()

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


/// The tooltip the hovering mob sees (tooltip(), code/engine/lifeforms/input.dm): opened on enter, closed on exit.
/atom/movable/screen/button_palette/proc/palette_tooltip(mob/user)
	return list(name, desc)

GLOBAL_LIST_INIT(palette_added_matrix, list(0.4,0.5,0.2,0, 0,1.4,0,0, 0,0.4,0.6,0, 0,0,0,1, 0,0,0,0))
GLOBAL_LIST_INIT(palette_removed_matrix, list(1.4,0,0,0, 0.7,0.4,0,0, 0.4,0,0.6,0, 0,0,0,1, 0,0,0,0))

/atom/movable/screen/button_palette/proc/play_item_added()
	color_for_now(GLOB.palette_added_matrix)

/atom/movable/screen/button_palette/proc/play_item_removed()
	color_for_now(GLOB.palette_removed_matrix)

/atom/movable/screen/button_palette/proc/color_for_now(list/color)
	if(om_timer_slot_pending(src, "color_timer_id"))
		return
	add_atom_colour(color, TEMPORARY_COLOUR_PRIORITY) //We unfortunately cannot animate matrix colors. Curse you lummy it would be ~~non~~trivial to interpolate between the two valuessssssssss
	after(src, 2 SECONDS, PROC_REF(remove_color), key = "color_timer_id", with = list(color))

/atom/movable/screen/button_palette/proc/remove_color(list/to_remove)
	remove_atom_colour(TEMPORARY_COLOUR_PRIORITY, to_remove)

/atom/movable/screen/button_palette/proc/can_use(mob/user)
	if(isobserver(user))
		// var/mob/observer/dead/O = user
		// return !O.observetarget
		return TRUE
	return TRUE

CAPABILITIES(/atom/movable/screen/button_palette)
	click_on(PROC_REF(click_input))
	tooltip(PROC_REF(palette_tooltip))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/button_palette/proc/click_input(datum/act/input/A)
	return click_with_actor(A.actor, A.native["location"], A.native["control"], A.params)

/atom/movable/screen/button_palette/click_with_actor(mob/user, location, control, params)
	if(!can_use(user))
		return

	if(GLOB.input_router.click_is(params, TYPE_TABLE_GET(GLOB.input_router, alternate_table), INPUT_ACTION_ALTERNATE))
		for(var/datum/action/action as anything in user.actions) // Reset action positions to default
			for(var/atom/movable/screen/movable/action_button/button as anything in action.viewers)
				var/datum/hud/hud = button.our_hud
				hud?.position_action(button, SCRN_OBJ_DEFAULT)
		to_chat(user, span_notice("Action button positions have been reset."))
		return TRUE

	set_expanded(!expanded)

/atom/movable/screen/button_palette/proc/clicked_while_open(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	var/datum/notice/client_click/event = A
	var/atom/target = event.target_
	if(istype(target, /atom/movable/screen/movable/action_button) || istype(target, /atom/movable/screen/palette_scroll) || target == src) // If you're clicking on an action button, or us, you can live
		return
	set_expanded(FALSE)
	if(source)
		unobserve(source, /datum/notice/client_click, src)

/atom/movable/screen/button_palette/proc/set_expanded(new_expanded)
	var/datum/action_group/our_group = our_hud().palette_actions
	if(!length(our_group.actions)) //Looks dumb, trust me lad
		new_expanded = FALSE
	if(expanded == new_expanded)
		return

	expanded = new_expanded
	our_group.refresh_actions()
	update_name()

	var/mob/viewer = our_hud().mymob()
	if(!viewer?.client)
		return

	// Clients cannot be hooked: client clicks are emitted on the client's mob.
	if(expanded)
		observe(viewer, /datum/notice/client_click, src, then(PROC_REF(clicked_while_open)))
	else
		unobserve(viewer, /datum/notice/client_click, src)

	closeToolTip(viewer, src) //Our tooltips are now invalid, can't seem to update them in one frame, so here, just close them

/atom/movable/screen/palette_scroll
	icon = 'icons/hud/screen_gen.dmi'
	screen_loc = ui_palette_scroll
	/// How should we move the palette's actions?
	/// Positive scrolls down the list, negative scrolls back
	var/scroll_direction = 0
	var/datum/hud/our_hud

/atom/movable/screen/palette_scroll/proc/can_use(mob/user)
	if(isobserver(user))
		// var/mob/observer/dead/O = user
		// return !O.observetarget
		return TRUE
	return TRUE

/atom/movable/screen/palette_scroll/proc/set_hud(datum/hud/our_hud)
	rel_set(src, nameof(our_hud), our_hud)
	refresh_owner()

/atom/movable/screen/palette_scroll/proc/refresh_owner()
	var/mob/viewer = our_hud().mymob()
	if(viewer.client)
		viewer.client.screen |= src


/atom/movable/screen/palette_scroll/Click(location, control, params)
	if(!can_use(usr))
		return
	our_hud().palette_actions.scroll(scroll_direction)

CAPABILITIES(/atom/movable/screen/palette_scroll)
	tooltip(PROC_REF(input_tooltip))

/// The tooltip the hovering mob sees (tooltip(), code/engine/lifeforms/input.dm).
/atom/movable/screen/palette_scroll/proc/input_tooltip(mob/user)
	return list(name, desc)

/atom/movable/screen/palette_scroll/down
	name = "Scroll Down"
	desc = "<b>Click</b> on this to scroll the actions above down"
	icon_state = "scroll_down"
	scroll_direction = 1

// the hud owns us as its palette_down; one deleted on its own clears that var.

/atom/movable/screen/palette_scroll/up
	name = "Scroll Up"
	desc = "<b>Click</b> on this to scroll the actions above up"
	icon_state = "scroll_up"
	scroll_direction = -1

// the hud owns us as its palette_up; one deleted on its own clears that var.

/// Exists so you have a place to put your buttons when you move them around
/atom/movable/screen/action_landing
	name = "Button Space"
	desc = "<b>Drag and drop</b> a button into this spot<br>to add it to the group"
	icon = 'icons/hud/screen_gen.dmi'
	icon_state = "reserved"
	// We want our whole 32x32 space to be clickable, so dropping's forgiving
	mouse_opacity = MOUSE_OPACITY_OPAQUE
	var/datum/action_group/owner

// its palette re-lays its actions without the landing spot.
// the group owns us as its landing; one deleted on its own clears it and re-lays the group.
/atom/movable/screen/action_landing/on_destroy(force)
	var/datum/action_group/group = owner()
	if(group && !QDELETED(group))
		group.refresh_actions()
	..()

/atom/movable/screen/action_landing/proc/set_owner(datum/action_group/owner)
	rel_set(src, nameof(owner), owner)
	refresh_owner()

/atom/movable/screen/action_landing/proc/refresh_owner()
	var/datum/hud/our_hud = owner()?.owner()
	var/mob/viewer = our_hud.mymob()
	if(viewer.client)
		viewer.client.screen |= src


/// Reacts to having a button dropped on it
/atom/movable/screen/action_landing/proc/hit_by(atom/movable/screen/movable/action_button/button)
	var/datum/hud/our_hud = owner()?.owner()
	our_hud.position_action(button, owner().location)

/// The action this button triggers (a relation view: null once that is deleted).
/atom/movable/screen/movable/action_button/proc/linked_action() as /datum/action
	return linked_action

/// The hud this is shown on (a relation view: null once that is deleted).
/atom/movable/screen/movable/action_button/proc/our_hud() as /datum/hud
	return our_hud

/// The hud this is shown on (a relation view: null once that is deleted).
/atom/movable/screen/button_palette/proc/our_hud() as /datum/hud
	return our_hud

/// The hud this is shown on (a relation view: null once that is deleted).
/atom/movable/screen/palette_scroll/proc/our_hud() as /datum/hud
	return our_hud

/// The action group this landing belongs to (a relation view: null once that is deleted).
/atom/movable/screen/action_landing/proc/owner() as /datum/action_group
	return owner

