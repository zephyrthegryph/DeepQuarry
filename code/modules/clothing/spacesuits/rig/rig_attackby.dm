/obj/item/rig/attackby(obj/item/W, mob/living/user)
	if(!istype(user))
		return 0

	if(electrified != 0)
		if(shock(user)) //Handles removing charge from the cell, as well. No need to do that here.
			return

	// Pass repair items on to the chestpiece.
	if(chest && istype(W, /obj/item/stack/material))
		return chest.attackby(W,user)

	// Lock or unlock the access panel.
	if(W.GetID())
		if(subverted)
			locked = 0
			to_chat(user, span_danger("It looks like the locking system has been shorted out."))
			return

		if(!LAZYLEN(req_access) && !LAZYLEN(req_one_access))
			locked = 0
			to_chat(user, span_danger("\The [src] doesn't seem to have a locking mechanism."))
			return

		if(security_check_enabled && !src.allowed(user))
			to_chat(user, span_danger("Access denied."))
			return

		locked = !locked
		to_chat(user, "You [locked ? "lock" : "unlock"] \the [src] access panel.")
		return

	if(open)
		// Air tank.
		if(istype(W,/obj/item/tank)) //Todo, some kind of check for suits without integrated air supplies.

			if(air_supply)
				to_chat(user, "\The [src] already has a tank installed.")
				return

			if(!user.unEquip(W))
				return

			air_supply = W
			W.forceMove(src)
			to_chat(user, "You slot [W] into [src] and tighten the connecting valve.")
			return

		// Check if this is a hardsuit upgrade or a modification.
		else if(istype(W,/obj/item/rig_module))
			if(ishuman(src.loc))
				var/mob/living/carbon/human/H = src.loc
				if(H.get_equipped_item(SLOT_ID_BACK) == src || H.get_equipped_item(SLOT_ID_BELT) == src)
					to_chat(user, span_danger("You can't install a hardsuit module while the suit is being worn."))
					return 1

			if(!installed_modules)
				installed_modules = list()
			if(installed_modules.len)
				for(var/obj/item/rig_module/installed_mod in installed_modules)
					if(!installed_mod.redundant && istype(installed_mod,W))
						to_chat(user, "The hardsuit already has a module of that class installed.")
						return 1

			var/obj/item/rig_module/mod = W
			to_chat(user, "You begin installing \the [mod] into \the [src].")
			if(!do_after(user, 4 SECONDS, target = src))
				return
			if(!user || !W)
				return
			if(!user.unEquip(mod))
				return
			to_chat(user, "You install \the [mod] into \the [src].")
			installed_modules |= mod
			mod.forceMove(src)
			mod.installed(src)
			update_icon()
			return 1

		else if(!cell && istype(W,/obj/item/cell))

			if(!user.unEquip(W))
				return
			to_chat(user, "You jack \the [W] into \the [src]'s battery mount.")
			W.forceMove(src)
			src.cell = W
			return

		return

	// If we've gotten this far, all we have left to do before we pass off to root procs
	// is check if any of the loaded modules want to use the item we've been given.
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.accepts_item(W,user)) //Item is handled in this proc
			return
	return ..()

/obj/item/rig/welder_act(mob/user, obj/item/tool)
	if(!chest)
		return ITEM_INTERACT_BLOCKING
	return chest.welder_act(user, tool)

/obj/item/rig/crowbar_act(mob/user, obj/item/tool)
	if(!open && locked)
		to_chat(user, "The access panel is locked shut.")
		return ITEM_INTERACT_BLOCKING
	open = !open
	to_chat(user, "You [open ? "open" : "close"] the access panel.")
	return ITEM_INTERACT_SUCCESS

/obj/item/rig/wirecutter_act(mob/user, obj/item/tool)
	if(!open)
		to_chat(user, "You can't reach the wiring.")
		return ITEM_INTERACT_BLOCKING
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/item/rig/multitool_act(mob/user, obj/item/tool)
	return wirecutter_act(user, tool)

/obj/item/rig/wrench_act(mob/user, obj/item/tool)
	if(!open || !air_supply)
		to_chat(user, open ? "There is no tank to remove." : "You can't reach the tank mount.")
		return ITEM_INTERACT_BLOCKING
	var/obj/item/tank/removed_tank = air_supply
	user.put_in_hands(removed_tank)
	air_supply = null
	to_chat(user, "You detach and remove \the [removed_tank].")
	return ITEM_INTERACT_SUCCESS

/obj/item/rig/screwdriver_act(mob/user, obj/item/tool)
	if(!open)
		return ITEM_INTERACT_BLOCKING
	var/list/current_mounts = list()
	if(cell)
		current_mounts += "cell"
	if(length(installed_modules))
		current_mounts += "system module"
	var/to_remove = tgui_input_list(user, "Which would you like to modify?", "Removal Choice", current_mounts)
	if(!to_remove)
		return ITEM_INTERACT_BLOCKING
	if(ishuman(loc) && to_remove != "cell")
		var/mob/living/carbon/human/wearer = loc
		if(wearer.get_equipped_item(SLOT_ID_BACK) == src || wearer.get_equipped_item(SLOT_ID_BELT) == src)
			to_chat(user, "You can't remove an installed device while the hardsuit is being worn.")
			return ITEM_INTERACT_BLOCKING
	if(to_remove == "cell")
		to_chat(user, "You detach \the [cell] from \the [src]'s battery mount.")
		for(var/obj/item/rig_module/module in installed_modules)
			module.deactivate()
		user.put_in_hands(cell)
		cell = null
		return ITEM_INTERACT_SUCCESS
	var/list/possible_removals = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(!module.permanent)
			possible_removals[module.name] = module
	if(!length(possible_removals))
		to_chat(user, "There are no installed modules to remove.")
		return ITEM_INTERACT_BLOCKING
	var/removal_choice = tgui_input_list(user, "Which module would you like to remove?", "Removal Choice", possible_removals)
	var/obj/item/rig_module/removed = possible_removals[removal_choice]
	if(!removed)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You detach \the [removed] from \the [src].")
	removed.forceMove(get_turf(src))
	removed.removed()
	installed_modules -= removed
	update_icon()
	return ITEM_INTERACT_SUCCESS


/obj/item/rig/attack_hand(mob/user)

	if(electrified != 0)
		if(shock(user)) //Handles removing charge from the cell, as well. No need to do that here.
			return
	..()

/obj/item/rig/emag_act(remaining_charges, mob/user)
	if(!subverted)
		req_access = null
		req_one_access = null
		locked = 0
		subverted = 1
		to_chat(user, span_danger("You short out the access protocol for the suit."))
		return 1
