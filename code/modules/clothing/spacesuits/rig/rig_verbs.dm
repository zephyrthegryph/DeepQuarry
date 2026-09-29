// Interface for humans. The Menu entries are declared with the rest of the rig's interactions (rig_attackby.dm).

/// Old verb "Open Hardsuit Interface".
/obj/item/rig/proc/rig_hardsuit_interface_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(wearer() && (wearer().get_equipped_item(SLOT_ID_BACK) == src || wearer().get_equipped_item(SLOT_ID_BELT) == src))
		tgui_interact(user)

// So the UI button clicks come here
/obj/item/rig/ui_action_click(mob/user, actiontype)
	if(user == wearer() && (wearer().get_equipped_item(SLOT_ID_BACK) == src || wearer().get_equipped_item(SLOT_ID_BELT) == src))
		tgui_interact(user)

/// Old verb "Toggle Visor".
/obj/item/rig/proc/rig_toggle_vision_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_power_cost(user))
		return

	if(canremove)
		to_chat(user, span_warning("The suit is not active."))
		return

	if(!check_suit_access(user))
		return

	if(!visor)
		to_chat(user, span_warning("The hardsuit does not have a configurable visor."))
		return

	if(!visor.active)
		visor.activate()
	else
		visor.deactivate()

/// Old verb "Toggle Helmet" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_helmet_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_suit_access(user))
		return

	toggle_piece("helmet",wearer())

/// Old verb "Toggle Chestpiece" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_chest_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!check_suit_access(user))
		return

	toggle_piece("chest",wearer())

/// Old verb "Toggle Gauntlets" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_gauntlets_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_suit_access(user))
		return

	toggle_piece("gauntlets",wearer())

/// Old verb "Toggle Boots" (offered while the suit has that piece).
/obj/item/rig/proc/rig_toggle_boots_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_suit_access(user))
		return

	toggle_piece("boots",wearer())

/// Old verb "Deploy Hardsuit".
/obj/item/rig/proc/rig_deploy_suit_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_suit_access(user))
		return

	if(!check_power_cost(user))
		return

	deploy(wearer())

/// Old verb "Toggle Hardsuit".
/obj/item/rig/proc/rig_toggle_seals_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_suit_access(user))
		return

	toggle_seals(wearer())

/// Old verb "Switch Vision Mode".
/obj/item/rig/proc/rig_switch_vision_mode_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	if(canremove)
		to_chat(user, span_warning("The suit is not active."))
		return

	if(!visor)
		to_chat(user, span_warning("The hardsuit does not have a configurable visor."))
		return

	if(!visor.active)
		visor.activate()

	if(!visor.active)
		to_chat(user, span_warning("The visor is suffering a hardware fault and cannot be configured."))
		return

	visor.engage()

/// Old verb "Configure Voice Synthesiser".
/obj/item/rig/proc/rig_alter_voice_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(malfunction_check(user))
		return

	if(canremove)
		to_chat(user, span_warning("The suit is not active."))
		return

	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!speech)
		to_chat(user, span_warning("The hardsuit does not have a speech synthesiser."))
		return

	speech.engage()

/// Old verb "Select Module".
/obj/item/rig/proc/rig_select_module_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	if(canremove)
		to_chat(user, span_warning("The suit is not active."))
		return

	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	var/list/selectable = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.selectable)
			selectable |= module

	var/obj/item/rig_module/module = rerun_ask(user, "a1", PROC_REF(rig_select_module_verb), list(user), /datum/om/prompt/choice, message = "Which module do you wish to select?", title = "Select Module", choices = selectable)
	if(isnull(module))
		return

	if(!istype(module))
		own_take(src, "selected_module")
		to_chat(user, span_boldnotice("Primary system is now: deselected."))
		return

	own_set(src, "selected_module", module)
	to_chat(user, span_boldnotice("Primary system is now: [selected_module.interface_name]."))

/// Old verb "Toggle Module".
/obj/item/rig/proc/rig_toggle_module_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(malfunction_check(user))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	if(canremove)
		to_chat(user, span_warning("The suit is not active."))
		return

	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	var/list/selectable = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.toggleable)
			selectable |= module

	var/obj/item/rig_module/module = rerun_ask(user, "a2", PROC_REF(rig_toggle_module_verb), list(user), /datum/om/prompt/choice, message = "Which module do you wish to toggle?", title = "Toggle Module", choices = selectable)
	if(isnull(module))
		return

	if(!istype(module))
		return

	if(module.active)
		to_chat(user, span_boldnotice("You attempt to deactivate \the [module.interface_name]."))
		module.deactivate()
	else
		to_chat(user, span_boldnotice("You attempt to activate \the [module.interface_name]."))
		module.activate()

/// Old verb "Engage Module".
/obj/item/rig/proc/rig_engage_module_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(malfunction_check(user))
		return

	if(canremove)
		to_chat(user, span_warning("The suit is not active."))
		return

	if(!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		to_chat(user, span_warning("The hardsuit is not being worn."))
		return

	if(!check_power_cost(user, 0, 0, 0, 0))
		return

	var/list/selectable = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.usable)
			selectable |= module

	var/obj/item/rig_module/module = rerun_ask(user, "a3", PROC_REF(rig_engage_module_verb), list(user), /datum/om/prompt/choice, message = "Which module do you wish to engage?", title = "Engage Module", choices = selectable)
	if(isnull(module))
		return

	if(!istype(module))
		return

	to_chat(user, span_boldnotice("You attempt to engage the [module.interface_name]."))
	module.engage()

/// Requirement: the suit has this piece (replaces adding the toggle verbs when the piece was built).
/obj/item/rig/proc/pred_has_helmet(mob/actor, atom/target, obj/item/held)
	return !!helmet

/obj/item/rig/proc/pred_has_chest(mob/actor, atom/target, obj/item/held)
	return !!chest

/obj/item/rig/proc/pred_has_gauntlets(mob/actor, atom/target, obj/item/held)
	return !!gloves

/obj/item/rig/proc/pred_has_boots(mob/actor, atom/target, obj/item/held)
	return !!boots
