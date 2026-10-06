/obj/item/aicard
	name = "intelliCore"
	desc = "Used to preserve and transport an AI."
	icon = 'icons/obj/pda.dmi'
	icon_state = "aicard" // aicard-full
	item_state = "aicard"
	w_class = ITEMSIZE_NORMAL
	slot_flags = SLOT_BELT
	show_messages = 0
	preserve_item = 1

	var/flush = null

	var/mob/living/silicon/ai/carded_ai

/obj/item/aicard/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/silicon/decoy))
		return ..()
	else
		var/mob/living/silicon/decoy/decoy = M
		decoy.death()
		to_chat(user, span_infoplain(span_bold("ERROR ERROR ERROR")))
		return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/aicard)
	op("view_ai", in_hand(), opens_ui())
	interface("AICard", state = nameof(GLOB.tgui_inventory_state))
	without("ui_open")
	op("wipe", ui_act("wipe"), then(PROC_REF(ui_act_wipe)))
	op("radio", ui_act("radio"), then(PROC_REF(ui_act_radio)))
	op("wireless", ui_act("wireless"), then(PROC_REF(ui_act_wireless)))

/// /obj/item/aicard's window data.
/obj/item/aicard/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["has_ai"] = carded_ai() != null
	if(carded_ai())
		data["name"] = carded_ai().name
		data["integrity"] = carded_ai().hardware_integrity()
		data["backup_capacitor"] = carded_ai().backup_capacitor()
		data["radio"] = !carded_ai().aiRadio.disabledAi
		data["wireless"] = !carded_ai().control_disabled
		data["operational"] = carded_ai().stat != DEAD
		data["flushing"] = flush

		var/list/laws = list()
		for(var/datum/ai_law/law in carded_ai().laws.all_laws())
			if(law in carded_ai().laws.ion_laws) // If we're an ion law, give it an ion index code
				laws.Add(ionnum() + ". " + law.law)
			else
				laws.Add(num2text(law.get_index()) + ". " + law.law)
		data["laws"] = laws
		data["has_laws"] = length(carded_ai().laws.all_laws())

	return data

/obj/item/aicard/proc/ui_gate(datum/act/op/A)
	if(!carded_ai())
		return FALSE
	return TRUE

/obj/item/aicard/proc/ui_act_wipe(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	msg_admin_attack("[key_name_admin(user)] wiped [key_name_admin(AI_DEPT)] with \the [src].")
	add_attack_logs(user,carded_ai(),"Purged from AI Card")
	wipe_ai()
	return TRUE

/obj/item/aicard/proc/ui_act_radio(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	carded_ai().aiRadio.disabledAi = !carded_ai().aiRadio.disabledAi
	to_chat(carded_ai(), span_warning("Your Subspace Transceiver has been [carded_ai().aiRadio.disabledAi ? "disabled" : "enabled"]!"))
	to_chat(user, span_notice("You [carded_ai().aiRadio.disabledAi ? "disable" : "enable"] the AI's Subspace Transceiver."))
	return TRUE

/obj/item/aicard/proc/ui_act_wireless(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	carded_ai().control_disabled = !carded_ai().control_disabled
	to_chat(carded_ai(), span_warning("Your wireless interface has been [carded_ai().control_disabled ? "disabled" : "enabled"]!"))
	to_chat(user, span_notice("You [carded_ai().control_disabled ? "disable" : "enable"] the AI's wireless interface."))
	if(carded_ai().control_disabled && carded_ai().deployed_shell)
		carded_ai().disconnect_shell("Disconnecting from remote shell due to [src] wireless access interface being disabled.")
	update_icon()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/item/aicard, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/aicard/appearance_overlays()
	. = list()
	if(carded_ai())
		if (!carded_ai().control_disabled)
			. += "aicard-on"
		if(carded_ai().stat)
			icon_state = "aicard-404"
		else
			icon_state = "aicard-full"
	else
		icon_state = "aicard"

/obj/item/aicard/proc/grab_ai(mob/living/silicon/ai/ai, mob/living/user)
	if(!ai.client && !ai.deployed_shell)
		to_chat(user, span_danger("ERROR:") + " AI [ai.name] is offline. Unable to transfer.")
		return 0

	if(carded_ai())
		to_chat(user, span_danger("Transfer failed:") + " Existing AI found on remote device. Remove existing AI to install a new one.")
		return 0

	if(!user.IsAdvancedToolUser() && isanimal(user))
		var/mob/living/simple_mob/S = user
		if(!S.IsHumanoidToolUser(src))
			return 0

	act_message(user, src, MSG_SELF("You start transferring \the [ai] into %T%..."), MSG_OTHERS("%U% starts transferring \the [ai] into %T%..."))
	show_message(span_critical("\The [user] is transferring you into \the [src]!"))

	om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(grab_ai_timed_done), done_args = list(ai, user))
	return 1

/obj/item/aicard/proc/grab_ai_timed_done(mob/living/silicon/ai/ai, mob/living/user)
	if(carded_ai())
		to_chat(user, span_danger("Transfer failed:") + " Existing AI found on remote device. Remove existing AI to install a new one.")
		return 0
	if(istype(ai.loc, /turf/))
		new /obj/structure/AIcore/deactivated(get_turf(ai))

	ai.carded = 1
	add_attack_logs(user,ai,"Extracted into AI Card")
	src.name = "[initial(name)] - [ai.name]"

	ai.forceMove(src)
	ai.destroy_eyeobj(src)
	ai.cancel_camera()
	ai.control_disabled = 1
	ai.aiRestorePowerRoutine = 0
	rel_set(src, nameof(carded_ai), ai)
	ai.disconnect_shell("Disconnected from remote shell due to core intelligence transfer.") //If the AI is controlling a borg, force the player back to core!

	if(ai.client)
		to_chat(ai, span_infoplain("You have been transferred into a mobile core. Remote access lost."))
	if(user.client)
		to_chat(ai, span_notice(span_bold("Transfer successful:")) + " [ai.name] extracted from current device and placed within mobile core.")

	ai.canmove = 1
	update_icon()

/obj/item/aicard/proc/clear()
	if(carded_ai() && istype(carded_ai().loc, /turf))
		carded_ai().canmove = 0
		carded_ai().carded = 0
	name = initial(name)
	rel_clear(src, nameof(carded_ai))
	update_icon()

/obj/item/aicard/see_emote(mob/living/M, text)
	if(carded_ai() && carded_ai().client)
		var/rendered = span_message("[text]")
		carded_ai().show_message(rendered, 2)
	..()

/obj/item/aicard/show_message(msg, type, alt, alt_type)
	if(carded_ai() && carded_ai().client)
		var/rendered = span_message("[msg]")
		carded_ai().show_message(rendered, type)
	..()

/obj/item/aicard/relaymove(mob/user, direction)
	if(user.stat || user.has_status(EFFECT_STUNNED))
		return
	var/obj/item/rig/rig = src.get_rig()
	if(istype(rig))
		rig.forced_move(direction, user)

/obj/item/aicard/proc/wipe_ai()
	var/mob/living/silicon/ai/our_ai = carded_ai()
	flush = TRUE
	our_ai.suiciding = TRUE
	to_chat(our_ai, "Your power has been disabled!")
	wipe_ai_tick(our_ai, 0)

/// Once a second while the carded AI dies: the shell link fails more and more.
/obj/item/aicard/proc/wipe_ai_tick(mob/living/silicon/ai/our_ai, power_lost)
	if(QDELETED(our_ai) || our_ai.stat == DEAD)
		flush = FALSE
		return
	// This is absolutely evil and I love it.
	if(our_ai.deployed_shell && prob(power_lost)) //You feel it creeping? Eventually will reach 100, resulting in the second half of the AI's remaining life being lonely.
		our_ai.disconnect_shell("Disconnecting from remote shell due to insufficent power.")
	if(!after(src, 1 SECOND, PROC_REF(wipe_ai_tick), with = list(our_ai, power_lost + 2)))
		flush = FALSE

/// Relation view: carded ai (reads null once it is gone).
/obj/item/aicard/proc/carded_ai() as /mob/living/silicon/ai
	return carded_ai
