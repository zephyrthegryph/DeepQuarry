/obj/machinery/computer/aifixer
	name = "\improper AI system integrity restorer"
	desc = "Used with intelliCards containing nonfunctional AIs to restore them to working order."
	req_one_access = list(ACCESS_ROBOTICS, ACCESS_HEADS)
	circuit = /obj/item/circuitboard/aifixer
	icon_keyboard = "tech_key"
	icon_screen = "ai-fixer"
	light_color = LIGHT_COLOR_PINK

	active_power_usage = 1000

	/// Variable containing transferred AI
	var/mob/living/silicon/ai/occupier
	/// Variable dictating if we are in the process of restoring the occupier AI
	var/restoring = FALSE

/obj/machinery/computer/aifixer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/aifixer_card,
		/datum/interaction/machine_hand/ungated/aifixer_use,
	)
	..()

/// Old attackby's aicard branch. Always falls through to ..() afterwards (base attackby still runs).
/datum/interaction/machine_item/aifixer_card
	id = "aifixer_card"
	name = "Use AI card"
	held_type = /obj/item/aicard
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/computer/aifixer/proc/can_use_card, null))
	effect = /obj/machinery/computer/aifixer/proc/interaction_use_card

/obj/machinery/computer/aifixer/proc/can_use_card(mob/actor, atom/target, obj/item/held)
	if(stat & (NOPOWER|BROKEN))
		return "this terminal isn't functioning right now"
	if(restoring)
		return "terminal is busy restoring [occupier] right now"
	return TRUE

/obj/machinery/computer/aifixer/proc/interaction_use_card(mob/user, obj/item/aicard/card, datum/interaction/interaction)
	if(occupier)
		if(card.grab_ai(occupier, user))
			occupier = null
	else if(card.carded_ai)
		var/mob/living/silicon/ai/new_occupant = card.carded_ai
		to_chat(new_occupant, span_notice("You have been transferred into a stationary terminal. Sadly there is no remote access from here."))
		to_chat(user, span_notice("Transfer Successful:") + " [new_occupant] placed within stationary terminal.")
		new_occupant.forceMove(src)
		new_occupant.cancel_camera()
		new_occupant.control_disabled = TRUE
		occupier = new_occupant
		card.clear()
		update_icon()
	else
		to_chat(user, span_notice("There is no AI loaded onto this computer, and no AI loaded onto [card]. What exactly are you trying to do here?"))
	// Old code always fell through to ..() after handling the card; decline so the base attackby still runs.
	return FALSE

/obj/machinery/computer/aifixer/screwdriver_act(mob/user, obj/item/tool)
	if(!occupier)
		return ..()
	if(stat & (NOPOWER|BROKEN))
		to_chat(user, span_warning("The screws on [name]'s screen won't budge."))
	else
		to_chat(user, span_warning("The screws on [name]'s screen won't budge and it emits a warning beep."))
	return ITEM_INTERACT_BLOCKING

/// Old attack_hand (never called ..()): opens the UI, silently doing nothing when unpowered/broken.
/datum/interaction/machine_hand/ungated/aifixer_use
	id = "aifixer_use"
	name = "Use"
	effect = /obj/machinery/computer/aifixer/proc/interaction_use

/obj/machinery/computer/aifixer/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat & (NOPOWER|BROKEN))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/aifixer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AiRestorer", name)
		ui.open()

/obj/machinery/computer/aifixer/tgui_data(mob/user)
	var/list/data = list()

	data["ejectable"] = FALSE
	data["AI_present"] = FALSE
	data["error"] = null
	if(!occupier)
		data["error"] = "Please transfer an AI unit."
	else
		data["AI_present"] = TRUE
		data["name"] = occupier.name
		data["restoring"] = restoring
		data["health"] = occupier.hardware_integrity()
		data["isDead"] = occupier.stat == DEAD
		var/list/laws = list()
		for(var/datum/ai_law/law in occupier.laws.all_laws())
			laws += "[law.get_index()]: [law.law]"
		data["laws"] = laws

	return data

/obj/machinery/computer/aifixer/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE
	if(!occupier)
		restoring = FALSE

	if(action)
		playsound(src, "terminal_type", 50, 1)

	switch(action)
		if("PRG_beginReconstruction")
			if(occupier && (occupier.vitality() < 1 || occupier.backup_capacitor() < 100))
				to_chat(ui.user, span_notice("Reconstruction in progress. This will take several minutes."))
				playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 25, FALSE)
				restoring = TRUE
				START_MACHINE_PROCESSING(src)
				var/mob/observer/dead/ghost = occupier.get_ghost()
				if(ghost)
					ghost.notify_revive("Your core files are being restored!", source = src)
				. = TRUE

/obj/machinery/computer/aifixer/proc/Fix()
	use_power(active_power_usage)
	occupier.adjust_backup_charge(5)
	occupier.mend(TREAT_SYSTEM_RESTORE, 5)
	occupier.mend(TREAT_WIRING_REPAIR, 5)
	occupier.mend(TREAT_PLATING_REPAIR, 5)
	// Old threshold: hardware integrity back above 50%.
	if(occupier.vitality() >= 0.5 && occupier.stat == DEAD)
		occupier.revive()

	return occupier.vitality() < 1 || occupier.backup_capacitor() < 100

/obj/machinery/computer/aifixer/process()
	if(!restoring || !occupier)
		return PROCESS_KILL
	if(stat & (NOPOWER|BROKEN))
		return
	var/oldstat = occupier.stat
	restoring = Fix()
	if(oldstat != occupier.stat)
		update_icon()
	if(!restoring)
		return PROCESS_KILL

/obj/machinery/computer/aifixer/update_icon()
	. = ..()
	if(stat & (NOPOWER|BROKEN))
		return

	if(restoring)
		. += "ai-fixer-on"
	if (occupier)
		switch (occupier.stat)
			if (CONSCIOUS)
				. += "ai-fixer-full"
			if (UNCONSCIOUS)
				. += "ai-fixer-404"
	else
		. += "ai-fixer-empty"
