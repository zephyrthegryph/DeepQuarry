
//Presets for item actions
/datum/action/item_action
	check_flags = AB_CHECK_RESTRAINED|AB_CHECK_STUNNED|AB_CHECK_LYING|AB_CHECK_CONSCIOUS
	// If you want to override the normal icon being the item
	// then change this to an icon state
	button_icon_state = null

	/// TRUE: the button shows the target item's appearance as an overlay
	/// (was /datum/component/action_item_overlay).
	var/item_overlay = FALSE
	/// The item appearance currently applied to the button.
	var/item_overlay_appearance

/datum/action/item_action/New(Target)
	. = ..()

	// If our button state is null, use the target's icon instead
	var/datum/target = action_target()
	if(target && isnull(button_icon_state))
		set_item_overlay(TRUE)

/datum/action/item_action/proc/set_item_overlay(enabled)
	if(item_overlay == enabled)
		return
	item_overlay = enabled
	build_all_button_icons(UPDATE_BUTTON_OVERLAY)

/datum/action/item_action/apply_button_overlay(atom/movable/screen/movable/action_button/current_button, force = FALSE)
	apply_item_overlay(current_button, force)
	return ..()

/// Applies (or, when disabled, removes) the target item's appearance on `current_button`.
/datum/action/item_action/proc/apply_item_overlay(atom/movable/screen/movable/action_button/current_button, force)
	if(!item_overlay)
		if(item_overlay_appearance)
			current_button.cut_overlay(item_overlay_appearance)
			item_overlay_appearance = null
		return

	var/atom/movable/muse = target
	if(!istype(muse))
		return

	var/mutable_appearance/current = item_overlay_appearance
	if(current)
		// For caching purposes, we will try not to update if we don't need to
		if(!force && current.icon == muse.icon && current.icon_state == muse.icon_state)
			return
		current_button.cut_overlay(current)

	var/mutable_appearance/muse_appearance = new(muse.appearance)
	muse_appearance.plane = FLOAT_PLANE
	muse_appearance.layer = FLOAT_LAYER
	muse_appearance.pixel_x = 0
	muse_appearance.pixel_y = 0

	current_button.add_overlay(muse_appearance)
	item_overlay_appearance = muse_appearance

/datum/action/item_action/vv_edit_var(var_name, var_value)
	. = ..()
	var/datum/target = action_target()
	if(!. || !target)
		return

	if(var_name == NAMEOF(src, button_icon_state))
		// If someone vv's our icon either add or remove the component
		set_item_overlay(isnull(var_value))

/datum/action/item_action/Trigger(trigger_flags)
	if(!..())
		return 0
	var/obj/item/item_target = action_target()
	if(item_target)
		item_target.ui_action_click(action_owner(), src.type)
	return 1

/datum/action/item_action/hands_free
	check_flags = AB_CHECK_CONSCIOUS
