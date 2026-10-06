
// Special AI/pAI PDAs that cannot explode.
/obj/item/pda/ai
	icon_state = "NONE"
	ttone = "data"
	detonate = FALSE
	touch_silent = TRUE
	programs = list(
		new/datum/data/pda/app/main_menu,
		new/datum/data/pda/app/notekeeper,
		new/datum/data/pda/app/news,
		new/datum/data/pda/app/messenger,
		new/datum/data/pda/app/game_launcher)
	special_handling = TRUE

/obj/item/pda/ai/proc/set_name_and_job(newname as text, newjob as text, newrank as null|text)
	owner = newname
	ownjob = newjob
	if(newrank)
		ownrank = newrank
	else
		ownrank = ownjob
	name = newname + " (" + ownjob + ")"

//AI verb and proc for sending PDA messages.
/obj/item/pda/ai/verb/cmd_pda_open_ui()
	set category = VERB_CAT_ABILITIES_AI
	set name = "Use PDA"
	set src in usr

	if(!can_use(usr))
		return
	tgui_interact(usr)

/obj/item/pda/ai/can_use()
	return 1

/obj/item/pda/ai/tgui_static_data(mob/user)
	. = ..()
	if(isrobot(loc))
		var/mob/living/silicon/robot/robot_owner = loc
		.["theme"] = robot_owner.get_ui_theme()

CAPABILITIES(/obj/item/pda/ai)
	op("ai_pda_self", in_hand(), then(PROC_REF(ai_pda_self)))

/// Old attack_self: only the clown virus honk.
/obj/item/pda/ai/proc/ai_pda_self(datum/act/op/A)
	if ((honkamt > 0) && (prob(60)))//For clown virus.
		honkamt--
		play_sfx(src, SFX_ITEMS_BIKEHORN, 0.6)


/obj/item/pda/ai/pai
	ttone = "assist"
	var/our_owner = null // Ref to a pAI

// ALLOW(init/INSTANCE_STATE): our_owner taken from where this instance is placed
/obj/item/pda/ai/pai/Initialize(mapload)
	. = ..()
	if(ispAI(loc))
		our_owner = REF(loc)

/obj/item/pda/ai/pai/tgui_status(mob/living/silicon/pai/user, datum/tgui_state/state)
	if(!istype(user) || REF(user) != our_owner) // Only allow our pAI to interface with us
		return STATUS_CLOSE
	return ..()

/obj/item/pda/ai/shell
	spam_proof = TRUE // Since empty shells get a functional PDA.
