/obj/item/rig/proc/install_module_done(mob/living/user, obj/item/rig_module/mod)
	if(!user.unEquip(mod))
		return
	to_chat(user, "You install \the [mod] into \the [src].")
	LAZYOR(installed_modules, mod)
	mod.forceMove(src)
	mod.installed(src)
	update_icon()

EXTEND_INTERACTIONS(/obj/item/rig, \
	INTERACT_ITEM(null, PROC_REF(rig_item)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(rig_shock_hand)), \
	INTERACT_VERB("Open Hardsuit Interface", PROC_REF(rig_hardsuit_interface_verb), REQ_IN_INVENTORY), \
	INTERACT_VERB("Toggle Visor", PROC_REF(rig_toggle_vision_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_active), REQ_FIELD("visor", "the hardsuit does not have a configurable visor")), \
	INTERACT_VERB("Toggle Helmet", PROC_REF(rig_toggle_helmet_verb), REQ_IN_INVENTORY, REQ_ON(PRED_TARGET, /obj/item/rig/proc/pred_has_helmet, "it has no helmet"), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Toggle Chestpiece", PROC_REF(rig_toggle_chest_verb), REQ_IN_INVENTORY, REQ_ON(PRED_TARGET, /obj/item/rig/proc/pred_has_chest, "it has no chestpiece")), \
	INTERACT_VERB("Toggle Gauntlets", PROC_REF(rig_toggle_gauntlets_verb), REQ_IN_INVENTORY, REQ_ON(PRED_TARGET, /obj/item/rig/proc/pred_has_gauntlets, "it has no gauntlets"), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Toggle Boots", PROC_REF(rig_toggle_boots_verb), REQ_IN_INVENTORY, REQ_ON(PRED_TARGET, /obj/item/rig/proc/pred_has_boots, "it has no boots"), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Deploy Hardsuit", PROC_REF(rig_deploy_suit_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Toggle Hardsuit", PROC_REF(rig_toggle_seals_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Switch Vision Mode", PROC_REF(rig_switch_vision_mode_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_active), REQ_FIELD("visor", "the hardsuit does not have a configurable visor")), \
	INTERACT_VERB("Configure Voice Synthesiser", PROC_REF(rig_alter_voice_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_active), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn), REQ_FIELD("speech", "the hardsuit does not have a speech synthesiser")), \
	INTERACT_VERB("Select Module", PROC_REF(rig_select_module_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_active), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Toggle Module", PROC_REF(rig_toggle_module_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_active), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
	INTERACT_VERB("Engage Module", PROC_REF(rig_engage_module_verb), REQ_IN_INVENTORY, REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_active), REQ_TARGET_STATE(/obj/item/rig/proc/pred_rig_worn)), \
)

/// Old attackby: lock, install a tank, module or cell, or hand the item to a module.
/obj/item/rig/proc/rig_item(mob/living/user, obj/item/W, datum/interaction/interaction)
	if(!istype(user))
		return INTERACTION_HANDLED_PASS

	if(electrified != 0)
		if(shock(user)) //Handles removing charge from the cell, as well. No need to do that here.
			return INTERACTION_HANDLED_PASS

	// Pass repair items on to the chestpiece.
	if(chest && istype(W, /obj/item/stack/material))
		return chest.attackby(W,user) ? TRUE : INTERACTION_HANDLED_PASS

	// Lock or unlock the access panel.
	if(W.GetID())
		if(subverted)
			locked = 0
			to_chat(user, span_danger("It looks like the locking system has been shorted out."))
			return INTERACTION_HANDLED_PASS

		if(!LAZYLEN(req_access) && !LAZYLEN(req_one_access))
			locked = 0
			to_chat(user, span_danger("\The [src] doesn't seem to have a locking mechanism."))
			return INTERACTION_HANDLED_PASS

		if(security_check_enabled && !src.allowed(user))
			to_chat(user, span_danger("Access denied."))
			return INTERACTION_HANDLED_PASS

		locked = !locked
		to_chat(user, "You [locked ? "lock" : "unlock"] \the [src] access panel.")
		return INTERACTION_HANDLED_PASS

	if(open)
		// Air tank.
		if(istype(W,/obj/item/tank)) //Todo, some kind of check for suits without integrated air supplies.

			if(air_supply)
				to_chat(user, "\The [src] already has a tank installed.")
				return INTERACTION_HANDLED_PASS

			if(!user.unEquip(W))
				return INTERACTION_HANDLED_PASS

			air_supply = W
			W.forceMove(src)
			to_chat(user, "You slot [W] into [src] and tighten the connecting valve.")
			return INTERACTION_HANDLED_PASS

		// Check if this is a hardsuit upgrade or a modification.
		else if(istype(W,/obj/item/rig_module))
			if(ishuman(src.loc))
				var/mob/living/carbon/human/H = src.loc
				if(H.get_equipped_item(SLOT_ID_BACK) == src || H.get_equipped_item(SLOT_ID_BELT) == src)
					to_chat(user, span_danger("You can't install a hardsuit module while the suit is being worn."))
					return TRUE

			if(!installed_modules)
				installed_modules = list()
			if(length(installed_modules))
				for(var/obj/item/rig_module/installed_mod in installed_modules)
					if(!installed_mod.redundant && istype(installed_mod,W))
						to_chat(user, "The hardsuit already has a module of that class installed.")
						return TRUE

			var/obj/item/rig_module/mod = W
			to_chat(user, "You begin installing \the [mod] into \the [src].")
			om_task_timed(user, 4 SECONDS, src, src, PROC_REF(install_module_done), list(user, mod))
			return TRUE

		else if(!cell && istype(W,/obj/item/cell))

			if(!user.unEquip(W))
				return INTERACTION_HANDLED_PASS
			to_chat(user, "You jack \the [W] into \the [src]'s battery mount.")
			W.forceMove(src)
			src.cell = W
			return INTERACTION_HANDLED_PASS

		return INTERACTION_HANDLED_PASS

	// If we've gotten this far, all we have left to do before we pass off to root procs
	// is check if any of the loaded modules want to use the item we've been given.
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.accepts_item(W,user)) //Item is handled in this proc
			return INTERACTION_HANDLED_PASS
	return FALSE

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
	var/to_remove = rerun_ask(user, "a1", TYPE_PROC_REF(/atom, screwdriver_act), args, /datum/om/prompt/choice, message = "Which would you like to modify?", title = "Removal Choice", choices = current_mounts)
	if(isnull(to_remove))
		return ITEM_INTERACT_BLOCKING
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
	var/removal_choice = rerun_ask(user, "a2", TYPE_PROC_REF(/atom, screwdriver_act), args, /datum/om/prompt/choice, message = "Which module would you like to remove?", title = "Removal Choice", choices = possible_removals)
	if(isnull(removal_choice))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/rig_module/removed = possible_removals[removal_choice]
	if(!removed)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You detach \the [removed] from \the [src].")
	removed.forceMove(get_turf(src))
	removed.removed()
	LAZYREMOVE(installed_modules, removed)
	update_icon()
	return ITEM_INTERACT_SUCCESS


/// Old attack_hand: an electrified suit shocks whoever grabs it.
/obj/item/rig/proc/rig_shock_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(electrified != 0)
		if(shock(user)) //Handles removing charge from the cell, as well. No need to do that here.
			return TRUE
	return FALSE

DECLARE_EMAG_REPEATABLE(/obj/item/rig, PROC_REF(on_emag), null)
/obj/item/rig/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(!subverted)
		req_access = null
		req_one_access = null
		locked = 0
		subverted = 1
		to_chat(user, span_danger("You short out the access protocol for the suit."))
		return 1
