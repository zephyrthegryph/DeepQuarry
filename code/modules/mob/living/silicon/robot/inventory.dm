//These procs handle putting s tuff in your hand. It's probably best to use these rather than setting stuff manually
//as they handle all relevant stuff like adding it to the player's screen and such

//Returns the thing in our active hand (whatever is in our active module-slot, in this case)
/mob/living/silicon/robot/get_active_hand(atom/A)
	if(module_active == A) //If we are interacting with the item itself (I.E swapping multibelt items)
		return module_active
	else if(isrobotmultibelt(module_active)) //If we are hitting something with a multibelt
		var/obj/item/robotic_multibelt/belt = module_active
		if(belt.selected_item)
			return belt.selected_item
	return module_active

/*-------TODOOOOOOOOOO--------*/

//Verbs used by hotkeys.
/mob/living/silicon/robot/verb/cmd_unequip_module()
	set name = "unequip-module"
	set hidden = 1
	uneq_active()

/mob/living/silicon/robot/verb/cmd_toggle_module(module as num)
	set name = "toggle-module"
	set hidden = 1
	toggle_module(module)

// --- Module slots ------------------------------------------------------------------------
// The three module slots are module_state_1..3. Slot logic is written once,
// here, and reached by slot number.

/mob/living/silicon/robot/proc/get_module_slot(slot)
	switch(slot)
		if(1)
			return module_state_1
		if(2)
			return module_state_2
		if(3)
			return module_state_3
	return null

/mob/living/silicon/robot/proc/set_module_slot(slot, obj/item/I)
	switch(slot)
		if(1)
			module_state_1 = I
		if(2)
			module_state_2 = I
		if(3)
			module_state_3 = I

/mob/living/silicon/robot/proc/get_module_slot_screen(slot)
	switch(slot)
		if(1)
			return inv1
		if(2)
			return inv2
		if(3)
			return inv3
	return null

/mob/living/silicon/robot/proc/get_module_slot_screen_loc(slot)
	switch(slot)
		if(1)
			return ui_inv1
		if(2)
			return ui_inv2
		if(3)
			return ui_inv3
	return null

/// Return the item in `slot` to the module. No appearance or HUD refresh.
/mob/living/silicon/robot/proc/clear_module_slot(slot)
	var/obj/item/I = get_module_slot(slot)
	if(!I)
		return null
	if(isrobotmultibelt(I))
		var/obj/item/robotic_multibelt/toolbelt = I
		toolbelt.original_state()
	if(istype(I, /obj/item/borg/sight))
		var/obj/item/borg/sight/S = I
		sight_mode &= ~S.sight_mode
	if(client)
		client.screen -= I
	contents -= I
	if(module_active == I)
		module_active = null
	for(var/datum/action/A as anything in I.actions)
		A.Remove(src)
	I.loc = module //So it can be used again later (no Moved side effects, as before)
	set_module_slot(slot, null)
	var/atom/movable/screen/slot_screen = get_module_slot_screen(slot)
	if(slot_screen)
		slot_screen.icon_state = "inv[slot]"
	return I

/mob/living/silicon/robot/proc/uneq_specific(obj/item/I)
	if(!istype(I))
		return
	var/slot = get_slot_from_module(I)
	if(!slot)
		return
	clear_module_slot(slot)
	after_equip()
	update_icon()
	if(shown_robot_modules)
		hud_used.update_robot_modules_display()

/mob/living/silicon/robot/proc/uneq_active()
	if(isnull(module_active))
		return
	uneq_specific(module_active)

/// Drop every module. Called on events (stat change, weapon lock, EMP),
/// never per tick; does nothing (and redraws nothing) when already empty.
/mob/living/silicon/robot/proc/uneq_all()
	module_active = null
	var/removed_any_module = FALSE
	for(var/slot in 1 to 3)
		if(clear_module_slot(slot))
			removed_any_module = TRUE
	if(!removed_any_module)
		return
	after_equip()
	update_icon()

	// Refresh inventory if needed
	if(hud_used && shown_robot_modules)
		hud_used.update_robot_modules_display()

// Just used for pretty display in TGUI
/mob/living/silicon/robot/proc/get_slot_from_module(obj/item/I)
	if(module_state_1 == I)
		return 1
	else if(module_state_2 == I)
		return 2
	else if(module_state_3 == I)
		return 3
	else
		return 0

/mob/living/silicon/robot/proc/activated(obj/item/O)
	var/belt_check = using_multibelt(O)
	if(belt_check)
		return belt_check
	if(module_state_1 == O)
		return 1
	else if(module_state_2 == O)
		return 1
	else if(module_state_3 == O)
		return 1
	else
		return 0

/mob/living/silicon/robot/proc/using_multibelt(obj/item/O)
	for(var/obj/item/robotic_multibelt/materials/material_belt in contents)
		if(material_belt.selected_item == O)
			return TRUE
	for(var/obj/item/gripper/gripper in contents)
		if(gripper.current_pocket == O || (O in gripper.current_pocket.contents))
			return TRUE
	return FALSE

/mob/living/silicon/robot/proc/get_active_modules()
	return list(module_state_1, module_state_2, module_state_3)

// This one takes an object's type instead of an instance, as above.
/mob/living/silicon/robot/proc/has_active_type(type_to_compare, explicit = FALSE)
	var/list/active_modules = get_active_modules()
	if(is_type_in_modules(type_to_compare, active_modules, explicit))
		return TRUE
	return FALSE

/// Searches through a provided list to see if we have a module that is in that list.
/mob/living/silicon/robot/proc/has_active_type_list(list/type_to_compare, explicit = FALSE)
	var/list/active_modules = get_active_modules()
	if(islist(type_to_compare))
		for(var/object_to_compare in type_to_compare)
			if(is_type_in_modules(object_to_compare, active_modules, explicit))
				return TRUE
	return FALSE

// Checks if the activated module is of the given type
/mob/living/silicon/robot/proc/activated_module_type_list(list/type_to_compare, explicit = FALSE)
	if(!islist(type_to_compare))
		return FALSE
	for(var/type in type_to_compare)
		if(istype(module_active, type))
			return TRUE
	return FALSE

/mob/living/silicon/robot/proc/is_type_in_modules(type, list/modules, explicit = FALSE)
	for(var/atom/module in modules)
		if(explicit && isatom(module))
			if(module.type == type)
				return TRUE
		else if(istype(module, type))
			return TRUE
	return FALSE

//Helper procs for cyborg modules on the UI.
//These are hackish but they help clean up code elsewhere.

//module_selected(module) - Checks whether the module slot specified by "module" is currently selected.
/mob/living/silicon/robot/proc/module_selected(module) //Module is 1-3
	return module == get_selected_module()

//module_active(module) - Checks whether there is a module active in the slot specified by "module".
/mob/living/silicon/robot/proc/module_active(module) //Module is 1-3
	return get_module_slot(module) ? 1 : 0

//get_selected_module() - Returns the slot number of the currently selected module.  Returns 0 if no modules are selected.
/mob/living/silicon/robot/proc/get_selected_module()
	if(module_state_1 && module_active == module_state_1)
		return 1
	else if(module_state_2 && module_active == module_state_2)
		return 2
	else if(module_state_3 && module_active == module_state_3)
		return 3

	return 0

//select_module(module) - Selects the module slot specified by "module"
/mob/living/silicon/robot/proc/select_module(module) //Module is 1-3
	if(module < 1 || module > 3)
		return
	var/obj/item/I = get_module_slot(module)
	if(!I || module_active == I)
		return
	for(var/slot in 1 to 3)
		var/atom/movable/screen/slot_screen = get_module_slot_screen(slot)
		if(slot_screen)
			slot_screen.icon_state = slot == module ? "inv[slot] +a" : "inv[slot]"
	module_active = I
	update_icon()

//deselect_module(module) - Deselects the module slot specified by "module"
/mob/living/silicon/robot/proc/deselect_module(module) //Module is 1-3
	if(module < 1 || module > 3)
		return
	var/obj/item/I = get_module_slot(module)
	if(!I || module_active != I)
		return
	var/atom/movable/screen/slot_screen = get_module_slot_screen(module)
	if(slot_screen)
		slot_screen.icon_state = "inv[module]"
	module_active = null
	update_icon()

//toggle_module(module) - Toggles the selection of the module slot specified by "module".
/mob/living/silicon/robot/proc/toggle_module(module) //Module is 1-3
	if(module < 1 || module > 3) return

	if(module_selected(module))
		deselect_module(module)
	else
		if(module_active(module))
			select_module(module)
		else
			deselect_module(get_selected_module()) //If we can't do select anything, at least deselect the current module.
	return

//cycle_modules() - Cycles through the list of selected modules.
/mob/living/silicon/robot/proc/cycle_modules()
	var/slot_start = get_selected_module()
	if(slot_start) deselect_module(slot_start) //Only deselect if we have a selected slot.

	var/slot_num
	if(slot_start == 0)
		slot_num = 1
	else
		slot_num = slot_start + 1
		if(slot_num > 3)
			return
	// Attempt to rotate through the slots until we're past slot 3, or find the next usable slot. Allows skipping empty slots, while still having an empty slot at end of rotation.
	while(slot_num <= 3)
		if(module_active(slot_num))
			select_module(slot_num)
			return
		slot_num++

	return

/mob/living/silicon/robot/proc/activate_module(obj/item/O)
	if(!(locate(O) in src.module.modules) && !(locate(O) in src.module.emag))
		return
	if(weapon_lock)
		to_chat(src, span_danger("Error: Modules locked."))
		return
	if(activated(O))
		to_chat(src, span_notice("Already activated"))
		return
	for(var/slot in 1 to 3)
		if(get_module_slot(slot))
			continue
		set_module_slot(slot, O)
		O.hud_layerise()
		var/atom/movable/screen/slot_screen = get_module_slot_screen(slot)
		O.screen_loc = slot_screen?.screen_loc
		contents += O
		if(istype(O, /obj/item/borg/sight))
			var/obj/item/borg/sight/S = O
			sight_mode |= S.sight_mode
		update_icon()
		after_equip(O)
		return
	to_chat(src, span_notice("You need to disable a module first!"))

/// Equipment changed: power demand is recomputed and modules/components react
/// through COMSIG_ROBOT_EQUIPMENT_CHANGED (the belly component handles its ore
/// bag and pounce there).
/mob/living/silicon/robot/proc/after_equip(obj/item/O)
	if(istype(O, /obj/item/gps))
		var/obj/item/gps/tracker = O
		if(tracker.tracking)
			tracker.tracking = FALSE
			tracker.toggle_tracking()
	recompute_power_demand()
	SEND_SIGNAL(src, COMSIG_ROBOT_EQUIPMENT_CHANGED, O)
	if(O)
		for(var/datum/action/A as anything in O.actions)
			A.Grant(src)

/mob/living/silicon/robot/put_in_hands(obj/item/W) // No hands.
	W.forceMove(get_turf(src))
	return 1

/mob/living/silicon/robot/is_holding_item_of_type(typepath)
	for(var/obj/item/I in list(module_state_1, module_state_2, module_state_3))
		if(istype(I, typepath))
			return I
	return FALSE

// Returns a list of all held items in a borg's 'hands'.
/mob/living/silicon/robot/get_all_held_items()
	. = list()
	if(module_state_1)
		. += module_state_1
	if(module_state_2)
		. += module_state_2
	if(module_state_3)
		. += module_state_3
