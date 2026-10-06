/obj/item/modular_computer/proc/pred_computer_has_drive(mob/actor, atom/target, obj/item/held)
	return !!portable_drive

/obj/item/modular_computer/proc/pred_computer_has_card_slot(mob/actor, atom/target, obj/item/held)
	return !!card_slot

/// Requirement: a living, able, non-animal user (simple mobs can't work the buttons). Reach is the verb's own clause.
/obj/item/modular_computer/proc/pred_computer_hands_on(mob/actor, atom/target, obj/item/held)
	if(!isliving(actor) || isanimal(actor) || actor.incapacitated())
		return "you can't do that"
	return TRUE

/// Old verb "Forced Shutdown": to be used when something bugs out and the UI is nonfunctional.
/obj/item/modular_computer/proc/computer_emergency_shutdown(mob/user, obj/item/held, datum/interaction/interaction)
	if(enabled)
		bsod = 1
		update_icon()
		shutdown_computer()
		to_chat(user, "You press a hard-reset button on \the [src]. It displays a brief debug screen before shutting down.")
		after(src, 2 SECONDS, PROC_REF(clear_bsod))

/// Old verb "Eject ID": eject the ID card from the computer, if it has an ID slot with a card inside.
/obj/item/modular_computer/proc/computer_verb_eject_id(mob/user, obj/item/held, datum/interaction/interaction)
	proc_eject_id(user)

/// Old verb "Eject Portable Storage".
/obj/item/modular_computer/proc/computer_verb_eject_usb(mob/user, obj/item/held, datum/interaction/interaction)
	proc_eject_usb(user)

/obj/item/modular_computer/proc/proc_eject_id(mob/user)
	if(!user)
		return

	if(!card_slot)
		to_chat(user, "\The [src] does not have an ID card slot")
		return

	if(!card_slot.stored_card())
		to_chat(user, "There is no card in \the [src]")
		return

	broadcast_event(COMPUTER_EVENT_IDREMOVED)

	card_slot.stored_card().forceMove(get_turf(src))
	rel_clear(card_slot, nameof(card_slot.stored_card))
	update_uis()
	to_chat(user, "You remove the card from \the [src]")


/obj/item/modular_computer/proc/proc_eject_usb(mob/user)
	if(!user)
		return

	if(!portable_drive)
		to_chat(user, "There is no portable device connected to \the [src].")
		return

	uninstall_component(user, portable_drive)
	update_uis()

/// Old attack_ghost: view the screen; staff may turn a powered-off computer on. Never fell through.
/obj/item/modular_computer/proc/modular_computer_ghost_view(mob/observer/dead/user, obj/item/held, datum/interaction/interaction)
	if(enabled)
		tgui_interact(user)
	else if(check_rights_for(user.client, R_ADMIN|R_EVENT|R_DEBUG))
		var/response = rerun_ask(user, "k98", PROC_REF(modular_computer_ghost_view), args, /datum/om/prompt/choice/alert, message = "This computer is turned off. Would you like to turn it on?", title = "Admin Override", choices = list("Yes", "No"))
		if(isnull(response))
			return TRUE
		if(response == "Yes")
			turn_on(user)
	return TRUE

/// Old attack_ai: use it as in hand.
/obj/item/modular_computer/proc/modular_computer_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	attack_self(user)
	return TRUE

DECLARE_INTERACTIONS(/obj/item/modular_computer, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_SILICON("Use", PROC_REF(modular_computer_silicon_use)), \
	INTERACT_OBSERVER("View", PROC_REF(modular_computer_ghost_view)), \
	INTERACT_VERB("Forced Shutdown", PROC_REF(computer_emergency_shutdown), REQ_TARGET_STATE(/obj/item/modular_computer/proc/pred_computer_hands_on)), \
	INTERACT_VERB("Eject ID", PROC_REF(computer_verb_eject_id), REQ_ON(PRED_TARGET, /obj/item/modular_computer/proc/pred_computer_has_card_slot, null), REQ_TARGET_STATE(/obj/item/modular_computer/proc/pred_computer_hands_on)), \
	INTERACT_VERB("Eject Portable Storage", PROC_REF(computer_verb_eject_usb), REQ_ON(PRED_TARGET, /obj/item/modular_computer/proc/pred_computer_has_drive, null), REQ_TARGET_STATE(/obj/item/modular_computer/proc/pred_computer_hands_on)), \
)

/// Old attack_hand.
/obj/item/modular_computer/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(anchored || ispAI(user))
		return attack_self(user)
	return FALSE

// On-click handling. Turns on the computer if it's off and opens the GUI.
/// Old attack_self.
/obj/item/modular_computer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(enabled && screen_on)
		if(isliving(user) && has_trait(user, TRAIT_UNLUCKY) && prob(5))
			var/mob/living/unlucky_soul = user
			to_chat(user, span_danger("You interact with \the [src] and are met with a sudden shock!"))
			fx_sparks(src, 5)
			unlucky_soul.electrocute_act(5, src, 1)
			return TRUE
		tgui_interact(user)
	else if(!enabled && screen_on)
		if(has_trait(user, TRAIT_UNLUCKY) && prob(25))
			to_chat(user, "You try to turn on \the [src] but it doesn't respond.")
			return TRUE
		turn_on(user)
	return TRUE

/// Old attackby.
/obj/item/modular_computer/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/card/id)) // ID Card, try to insert it.
		var/obj/item/card/id/I = W
		if(!card_slot)
			to_chat(user, "You try to insert \the [I] into \the [src], but it does not have an ID card slot installed.")
			return INTERACTION_HANDLED_PASS

		if(card_slot.stored_card())
			to_chat(user, "You try to insert \the [I] into \the [src], but it's ID card slot is occupied.")
			return INTERACTION_HANDLED_PASS
		user.drop_from_inventory(I)
		rel_set(card_slot, nameof(card_slot.stored_card), I)
		I.forceMove(src)
		update_uis()
		to_chat(user, "You insert \the [I] into \the [src].")
		return INTERACTION_HANDLED_PASS
	if(istype(W, /obj/item/paper) || istype(W, /obj/item/paper_bundle))
		if(!nano_printer)
			return INTERACTION_HANDLED_PASS
		nano_printer.attackby(W, user)
	if(istype(W, /obj/item/computer_hardware))
		var/obj/item/computer_hardware/C = W
		if(C.hardware_size <= max_hardware_size)
			try_install_component(user, C)
		else
			to_chat(user, "This component is too large for \the [src].")
	return FALSE

/obj/item/modular_computer/wrench_act(mob/user, obj/item/tool)
	var/list/components = get_all_components()
	if(length(components))
		to_chat(user, "Remove all components from \the [src] before disassembling it.")
		return ITEM_INTERACT_BLOCKING
	act_message(src, user, others = "%U% has been disassembled by %T%.")
	replace_with(src, /obj/item/stack/material/steel, steel_sheet_cost)
	return ITEM_INTERACT_SUCCESS

/obj/item/modular_computer/welder_act(mob/user, obj/item/tool)
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.isOn())
		to_chat(user, "\The [tool] is off.")
		return ITEM_INTERACT_BLOCKING
	var/missing = get_integrity_damage()
	if(!missing)
		to_chat(user, "\The [src] does not require repairs.")
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You begin repairing damage to \the [src]...")
	if(!welder.remove_fuel(round(missing / 75)))
		return ITEM_INTERACT_BLOCKING
	task_timed(user, missing / 10, src, src, PROC_REF(weld_repair_done), list(user))
	return ITEM_INTERACT_SUCCESS

/obj/item/modular_computer/proc/weld_repair_done(mob/user)
	repair_damage(max_integrity)
	to_chat(user, "You repair \the [src].")

/obj/item/modular_computer/screwdriver_act(mob/user, obj/item/tool)
	var/list/all_components = get_all_components()
	if(!length(all_components))
		to_chat(user, "This device doesn't have any components installed.")
		return ITEM_INTERACT_BLOCKING
	var/list/component_names = list()
	for(var/obj/item/computer_hardware/hardware in all_components)
		component_names += hardware.name
	var/choice = rerun_ask(user, "k196", TYPE_PROC_REF(/atom, screwdriver_act), args, /datum/om/prompt/choice, message = "Which component do you want to uninstall?", title = "Computer maintenance", choices = component_names)
	if(isnull(choice))
		return ITEM_INTERACT_BLOCKING
	if(!choice || !Adjacent(user))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/computer_hardware/hardware = find_hardware_by_name(choice)
	if(!hardware)
		return ITEM_INTERACT_BLOCKING
	uninstall_component(user, hardware)
	return ITEM_INTERACT_SUCCESS

/obj/item/modular_computer/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	if(!card_slot?.stored_card()?.dna_hash || !user.master_dna)
		return FALSE
	if(card_slot.stored_card().dna_hash != user.master_dna)
		return FALSE
	return proximity_flag

/obj/item/modular_computer/proc/clear_bsod()
	bsod = 0
	update_icon()
