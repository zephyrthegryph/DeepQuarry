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
OM_FIELD(/obj/machinery/computer/aifixer, restoring, FALSE, CHANGE_MACHINE_SETTINGS)
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
	if(!operable())
		return "this terminal isn't functioning right now"
	if(restoring)
		return "terminal is busy restoring [occupier()] right now"
	return TRUE

/obj/machinery/computer/aifixer/proc/interaction_use_card(mob/user, obj/item/aicard/card, datum/interaction/interaction)
	if(occupier())
		if(card.grab_ai(occupier(), user))
			rel_clear(src, nameof(occupier))
	else if(card.carded_ai())
		var/mob/living/silicon/ai/new_occupant = card.carded_ai()
		to_chat(new_occupant, span_notice("You have been transferred into a stationary terminal. Sadly there is no remote access from here."))
		to_chat(user, span_notice("Transfer Successful:") + " [new_occupant] placed within stationary terminal.")
		new_occupant.forceMove(src)
		new_occupant.cancel_camera()
		new_occupant.control_disabled = TRUE
		rel_set(src, nameof(occupier), new_occupant)
		card.clear()
		update_icon()
	else
		to_chat(user, span_notice("There is no AI loaded onto this computer, and no AI loaded onto [card]. What exactly are you trying to do here?"))
	// Old code always fell through to ..() after handling the card; decline so the base attackby still runs.
	return FALSE

MSG_DEF_SELF(aifixer/screws_stuck, "The screws on the screen won't budge.")
MSG_DEF_SELF(aifixer/screws_stuck_beep, "The screws on the screen won't budge and it emits a warning beep.")

/// needs: no AI is loaded (its screws won't budge while one is).
/obj/machinery/computer/aifixer/proc/no_ai_loaded(datum/act/op/A)
	return !occupier()

/obj/machinery/computer/aifixer/proc/screws_stuck_reason(datum/act/op/A)
	return operable() ? /datum/msg/aifixer/screws_stuck_beep : /datum/msg/aifixer/screws_stuck

/// Old attack_hand (never called ..()): opens the UI, silently doing nothing when unpowered/broken.
/datum/interaction/machine_hand/ungated/aifixer_use
	id = "aifixer_use"
	name = "Use"
	effect = /obj/machinery/computer/aifixer/proc/interaction_use

/obj/machinery/computer/aifixer/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/aifixer)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(restoring), wakes_on = list(nameof(restoring)))
	extend("disconnect", needs(req(PROC_REF(no_ai_loaded), because = PROC_REF(screws_stuck_reason))))
	interface("AiRestorer")
	op("PRG_beginReconstruction", ui_act("PRG_beginReconstruction"), then(PROC_REF(ui_act_prg_beginreconstruction)))
	extend(TAG_UI, then(PROC_REF(ui_typed), early = TRUE))

/obj/machinery/computer/aifixer/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["ejectable"] = FALSE
	data["AI_present"] = FALSE
	data["error"] = null
	if(!occupier())
		data["error"] = "Please transfer an AI unit."
	else
		data["AI_present"] = TRUE
		data["name"] = occupier().name
		data["restoring"] = restoring
		data["health"] = occupier().hardware_integrity()
		data["isDead"] = occupier().stat == DEAD
		var/list/laws = list()
		for(var/datum/ai_law/law in occupier().laws.all_laws())
			laws += "[law.get_index()]: [law.law]"
		data["laws"] = laws

	return data

/// Every button clicks, and restoring stops when nobody is in the terminal (the old window guard's side effects).
/obj/machinery/computer/aifixer/proc/ui_typed(datum/act/op/A)
	if(!occupier())
		set_restoring(FALSE)
	play_sfx(src, SFX_TERMINAL_TYPE)
	return OP_OK

/obj/machinery/computer/aifixer/proc/ui_act_prg_beginreconstruction(datum/act/op/A)
	if(occupier() && (occupier().vitality() < 1 || occupier().backup_capacitor() < 100))
		to_chat(A.actor, span_notice("Reconstruction in progress. This will take several minutes."))
		play_sfx(src, SFX_MACHINES_TERMINAL_PROMPT_CONFIRM)
		set_restoring(TRUE)
		var/mob/observer/dead/ghost = occupier().get_ghost()
		if(ghost)
			ghost.notify_revive("Your core files are being restored!", source = src)
		. = TRUE

/obj/machinery/computer/aifixer/proc/Fix()
	use_power(active_power_usage)
	occupier().adjust_backup_charge(5)
	occupier().mend(TREAT_SYSTEM_RESTORE, 5)
	occupier().mend(TREAT_WIRING_REPAIR, 5)
	occupier().mend(TREAT_PLATING_REPAIR, 5)
	// Old threshold: hardware integrity back above 50%.
	if(occupier().vitality() >= 0.5 && occupier().stat == DEAD)
		occupier().revive()

	return occupier().vitality() < 1 || occupier().backup_capacitor() < 100

/obj/machinery/computer/aifixer/proc/work_step(datum/act/timer/A)
	if(!occupier())
		set_restoring(FALSE)
		return
	if(!operable())
		return
	var/oldstat = occupier().stat
	set_restoring(Fix())
	if(oldstat != occupier().stat)
		update_icon()

/// Over the console's screen: restoring, and the state of the AI card's occupant (none, awake, or out).
/obj/machinery/computer/aifixer/draw(datum/look/look)
	..()
	if(!operable())
		return
	look.overlay("ai-fixer-on", when = restoring)
	var/mob/living/silicon/ai/AI = occupier()
	var/ai_stat = AI?.stat
	if(!AI)
		look.overlay("ai-fixer-empty")
	else if(ai_stat == CONSCIOUS)
		look.overlay("ai-fixer-full")
	else if(ai_stat == UNCONSCIOUS)
		look.overlay("ai-fixer-404")

/// occupier (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/aifixer/proc/occupier() as /mob/living/silicon/ai
	return occupier // ALLOW(reads): the loaded AI is asked when it is needed, never cached
