// Interface for humans. The Menu entries are declared with the rest of the rig's interactions (rig_attackby.dm).

/// Old verb "Open Hardsuit Interface".
/obj/item/rig/proc/rig_hardsuit_interface_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(wearer() && (wearer().get_equipped_item(SLOT_ID_BACK) == src || wearer().get_equipped_item(SLOT_ID_BELT) == src))
		tgui_interact(user)

// So the UI button clicks come here
/obj/item/rig/ui_action_click(mob/user, actiontype)
	if(user == wearer() && (wearer().get_equipped_item(SLOT_ID_BACK) == src || wearer().get_equipped_item(SLOT_ID_BELT) == src))
		tgui_interact(user)

/// Old verb "Toggle Visor".
/obj/item/rig/proc/rig_toggle_vision_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_power_cost(user))
		return

	if(!check_suit_access(user))
		return

	if(!visor.active)
		visor.activate(FALSE, user)
	else
		visor.deactivate(FALSE, user)

/// Old verb "Toggle Helmet" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_helmet_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_suit_access(user))
		return

	toggle_piece("helmet",wearer())

/// Old verb "Toggle Chestpiece" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_chest_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_suit_access(user))
		return

	toggle_piece("chest",wearer())

/// Old verb "Toggle Gauntlets" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_gauntlets_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_suit_access(user))
		return

	toggle_piece("gauntlets",wearer())

/// Old verb "Toggle Boots" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_boots_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_suit_access(user))
		return

	toggle_piece("boots",wearer())

/// Old verb "Deploy Hardsuit".
/obj/item/rig/proc/rig_deploy_suit_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_suit_access(user))
		return

	if(!check_power_cost(user))
		return

	deploy(wearer())

/// Old verb "Toggle Hardsuit".
/obj/item/rig/proc/rig_toggle_seals_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_suit_access(user))
		return

	toggle_seals(wearer())

/// Old verb "Switch Vision Mode".
/obj/item/rig/proc/rig_switch_vision_mode_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	if(!visor.active)
		visor.activate(FALSE, user)

	if(!visor.active)
		to_chat(user, span_warning("The visor is suffering a hardware fault and cannot be configured."))
		return

	visor.engage(null, FALSE, user)

/// Old verb "Configure Voice Synthesiser".
/obj/item/rig/proc/rig_alter_voice_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(malfunction_check(user))
		return

	speech.engage(null, FALSE, user)

/// Old verb "Select Module".
/obj/item/rig/proc/rig_select_module_verb(datum/act/op/A)
	return select_module_for(A.actor)

/obj/item/rig/proc/select_module_for(mob/user, obj/item/rig_module/answered_module = null)
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	var/list/selectable = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.selectable)
			selectable |= module

	if(isnull(answered_module))
		var/original_client_ckey
		if(istype(user, /client))
			var/client/C = user
			original_client_ckey = C.ckey
			user = C.mob
		if(!ismob(user) || QDELETED(user))
			return
		open_request(src, /datum/prompt/choice/rig_module_selection, PROC_REF(select_module_chosen), answerer = user, question = "Which module do you wish to select?", title = "Select Module", choices = selectable, original_client_ckey = original_client_ckey)
		return
	var/obj/item/rig_module/module = answered_module
	if(isnull(module))
		return

	if(!istype(module))
		rel_clear(src, nameof(selected_module))
		to_chat(user, span_boldnotice("Primary system is now: deselected."))
		return

	rel_set(src, nameof(selected_module), module)
	to_chat(user, span_boldnotice("Primary system is now: [selected_module.interface_name]."))

/// Old verb "Toggle Module".
/obj/item/rig/proc/rig_toggle_module_verb(datum/act/op/A)
	return toggle_module_for(A.actor)

/obj/item/rig/proc/toggle_module_for(mob/user, obj/item/rig_module/answered_module = null)
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	var/list/selectable = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.toggleable)
			selectable |= module

	if(isnull(answered_module))
		var/original_client_ckey
		if(istype(user, /client))
			var/client/C = user
			original_client_ckey = C.ckey
			user = C.mob
		if(!ismob(user) || QDELETED(user))
			return
		open_request(src, /datum/prompt/choice/rig_module_selection, PROC_REF(toggle_module_chosen), answerer = user, question = "Which module do you wish to toggle?", title = "Toggle Module", choices = selectable, original_client_ckey = original_client_ckey)
		return
	var/obj/item/rig_module/module = answered_module
	if(isnull(module))
		return

	if(!istype(module))
		return

	if(module.active)
		to_chat(user, span_boldnotice("You attempt to deactivate \the [module.interface_name]."))
		module.deactivate(FALSE, user)
	else
		to_chat(user, span_boldnotice("You attempt to activate \the [module.interface_name]."))
		module.activate(FALSE, user)

/// Old verb "Engage Module".
/obj/item/rig/proc/rig_engage_module_verb(datum/act/op/A)
	return engage_module_for(A.actor)

/obj/item/rig/proc/engage_module_for(mob/user, obj/item/rig_module/answered_module = null)
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	var/list/selectable = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.usable)
			selectable |= module

	if(isnull(answered_module))
		var/original_client_ckey
		if(istype(user, /client))
			var/client/C = user
			original_client_ckey = C.ckey
			user = C.mob
		if(!ismob(user) || QDELETED(user))
			return
		open_request(src, /datum/prompt/choice/rig_module_selection, PROC_REF(engage_module_chosen), answerer = user, question = "Which module do you wish to engage?", title = "Engage Module", choices = selectable, original_client_ckey = original_client_ckey)
		return
	var/obj/item/rig_module/module = answered_module
	if(isnull(module))
		return

	if(!istype(module))
		return

	to_chat(user, span_boldnotice("You attempt to engage the [module.interface_name]."))
	module.engage(null, FALSE, user)

/// Requirement: the suit has this piece (replaces adding the toggle verbs when the piece was built).
/obj/item/rig/proc/pred_has_helmet(mob/actor, atom/target, obj/item/held)
	return !!helmet

/obj/item/rig/proc/pred_has_chest(mob/actor, atom/target, obj/item/held)
	return !!chest

/obj/item/rig/proc/pred_has_gauntlets(mob/actor, atom/target, obj/item/held)
	return !!gloves

/obj/item/rig/proc/pred_has_boots(mob/actor, atom/target, obj/item/held)
	return !!boots

/obj/item/rig/proc/select_module_chosen(datum/act/request/A)
	if(!A.answer)
		return
	apply_select_module_answer(A)
	SStgui.update_uis(src)

/obj/item/rig/proc/apply_select_module_answer(datum/act/request/A)
	var/datum/prompt/choice/rig_module_selection/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	var/obj/item/rig_module/module = A.answer.value
	if(QDELETED(module))
		return
	return select_module_for(user, module)

/obj/item/rig/proc/toggle_module_chosen(datum/act/request/A)
	if(!A.answer)
		return
	apply_toggle_module_answer(A)
	SStgui.update_uis(src)

/obj/item/rig/proc/apply_toggle_module_answer(datum/act/request/A)
	var/datum/prompt/choice/rig_module_selection/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	var/obj/item/rig_module/module = A.answer.value
	if(QDELETED(module))
		return
	return toggle_module_for(user, module)

/obj/item/rig/proc/engage_module_chosen(datum/act/request/A)
	if(!A.answer)
		return
	apply_engage_module_answer(A)
	SStgui.update_uis(src)

/obj/item/rig/proc/apply_engage_module_answer(datum/act/request/A)
	var/datum/prompt/choice/rig_module_selection/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	var/obj/item/rig_module/module = A.answer.value
	if(QDELETED(module))
		return
	return engage_module_for(user, module)

/datum/prompt/choice/rig_module_selection
	timeout = 0
	var/original_client_ckey

/datum/prompt/choice/rig_module_selection/recheck_extra()
	. = ..()
	if(.)
		return
	if(original_client_ckey && !GLOB.directory[original_client_ckey])
		return "gone"
	if(!isnull(value))
		var/obj/item/rig_module/module = value
		if(!istype(module) || QDELETED(module))
			return "gone"
	return null
