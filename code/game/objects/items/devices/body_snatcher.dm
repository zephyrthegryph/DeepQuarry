//Body snatcher. Based off the sleevemate, but instead of storing a mind it lets you swap your mind with someone. Extremely illegal and being caught with one s
/obj/item/bodysnatcher
	name = "\improper Body Snatcher Device"
	desc = "An extremely illegal tool that allows the user to swap minds with the selected humanoid victim. The LED panel on the side states 'Place both heads on the device, pull trigger, then wait for the transfer to complete.'"
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "sleevemate" //Give this a fancier sprite later.
	item_state = "healthanalyzer"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 200)
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'
	flags = NOBLUDGEON

/// Re-checked on the answer: the device is still in hand, and the victim is next to the user and alive.
/datum/om/prompt/confirm/bodysnatch
	title = "Confirmation"
	message = "This will swap your mind with the target's mind. This will result in them controlling your body, and you controlling their body. Continue?"
	yes_text = "Continue"
	no_text = "Cancel"
	requires = PROMPT_IN_HAND
	var/mob/living/victim

/datum/om/prompt/confirm/bodysnatch/valid()
	if(!answerer.Adjacent(victim) || victim.stat == DEAD)
		return "no longer a target"
	return null

/obj/item/bodysnatcher/proc/swap_confirmed(datum/om/prompt/confirm/bodysnatch/ask)
	var/mob/living/user = ask.answerer
	var/mob/living/M = ask.victim
	if(M.ckey && !M.client)
		log_and_message_admins("attempted to body swap with [key_name(M)] while they were SSD!")
	else
		log_and_message_admins("attempted to body swap with [key_name(M)].")
	user.visible_message(span_warning("[user] pushes the device up their forehead and [M]'s head, the device beginning to let out a series of light beeps!"),span_notice("You begin swap minds with [M]!"))
	om_task_timed(user, 35 SECONDS, target = M, receiver = src, on_done = PROC_REF(attack_timed_done), done_args = list(M, user))

/obj/item/bodysnatcher/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(ishuman(M) || issilicon(M)) //Allows body swapping with humans, synths, and pAI's/borgs since they all have a mind.
		if(user == M)
			to_chat(user,span_warning("A message pops up on the LED display, informing you that the mind transfer to yourself was successful... Wait, did that even do anything?"))
			return ITEM_INTERACT_FAILURE

		if(!M.mind) //Do they have a mind?
			to_chat(user,span_warning("A warning pops up on the device, informing you that [M] appears braindead."))
			return ITEM_INTERACT_FAILURE

		if(!M.allow_mind_transfer)
			to_chat(user,span_danger("The target's mind is too complex to be affected!"))
			return ITEM_INTERACT_FAILURE

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.resleeve_lock && user.ckey != H.resleeve_lock)
				to_chat(src, span_danger("[H] cannot be impersonated!"))
				return ITEM_INTERACT_FAILURE

		if(M.stat == DEAD) //Are they dead?
			to_chat(user,span_warning("A warning pops up on the device, informing you that [M] is dead, and, as such, the mind transfer can not be done."))
			return ITEM_INTERACT_FAILURE

		om_ask(user, /datum/om/prompt/confirm/bodysnatch, PROC_REF(swap_confirmed), victim = M)
		return ITEM_INTERACT_BLOCKING

	else
		to_chat(user,span_warning(" A warning pops up on the LED display on the side of the device, informing you that the target is not able to have their mind swapped with!"))
		return ITEM_INTERACT_FAILURE

/obj/item/bodysnatcher/proc/attack_timed_done(mob/living/M, mob/living/user)
	if(user.mind && M.mind && M.stat != DEAD && user.stat != DEAD)
		log_and_message_admins("[user.ckey] used a Bodysnatcher to swap bodies with [M.ckey]", user)
		to_chat(user,span_notice("Your minds have been swapped! Have a nice day."))
		var/datum/mind/user_mind = user.mind
		var/datum/mind/prey_mind = M.mind
		M.ghostize()
		user.ghostize()
		rel_clear(user, "mind")
		rel_clear(M, "mind")
		rel_clear(user_mind, "current")
		rel_clear(prey_mind, "current")
		user_mind.active = TRUE //If they are 'active', their client is automatically pushed to the mob
		transfer_mind(user_mind, M, "bodysnatcher swap") // The identity (OOC notes and all) follows each mind.
		prey_mind.active = TRUE
		transfer_mind(prey_mind, user, "bodysnatcher swap")
		if(M.tf_mob_holder == user)
			M.set_tf_mob_holder(null)
		else
			M.set_tf_mob_holder(user)
		if(user.tf_mob_holder == M)
			user.set_tf_mob_holder(null)
		else
			user.set_tf_mob_holder(M)
		user.status_set(EFFECT_SLEEPING, 10) //Device knocks out both the user and the target.
		user.status_set(EFFECT_BLURRY, 30) //Blurry vision while they both get used to their new body's vision
		user.status_set(EFFECT_SLURRING, 50) //And let's also have them slurring while they attempt to get used to using their new body.
		if(ishuman(M)) //Let's not have the AI slurring, even though its downright hilarious.
			M.status_set(EFFECT_SLEEPING, 10)
			M.status_set(EFFECT_BLURRY, 30)
			M.status_set(EFFECT_SLURRING, 50)
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

DECLARE_INTERACTIONS(/obj/item/bodysnatcher, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/bodysnatcher/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user,span_warning(" A message pops up on the LED display, informing you that you that the mind transfer to yourself was successful... Wait, did that even do anything?"))
	return TRUE
