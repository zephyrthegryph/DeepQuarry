/**
 * # Action system
 *
 * A simple base for an modular behavior attached to atom or datum.
 */
/datum/action
	/// The name of the action
	var/name = "Generic Action"
	/// The description of what the action does, shown in button tooltips
	var/desc
	// The target the action is attached to is the action_for relation (action_target()): if the
	// target datum is deleted, the action is as well. Set in New() via the proc link_to().
	// PLEASE set a target if you're making an action.
	/// Where any buttons we create should be by default. Accepts screen_loc and location defines
	var/default_button_position = SCRN_OBJ_IN_LIST
	// Who currently owns the action (action_owner()), and most often who is using it when it is triggered, is
	// the action_granted_to relation. It can be the same as the target but is not ALWAYS the same: Grant()
	// and Remove() set and unset it, and the owner being deleted removes the action from them.
	/// Flags that will determine of the owner / user of the action can... use the action
	var/check_flags = NONE
	/// Whether the button becomes transparent when it can't be used or just reddened
	var/transparent_when_unavailable = TRUE
	/// Our buttons (owned), one per viewing hud; each button's `our_hud` names the hud it is shown on.
	/// Read through button_for(hud).
	var/list/viewers
	/// If TRUE, this action button will be shown to observers / other mobs who view from this action's owner's eyes.
	/// Used in [/mob/proc/show_other_mob_action_buttons]
	/// (Not really, this behavior is unimplemented)
	var/show_to_observers = TRUE

	/// The style the button's tooltips appear to be
	var/buttontooltipstyle = ""

	/// This is the file for the BACKGROUND underlay icon of the button
	var/background_icon = 'icons/mob/actions/backgrounds.dmi'
	/// This is the icon state state for the BACKGROUND underlay icon of the button
	/// (If set to ACTION_BUTTON_DEFAULT_BACKGROUND, uses the hud's default background)
	var/background_icon_state = ACTION_BUTTON_DEFAULT_BACKGROUND

	/// This is the file for the icon that appears on the button
	var/button_icon = 'icons/mob/actions.dmi'
	/// This is the icon state for the icon that appears on the button
	var/button_icon_state = "default"

	/// This is the file for any FOREGROUND overlay icons on the button (such as borders)
	var/overlay_icon = 'icons/mob/actions/backgrounds.dmi'
	/// This is the icon state for any FOREGROUND overlay icons on the button (such as borders)
	var/overlay_icon_state

CAPABILITIES(/datum/action)
	owns_many(nameof(viewers))

/datum/action/New(Target)
	link_to(Target)

/// Links the passed target to our action (the action_for relation: its deletion deletes us)
/datum/action/proc/link_to(Target)
	if(Target)
		om_link(src, Target, /datum/om/relation/action_for)


/// An action -> the datum it acts for (an item, a mecha, a spell). Read with action_target().
/// Deleting that datum deletes the action.
/datum/om/relation/action_for
	name = "action target"
	source_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER

/// An action -> the mob it is granted to (its owner). Read with action_owner(). Grant() and
/// Remove() link and unlink it; either end being deleted runs Remove() on the owner.
/datum/om/relation/action_granted_to
	name = "action owner"
	source_single = TRUE

/datum/om/relation/action_granted_to/on_unlink(datum/action/source, mob/target, datum/om/edge/edge)
	if(QDELETED(source) || QDELETED(target))
		source.Remove(target)

/// The button (owned, in `viewers`) shown on `hud`, or null.
/datum/action/proc/button_for(datum/hud/hud)
	if(!hud)
		return null
	for(var/atom/movable/screen/movable/action_button/button as anything in viewers)
		if(button.our_hud == hud)
			return button
	return null

/// Grants the action to the passed mob, making it the owner
/datum/action/proc/Grant(mob/grant_to)
	if(!grant_to)
		Remove(action_owner())
		return
	var/mob/owner = action_owner()
	if(owner)
		if(owner == grant_to)
			return
		Remove(owner)

	OM_EMIT(grant_to, /datum/om/event/mob_granted_action, src)
	om_link(src, grant_to, /datum/om/relation/action_granted_to)

	GiveAction(grant_to)

/// Remove the passed mob from being owner of our action
/datum/action/proc/Remove(mob/remove_from)
	SHOULD_CALL_PARENT(TRUE)

	for(var/atom/movable/screen/movable/action_button/button as anything in viewers?.Copy())
		var/datum/hud/hud = button.our_hud
		var/mob/viewer = hud?.mymob()
		if(!viewer)
			continue
		HideFrom(viewer)
	if(remove_from)
		rel_remove(remove_from, nameof(/mob::actions), src) // We aren't always properly inserted into the viewers list, gotta make sure that action's cleared
	own_clear(src, nameof(viewers), OWN_DELETE) // whatever HideFrom() couldn't reach

	// While the owner relation is being torn down (either end deleted) the edge is already gone.
	var/mob/owner = action_owner() || remove_from
	if(owner)
		OM_EMIT(owner, /datum/om/event/mob_removed_action, src)
		om_unlink(src, owner, /datum/om/relation/action_granted_to)

/// Actually triggers the effects of the action.
/// Called when the on-screen button is clicked, for example.
/datum/action/proc/Trigger(trigger_flags)
	if(!IsAvailable())
		return FALSE
	return TRUE

/// Whether our action is currently available to use or not
/datum/action/proc/IsAvailable()
	var/mob/owner = action_owner()
	if(!owner)
		return FALSE
	if(check_flags & AB_CHECK_RESTRAINED)
		if(owner.restrained())
			return FALSE
	if(check_flags & AB_CHECK_STUNNED)
		if(owner.has_status(STAT_STUNNED))
			return FALSE
	if(check_flags & AB_CHECK_LYING)
		if(owner.lying)
			return FALSE
	if(check_flags & AB_CHECK_CONSCIOUS)
		if(owner.stat)
			return FALSE
	return TRUE

/// Builds / updates all buttons we have shared or given out
/datum/action/proc/build_all_button_icons(update_flags = ALL, force)
	for(var/atom/movable/screen/movable/action_button/button as anything in viewers)
		build_button_icon(button, update_flags, force)

/**
 * Builds the icon of the button.
 *
 * Concept:
 * - Underlay (Background icon)
 * - Icon (button icon)
 * - Maptext
 * - Overlay (Background border)
 *
 * button - which button we are modifying the icon of
 * force - whether we're forcing a full update
 */
/datum/action/proc/build_button_icon(atom/movable/screen/movable/action_button/button, update_flags = ALL, force = FALSE)
	if(!button)
		return

	if(update_flags & UPDATE_BUTTON_NAME)
		update_button_name(button, force)

	if(update_flags & UPDATE_BUTTON_BACKGROUND)
		apply_button_background(button, force)

	if(update_flags & UPDATE_BUTTON_ICON)
		apply_button_icon(button, force)

	if(update_flags & UPDATE_BUTTON_OVERLAY)
		apply_button_overlay(button, force)

	if(update_flags & UPDATE_BUTTON_STATUS)
		update_button_status(button, force)

/**
 * Updates the name and description of the button to match our action name and discription.
 *
 * current_button - what button are we editing?
 * force - whether an update is forced regardless of existing status
 */
/datum/action/proc/update_button_name(atom/movable/screen/movable/action_button/button, force = FALSE)
	button.name = name
	if(desc)
		button.desc = desc

/**
 * Creates the background underlay for the button
 *
 * current_button - what button are we editing?
 * force - whether an update is forced regardless of existing status
 */
/datum/action/proc/apply_button_background(atom/movable/screen/movable/action_button/current_button, force = FALSE)
	if(!background_icon || !background_icon_state || (current_button.active_underlay_icon_state == background_icon_state && !force))
		return

	// What icons we use for our background
	var/list/icon_settings = list(
		// The icon file
		"bg_icon" = background_icon,
		// The icon state, if is_action_active() returns FALSE
		"bg_state" = background_icon_state,
		// The icon state, if is_action_active() returns TRUE
		"bg_state_active" = background_icon_state,
	)

	// If background_icon_state is ACTION_BUTTON_DEFAULT_BACKGROUND instead use our hud's action button scheme
	var/mob/owner = action_owner()
	if(background_icon_state == ACTION_BUTTON_DEFAULT_BACKGROUND && owner?.hud_used)
		icon_settings = owner.hud_used.get_action_buttons_icons()

	// Determine which icon to use
	var/used_icon_key = is_action_active(current_button) ? "bg_state_active" : "bg_state"

	// Make the underlay
	current_button.underlays.Cut()
	current_button.underlays += image(icon = icon_settings["bg_icon"], icon_state = icon_settings[used_icon_key])
	current_button.active_underlay_icon_state = icon_settings[used_icon_key]

/**
 * Applies our button icon and icon state to the button
 *
 * current_button - what button are we editing?
 * force - whether an update is forced regardless of existing status
 */
/datum/action/proc/apply_button_icon(atom/movable/screen/movable/action_button/current_button, force = FALSE)
	if(!button_icon || !button_icon_state || (current_button.icon_state == button_icon_state && !force))
		return

	current_button.icon = button_icon
	current_button.icon_state = button_icon_state

/**
 * Applies any overlays to our button
 *
 * current_button - what button are we editing?
 * force - whether an update is forced regardless of existing status
 */
/datum/action/proc/apply_button_overlay(atom/movable/screen/movable/action_button/current_button, force = FALSE)
	if(!overlay_icon || !overlay_icon_state || (current_button.active_overlay_icon_state == overlay_icon_state && !force))
		return

	current_button.cut_overlay(current_button.button_overlay)
	current_button.button_overlay = mutable_appearance(icon = overlay_icon, icon_state = overlay_icon_state)
	current_button.add_overlay(current_button.button_overlay)
	current_button.active_overlay_icon_state = overlay_icon_state

/**
 * Any other miscellaneous "status" updates within the action button is handled here,
 * such as redding out when unavailable or modifying maptext.
 *
 * current_button - what button are we editing?
 * force - whether an update is forced regardless of existing status
 */
/datum/action/proc/update_button_status(atom/movable/screen/movable/action_button/current_button, force = FALSE)
	if(IsAvailable())
		current_button.color = rgb(255,255,255,255)
	else
		current_button.color = transparent_when_unavailable ? rgb(128,0,0,128) : rgb(128,0,0)

/// Gives our action to the passed viewer.
/// Puts our action in their actions list and shows them the button.
/datum/action/proc/GiveAction(mob/viewer)
	var/datum/hud/our_hud = viewer.hud_used
	if(our_hud && button_for(our_hud)) // Already have a copy of us? go away
		return

	rel_add(viewer, nameof(/mob::actions), src) // Move this in
	ShowTo(viewer)

/// Adds our action button to the screen of the passed viewer.
/datum/action/proc/ShowTo(mob/viewer)
	var/datum/hud/our_hud = viewer.hud_used
	if(!our_hud || button_for(our_hud)) // There's no point in this if you have no hud in the first place
		return

	var/atom/movable/screen/movable/action_button/button = create_button()
	SetId(button, viewer)

	rel_set(button, nameof(button.our_hud), our_hud)
	rel_add(src, nameof(viewers), button)
	if(viewer.client)
		viewer.client.screen += button

	button.load_position(viewer)
	viewer.update_action_buttons()

/// Removes our action from the passed viewer.
/datum/action/proc/HideFrom(mob/viewer)
	var/datum/hud/our_hud = viewer.hud_used
	var/atom/movable/screen/movable/action_button/button = button_for(our_hud)
	rel_remove(viewer, nameof(/mob::actions), src)
	if(button)
		own_remove(src, nameof(viewers), button)

/// Creates an action button movable for the passed mob, and returns it.
/datum/action/proc/create_button()
	var/atom/movable/screen/movable/action_button/button = new()
	rel_set(button, nameof(button.linked_action), src)
	build_button_icon(button, ALL, TRUE)
	return button

/datum/action/proc/SetId(atom/movable/screen/movable/action_button/our_button, mob/owner)
	//button id generation
	var/bitfield = 0
	for(var/datum/action/action in owner.actions)
		if(action == src) // This could be us, which is dumb
			continue
		var/atom/movable/screen/movable/action_button/button = action.button_for(owner.hud_used)
		if(action.name == name && button?.id)
			bitfield |= button.id

	bitfield = ~bitfield // Flip our possible ids, so we can check if we've found a unique one
	for(var/i in 0 to 23) // We get 24 possible bitflags in dm
		var/bitflag = 1 << i // Shift us over one
		if(bitfield & bitflag)
			our_button.id = bitflag
			return

/// Checks if our action is actively selected. Used for selecting icons primarily.
/datum/action/proc/is_action_active(atom/movable/screen/movable/action_button/current_button)
	return FALSE
