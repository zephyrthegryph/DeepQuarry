/mob/living/simple_mob //makes it so that any simplemob can potentially be revived by players and joined by ghosts
	var/ghostjoin = FALSE
	var/ic_revivable = FALSE
	var/revivedby = "no one"

REGISTRY_MEMBERSHIP(/mob/living, REGISTRY_GHOST_PODS)

/mob/living/simple_mob/vv_edit_var(var_name, var_value)
	switch(var_name)
		if(NAMEOF(src, ghostjoin))
			if(ghostjoin == var_value)
				return

			if(var_value)
				set_ghostjoin(TRUE)
				registry_join(REGISTRY_GHOST_PODS, src)
			else
				set_ghostjoin(FALSE)
				registry_leave(REGISTRY_GHOST_PODS, src)

			. =  TRUE

	if(!isnull(.))
		datum_flags |= DF_VAR_EDITED
		return

	. = ..()


//The stuff we want to be revivable normally
/mob/living/simple_mob/animal
	ic_revivable = TRUE
/mob/living/simple_mob/vore/otie
	ic_revivable = TRUE
/mob/living/simple_mob/vore
	ic_revivable = TRUE
//The stuff that would be revivable but that we don't want to be revivable
/mob/living/simple_mob/animal/giant_spider/nurse //no you can't revive the ones who can lay eggs and get webs everywhere
	ic_revivable = FALSE
/mob/living/simple_mob/animal/giant_spider/carrier //or the ones who fart babies when they die
	ic_revivable = FALSE

TRACKED(/mob/living/simple_mob, ghostjoin)

/// Requirement: this ghost may inhabit us (not banned, nobody in us yet, preferences that allow a captured mob).
/mob/living/simple_mob/proc/can_ghost_join(datum/act/op/A)
	return isnull(ghost_join_refusal(src, A.actor))

/mob/living/simple_mob/proc/ghost_join_reason(datum/act/op/A)
	return ghost_join_refusal(src, A.actor)

/// Why the ghost `D` may not take `M` over, or null.
/proc/ghost_join_refusal(mob/living/simple_mob/M, mob/observer/dead/D)
	READS_FROM() // bans, a player's presence and preferences are asked when the ghost clicks
	if(jobban_isbanned(D, JOB_GHOSTROLES))
		return "You cannot inhabit this creature because you are banned from playing ghost roles."
	if(M.ckey)
		return "Sorry, someone else has already inhabited [M]."
	if(M.capture_caught && !D.client?.prefs?.read_preference(/datum/preference/toggle/human/capture_crystal))
		return "Sorry, [M] is participating in capture mechanics, and your preferences do not allow for that."
	return null

/mob/living/simple_mob/proc/ghost_join_question(datum/act/A)
	return "Would you like to become [src]? It is bound to [revivedby]."

/// Old attack_ghost: a ghost said yes to becoming us (re-checked on the answer).
/mob/living/simple_mob/proc/reply_ghost_join(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/mob/observer/dead/user = A.actor
	if(!R?.value)
		return OP_OK
	if(!ghostjoin || !user?.client || ghost_join_refusal(src, user))
		return OP_OK
	if(evaluate_ghost_join(user))
		ghost_join(user)
	return OP_OK

/// Inject a ghost into this mob. Assumes you've done all sanity before this point.
/mob/living/simple_mob/proc/ghost_join(mob/observer/dead/D)
	log_and_message_admins("joined [src] as a ghost [ADMIN_FLW(src)]", D)
	registry_leave(REGISTRY_GHOST_PODS, src)

	// Move the ghost in
	if(D.mind)
		D.mind.active = TRUE
		D.mind.transfer_to(src)
	else
		src.ckey = D.ckey
	spent(D)

	// Clean up the simplemob
	set_ghostjoin(FALSE)
	if(capture_caught)
		to_chat(src, span_notice("You are bound to [revivedby], follow their commands within reason and to the best of your abilities, and avoid betraying or abandoning them.") + " " + span_warning("You are allied with [revivedby]. Do not attack anyone for no reason. Of course, you may do scenes as you like, but you must still respect preferences."))
		act_message(src, null, others = "%U%'s eyes flicker with a curious intelligence.", runemessage = "looks around")
		return
	if(revivedby != "no one")
		to_chat(src, span_notice("Where once your life had been rough and scary, you have been assisted by [revivedby]. They seem to be the reason you are on your feet again... so perhaps you should help them out.") + " " + span_warning("Being as you were revived, you are allied with the station. Do not attack anyone unless they are threatening the one who revived you. And try to listen to the one who revived you within reason. Of course, you may do scenes as you like, but you must still respect preferences."))
		act_message(src, null, others = "%U%'s eyes flicker with a curious intelligence.", runemessage = "looks around")

/// Evaluate someone for being allowed to join as this mob from being a ghost
/mob/living/simple_mob/proc/evaluate_ghost_join(mob/observer/dead/D)
	if(!istype(D) || !D.client)
		stack_trace("A non-ghost mob was evaluated for joining into a simplemob...")
		return FALSE

	// At this point we can at least send them messages as to why they can't join, since they are a mob with a client
	if(!ghostjoin)
		to_chat(D, span_notice("Sorry, [src] is no longer ghost-joinable."))
		return FALSE

	if(ckey)
		to_chat(D, span_notice("Sorry, someone else has already inhabited [src]."))
		return FALSE

	if(capture_caught && !D.client.prefs.read_preference(/datum/preference/toggle/human/capture_crystal)) // migrated pref
		to_chat(D, span_notice("Sorry, [src] is participating in capture mechanics, and your preferences do not allow for that."))
		return FALSE

	// Insert whatever ban checks you want here if we ever add simplemob bans

	return TRUE

/obj/item/denecrotizer //Away map reward. FOR TRAINED NECROMANCERS ONLY. >:C
	name = "experimental denecrotizer"
	desc = "It looks simple on the outside but this device radiates some unknown dread. It does not appear to be of any ordinary make, and just how it works is unclear, but this device seems to interact with dead flesh."
	icon = 'icons/obj/device.dmi'
	icon_state = "denecrotizer"
	w_class = ITEMSIZE_COST_NORMAL
	var/charges = 5 //your army of minions can only be this big
	EXPIRY_DECLARE(last_used)
	var/cooldown = 10 MINUTES //LONG
	var/revive_time = 30 SECONDS //Don't do this in combat
	var/advanced = 1 //allows for ghosts to join mobs who get revived by this, and updates their faction to yours

/obj/item/denecrotizer/examine(mob/user)
	. = ..()
	var/cooldowntime = round((cooldown - (world.time - last_used)) * 0.1)
	if(Adjacent(user))
		if(cooldowntime <= 0)
			. += span_notice("The screen indicates that this device is ready to be used, and that it has enough energy for [charges] uses.")
		else
			. += span_notice("The screen indicates that this device can be used again in [cooldowntime] seconds, and that it has enough energy for [charges] uses.")

/obj/item/denecrotizer/proc/check_target(mob/living/simple_mob/target, mob/living/user, stance = I_HURT)
	if(!target.Adjacent(user))
		return FALSE
	if(stance != I_HELP) //be gentle
		act_message(user, target, others = "%U% bonks %T% with [src].", runemessage = "bonks [target]")
		return FALSE
	if(!istype(target))
		to_chat(user, span_notice("[target] seems to be too complicated for [src] to interface with."))
		return FALSE
	if(!(ELAPSED(src, last_used, CLOCK_WORLD) > cooldown))
		to_chat(user, span_notice("[src] doesn't seem to be ready yet."))
		return FALSE
	if(!charges)
		to_chat(user, span_notice("[src] doesn't seem to be active anymore."))
		return FALSE
	if(!target.ic_revivable)
		to_chat(user, span_notice("[src] doesn't seem to interface with [target]."))
		return FALSE
	if(target.stat != DEAD)
		if(!advanced)
			to_chat(user, span_notice("[src] doesn't seem to work on that."))
			return FALSE
		//legacy `.retaliate` is dead in the modern brain (every brain
		// mob retaliates on damage automatically). Only refuse to revive
		// aggro-on-sight mobs. Null-safe on ai_brain since mobs without a
		// brain (e.g. opted-out subtypes) are by definition not aggressive.
		if(target.ai_brain?.hostile)
			to_chat(user, span_notice("[src] doesn't seem to work on that."))
			return FALSE
		if(!target.mind)
			act_message(user, target, others = "%U% gently presses [src] to %T%...", runemessage = "presses [src] to [target]")
			task_timed(user, revive_time, target = target, receiver = src, on_done = PROC_REF(check_target_timed_done), done_args = list(target, user))
			return FALSE
		else
			to_chat(user, span_notice("[src] doesn't seem to work on that."))
			return FALSE
	return TRUE

/obj/item/denecrotizer/proc/check_target_timed_done(mob/living/simple_mob/target, mob/living/user)
	target.faction = user.faction
	target.revivedby = user.name
	target.set_ghostjoin(1)
	registry_join(REGISTRY_GHOST_PODS, target)
	EXPIRY_STAMP(src, last_used, CLOCK_WORLD)
	charges--
	log_and_message_admins("used a denecrotizer to tame/offer a simplemob to ghosts: [target]. [ADMIN_FLW(src)]", user)
	act_message(target, user, others = "%U%'s eyes widen, as though in revelation as it looks at %T%.", runemessage = "eyes widen")
	if(charges == 0)
		icon_state = "[initial(icon_state)]-o"

/obj/item/denecrotizer/proc/ghostjoin_rez(mob/living/simple_mob/target, mob/living/user)
	act_message(user, target, others = "%U% gently presses [src] to %T%...", runemessage = "presses [src] to [target]")
	task_timed(user, revive_time, target = target, receiver = src, on_done = PROC_REF(ghostjoin_rez_timed_done), done_args = list(target, user))
	return

/obj/item/denecrotizer/proc/ghostjoin_rez_timed_done(mob/living/simple_mob/target, mob/living/user)
	target.faction = user.faction
	target.revivedby = user.name
	target.revive()
	target.update_icon()
	act_message(target, user, others = "%U% lifts its head and looks at %T%.", runemessage = "lifts its head and looks at [user]")
	log_and_message_admins("used a denecrotizer to revive a simple mob: [target]. [ADMIN_FLW(src)]", user)
	if(!target.mind) //if it doesn't have a mind then no one has been playing as it, and it is safe to offer to ghosts.
		target.set_ghostjoin(1)
		registry_join(REGISTRY_GHOST_PODS, target)
	EXPIRY_STAMP(src, last_used, CLOCK_WORLD)
	charges--
	if(charges == 0)
		icon_state = "[initial(icon_state)]-o"
	return

/obj/item/denecrotizer/proc/basic_rez(mob/living/simple_mob/target, mob/living/user) //so medical can have a way to bring back people's pets or whatever, does not change any settings about the mob or offer it to ghosts.
	act_message(user, target, others = "%U% presses [src] to %T%...", runemessage = "presses [src] to [target]")
	task_start(/datum/task/timed/denecrotizer_basic_rez, user, target, receiver = src, duration = revive_time)

/datum/task/timed/denecrotizer_basic_rez
	complete_proc = /obj/item/denecrotizer/proc/basic_rez_timed_done
	cancel_proc = /obj/item/denecrotizer/proc/basic_rez_timed_failed

/obj/item/denecrotizer/proc/basic_rez_timed_done(datum/task/timed/denecrotizer_basic_rez/task)
	var/mob/living/simple_mob/target = task.target
	var/mob/living/user = task.actor
	target.revive()
	target.update_icon()
	act_message(target, user, others = "%U% lifts its head and looks at %T%.", runemessage = "lifts its head and looks at [user]")
	EXPIRY_STAMP(src, last_used, CLOCK_WORLD)
	charges--
	if(charges == 0)
		icon_state = "[initial(icon_state)]-o"
	return

/obj/item/denecrotizer/proc/basic_rez_timed_failed(datum/task/timed/denecrotizer_basic_rez/task)
	var/mob/living/simple_mob/target = task.target
	var/mob/living/user = task.actor
	act_message(user, src, others = "%U% bonks [target] with %T%. Nothing happened.")
	return

/obj/item/denecrotizer/attack(mob/living/target, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(check_target(target, user, stance))
		if(advanced)
			ghostjoin_rez(target, user)
		else
			basic_rez(target, user)
		return ITEM_INTERACT_SUCCESS
	else
		return ..()

/obj/item/denecrotizer/medical //Can revive more things, but without the special ghost and faction stuff. For medical use.
	name = "commercial denecrotizer"
	desc = "A curious device who's purpose is reviving simpler life forms. It seems to radiate menace."
	icon_state = "m-denecrotizer"
	advanced = 0 //This one isn't as fancy
	cooldown = 5 MINUTES //not as long
	charges = 20 //in case spiders merc Ian
