/obj/item/modular_computer/proc/pred_computer_has_drive(datum/act/op/A)
	return !!portable_drive

/obj/item/modular_computer/proc/pred_computer_has_card_slot(datum/act/op/A)
	return !!card_slot

/// Requirement: a living, able, non-animal user (simple mobs can't work the buttons). Reach is the verb's own clause.
/obj/item/modular_computer/proc/pred_computer_hands_on(datum/act/op/A)
	var/mob/actor = A.actor
	return isliving(actor) && !isanimal(actor) && !actor.incapacitated()

/// Why pred_computer_hands_on refuses.
/obj/item/modular_computer/proc/pred_computer_hands_on_refusal(datum/act/op/A)
	return "you can't do that"

/// Old verb "Forced Shutdown": to be used when something bugs out and the UI is nonfunctional.
/obj/item/modular_computer/proc/computer_emergency_shutdown(datum/act/op/A)
	var/mob/user = A.actor
	if(enabled)
		set_bsod(TRUE)
		shutdown_computer()
		to_chat(user, "You press a hard-reset button on \the [src]. It displays a brief debug screen before shutting down.")
		after(src, 2 SECONDS, PROC_REF(clear_bsod))

/// Old verb "Eject ID": eject the ID card from the computer, if it has an ID slot with a card inside.
/obj/item/modular_computer/proc/computer_verb_eject_id(datum/act/op/A)
	proc_eject_id(A.actor)

/// Old verb "Eject Portable Storage".
/obj/item/modular_computer/proc/computer_verb_eject_usb(datum/act/op/A)
	proc_eject_usb(A.actor)

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
/obj/item/modular_computer/proc/modular_computer_ghost_view(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_OK

/// Old attack_ghost: staff turn a powered-off computer on if they say so.
/obj/item/modular_computer/proc/modular_computer_ghost_power(datum/act/op/A)
	if(A.step_value("k98") == "Yes")
		turn_on(A.actor)
	return OP_OK

/// Old attack_ai: use it as in hand.
/obj/item/modular_computer/proc/modular_computer_silicon_use(datum/act/op/A)
	attack_self(A.actor)
	return OP_OK

/// Old attack_hand.
/obj/item/modular_computer/proc/interaction_hand(datum/act/op/A)
	return attack_self(A.actor) ? OP_OK : OP_DECLINE

// On-click handling. Turns on the computer if it's off and opens the GUI.
/// Old attack_self.
/obj/item/modular_computer/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(enabled && screen_on)
		if(isliving(user) && has_trait(user, TRAIT_UNLUCKY) && prob(5))
			var/mob/living/unlucky_soul = user
			to_chat(user, span_danger("You interact with \the [src] and are met with a sudden shock!"))
			fx_sparks(src, 5)
			unlucky_soul.electrocute_act(5, src, 1)
			return OP_OK
		tgui_interact(user)
	else if(!enabled && screen_on)
		if(has_trait(user, TRAIT_UNLUCKY) && prob(25))
			to_chat(user, "You try to turn on \the [src] but it doesn't respond.")
			return OP_OK
		turn_on(user)
	return OP_OK

/// Old attackby.
/obj/item/modular_computer/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/card/id)) // ID Card, try to insert it.
		var/obj/item/card/id/I = W
		if(!card_slot)
			to_chat(user, "You try to insert \the [I] into \the [src], but it does not have an ID card slot installed.")
			return OP_PASS

		if(card_slot.stored_card())
			to_chat(user, "You try to insert \the [I] into \the [src], but it's ID card slot is occupied.")
			return OP_PASS
		user.drop_from_inventory(I)
		rel_set(card_slot, nameof(card_slot.stored_card), I)
		I.forceMove(src)
		update_uis()
		to_chat(user, "You insert \the [I] into \the [src].")
		return OP_PASS
	if(istype(W, /obj/item/paper) || istype(W, /obj/item/paper_bundle))
		if(!nano_printer)
			return OP_PASS
		nano_printer.attackby(W, user)
	if(istype(W, /obj/item/computer_hardware))
		var/obj/item/computer_hardware/C = W
		if(C.hardware_size <= max_hardware_size)
			try_install_component(user, C)
		else
			to_chat(user, "This component is too large for \the [src].")
	return OP_DECLINE

/obj/item/modular_computer/wrench_act(mob/user, obj/item/tool)
	var/list/components = get_all_components()
	if(length(components))
		to_chat(user, "Remove all components from \the [src] before disassembling it.")
		return ITEM_INTERACT_BLOCKING
	act_message(src, user, others = "%U% has been disassembled by %T%.")
	replace_with(src, /obj/item/stack/material/steel, steel_sheet_cost)
	return ITEM_INTERACT_SUCCESS

MSG_DEF_SELF(modular_computer/no_repairs, "%T% does not require repairs.")
MSG_DEF_SELF(modular_computer/welding, "You begin repairing damage to %T%...")
MSG_DEF_SELF(modular_computer/welded, "You repair %T%.")

/obj/item/modular_computer/proc/needs_repair(datum/act/op/A)
	return get_integrity_damage() > 0

/// A weld takes a second for every ten points of damage, and a unit of fuel for every 75, both read when it starts.
/obj/item/modular_computer/proc/weld_time(datum/act/op/A)
	return get_integrity_damage() / 10

/obj/item/modular_computer/proc/weld_fuel(datum/act/op/A)
	return round(get_integrity_damage() / 75)

/obj/item/modular_computer/proc/weld_repair_done(datum/act/op/A)
	repair_damage(max_integrity)

/obj/item/modular_computer/screwdriver_act(mob/user, obj/item/tool)
	var/list/all_components = get_all_components()
	if(!length(all_components))
		to_chat(user, "This device doesn't have any components installed.")
		return ITEM_INTERACT_BLOCKING
	var/list/component_names = list()
	for(var/obj/item/computer_hardware/hardware in all_components)
		component_names += hardware.name
	var/choice = rerun_ask(user, "k196", TYPE_PROC_REF(/atom, screwdriver_act), args, /datum/prompt/choice, question = "Which component do you want to uninstall?", title = "Computer maintenance", choices = component_names)
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
	set_bsod(FALSE)
