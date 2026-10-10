/// Four seconds with the module in the hand (rig_item() starts it once the suit has passed its checks).
/obj/item/rig/proc/install_module_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/rig_module/mod = A.held
	if(QDELETED(mod))
		return OP_REFUSED
	to_chat(user, "You install \the [mod] into \the [src].")
	if(!move_into(src, nameof(src.installed_modules), mod, user))
		return OP_OK
	mod.installed(src)
	return OP_OK

/// Old attackby: lock, install a tank, module or cell, or hand the item to a module.
/obj/item/rig/proc/rig_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(!istype(user))
		return OP_PASS

	if(electrified != 0)
		if(shock(user)) //Handles removing charge from the cell, as well. No need to do that here.
			return OP_PASS

	// Pass repair items on to the chestpiece.
	if(chest && istype(W, /obj/item/stack/material))
		return chest.attackby(W,user) ? OP_OK : OP_PASS

	// Lock or unlock the access panel.
	if(W.GetID())
		if(subverted)
			locked = 0
			to_chat(user, span_danger("It looks like the locking system has been shorted out."))
			return OP_PASS

		if(!LAZYLEN(req_access) && !LAZYLEN(req_one_access))
			locked = 0
			to_chat(user, span_danger("\The [src] doesn't seem to have a locking mechanism."))
			return OP_PASS

		if(security_check_enabled && !src.allowed(user))
			to_chat(user, span_danger("Access denied."))
			return OP_PASS

		locked = !locked
		to_chat(user, "You [locked ? "lock" : "unlock"] \the [src] access panel.")
		return OP_PASS

	if(open)
		// Air tank.
		if(istype(W,/obj/item/tank)) //Todo, some kind of check for suits without integrated air supplies.

			if(air_supply)
				to_chat(user, "\The [src] already has a tank installed.")
				return OP_PASS


			if(!move_into(src, nameof(src.air_supply), W, user))
				return OP_PASS
			to_chat(user, "You slot [W] into [src] and tighten the connecting valve.")
			return OP_PASS

		// Check if this is a hardsuit upgrade or a modification.
		else if(istype(W,/obj/item/rig_module))
			if(ishuman(src.loc))
				var/mob/living/carbon/human/H = src.loc
				if(H.get_equipped_item(SLOT_ID_BACK) == src || H.get_equipped_item(SLOT_ID_BELT) == src)
					to_chat(user, span_danger("You can't install a hardsuit module while the suit is being worn."))
					return OP_OK

			if(length(installed_modules))
				for(var/obj/item/rig_module/installed_mod in installed_modules)
					if(!installed_mod.redundant && istype(installed_mod,W))
						to_chat(user, "The hardsuit already has a module of that class installed.")
						return OP_OK

			var/obj/item/rig_module/mod = W
			to_chat(user, "You begin installing \the [mod] into \the [src].")
			perform_op(user, src, "install_module", mod, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
			return OP_OK

		else if(!cell && istype(W,/obj/item/cell))

			to_chat(user, "You jack \the [W] into \the [src]'s battery mount.")
			if(!move_into(src, nameof(src.cell), W, user))
				return OP_PASS
			return OP_PASS

		return OP_PASS

	// If we've gotten this far, all we have left to do before we pass off to root procs
	// is check if any of the loaded modules want to use the item we've been given.
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.accepts_item(W,user)) //Item is handled in this proc
			return OP_PASS
	return OP_DECLINE

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
	wires_open(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/item/rig/multitool_act(mob/user, obj/item/tool)
	return wirecutter_act(user, tool)

/obj/item/rig/wrench_act(mob/user, obj/item/tool)
	if(!open || !air_supply)
		to_chat(user, open ? "There is no tank to remove." : "You can't reach the tank mount.")
		return ITEM_INTERACT_BLOCKING
	var/obj/item/tank/removed_tank = air_supply
	user.put_in_hands(removed_tank)
	rel_take(src, nameof(air_supply))
	to_chat(user, "You detach and remove \the [removed_tank].")
	return ITEM_INTERACT_SUCCESS

/obj/item/rig/screwdriver_act(mob/user, obj/item/tool, answered_mount = null, answered_module = null)
	if(!open)
		return ITEM_INTERACT_BLOCKING
	var/list/current_mounts = list()
	if(cell)
		current_mounts += "cell"
	if(length(installed_modules))
		current_mounts += "system module"
	if(isnull(answered_mount))
		open_maintenance_request(user, tool, "Which would you like to modify?", current_mounts)
		return ITEM_INTERACT_BLOCKING
	var/to_remove = answered_mount
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
			module.deactivate(FALSE, user)
		user.put_in_hands(cell)
		rel_take(src, nameof(cell))
		return ITEM_INTERACT_SUCCESS
	var/list/possible_removals = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(!module.permanent)
			possible_removals[module.name] = module
	if(!length(possible_removals))
		to_chat(user, "There are no installed modules to remove.")
		return ITEM_INTERACT_BLOCKING
	if(isnull(answered_module))
		open_maintenance_request(user, tool, "Which module would you like to remove?", possible_removals, to_remove)
		return ITEM_INTERACT_BLOCKING
	var/removal_choice = answered_module
	if(isnull(removal_choice))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/rig_module/removed = possible_removals[removal_choice]
	if(!removed)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You detach \the [removed] from \the [src].")
	own_take_member(src, nameof(installed_modules), removed)
	removed.forceMove(get_turf(src))
	removed.removed()
	return ITEM_INTERACT_SUCCESS


/// Old attack_hand: an electrified suit shocks whoever grabs it.
/obj/item/rig/proc/rig_shock_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(electrified != 0)
		if(shock(user)) //Handles removing charge from the cell, as well. No need to do that here.
			return OP_OK
	return OP_DECLINE

/obj/item/rig/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!subverted)
		req_access = null
		req_one_access = null
		locked = 0
		subverted = 1
		to_chat(user, span_danger("You short out the access protocol for the suit."))
		return OP_OK
	return OP_DECLINE

/obj/item/rig/proc/open_maintenance_request(mob/user, obj/item/tool, question, list/choices, mount_choice = null)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/choice/rig_maintenance, PROC_REF(maintenance_chosen), answerer = user, captured_tool = tool, tool_expected = !isnull(tool), question = question, choices = choices, mount_choice = mount_choice, original_client_ckey = original_client_ckey)

/obj/item/rig/proc/maintenance_chosen(datum/act/request/A)
	if(!A.answer)
		return
	apply_maintenance_answer(A)
	SStgui.update_uis(src)

/obj/item/rig/proc/apply_maintenance_answer(datum/act/request/A)
	var/datum/prompt/choice/rig_maintenance/request = A.request
	if(request.captures_gone())
		return
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	if(isnull(request.mount_choice))
		return screwdriver_act(user, request.captured_tool, A.answer.value)
	return screwdriver_act(user, request.captured_tool, request.mount_choice, A.answer.value)

/datum/prompt/choice/rig_maintenance
	title = "Removal Choice"
	timeout = 0
	var/obj/item/captured_tool
	var/tool_expected = FALSE
	var/mount_choice
	var/original_client_ckey

CAPABILITIES(/datum/prompt/choice/rig_maintenance)
	ref_one(nameof(captured_tool), /obj/item)

/datum/prompt/choice/rig_maintenance/prepare(datum/act/A)
	. = ..()
	var/obj/item/tool = captured_tool
	rel_clear(src, nameof(captured_tool))
	rel_set(src, nameof(captured_tool), tool)

/datum/prompt/choice/rig_maintenance/proc/captures_gone()
	return QDELETED(answerer) || (tool_expected && QDELETED(captured_tool)) || (original_client_ckey && !GLOB.directory[original_client_ckey])

/datum/prompt/choice/rig_maintenance/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	return null
