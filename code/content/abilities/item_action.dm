// Presets for item actions: an ability an item gives the mob wearing or holding it (items.dm add_item_action()). The item's own
// appearance is the icon unless the action names an icon state.
/datum/action/item_action
	check_flags = AB_CHECK_RESTRAINED|AB_CHECK_STUNNED|AB_CHECK_LYING|AB_CHECK_CONSCIOUS
	// If you want to override the normal icon being the item
	// then change this to an icon state
	button_icon_state = null

/datum/action/item_action/Trigger(trigger_flags)
	if(!..())
		return 0
	var/obj/item/item_target = action_target()
	if(item_target)
		item_target.ui_action_click(action_owner(), src.type)
	return 1

/// The hover text names the item the ability belongs to.
/datum/action/item_action/ability_desc()
	var/obj/item/item_target = action_target()
	if(desc)
		return desc
	return item_target ? "[name] ([item_target.name])" : name

/// A toggle shows whether the item has it on (obj/item/proc/action_toggle_state()).
/datum/action/item_action/ability_toggled()
	var/obj/item/item_target = action_target()
	return istype(item_target) ? item_target.action_toggle_state(type) : null

/datum/action/item_action/hands_free
	check_flags = AB_CHECK_CONSCIOUS
