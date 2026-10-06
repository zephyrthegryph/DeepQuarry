// Another illegal hack of the sleevemate similar to the Body Snatcher. This one lets you store and bind minds to items.
/obj/item/mindbinder
	name = "\improper Mind Binder"
	desc = "An extremely illegal tool modified from a SleeveMate. It allows the storing and transfer of minds, but can bind them to objects instead of just humanoids."
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "sleevemate"
	item_state = "healthanalyzer"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_STEEL, 200)
	possessed_voice = list()
	var/self_bind = FALSE
	flags = NOBLUDGEON

/obj/item/mindbinder/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	return ITEM_INTERACT_SUCCESS

/obj/item/mindbinder/proc/toggle_self_bind(mob/user)
	if(length(possessed_voice) == 1)
		to_chat(user,span_warning("The device beeps a warning that there is already a mind loaded!"))
		return
	self_bind = !self_bind
	if(self_bind)
		to_chat(user,span_notice("You prepare the device to use your own mind!"))
	else
		to_chat(user,span_notice("You disable the device from using your mind."))
	update_icon()

/obj/item/mindbinder/pre_attack(atom/A, mob/user, params)
	if(istype(A, /obj/structure/gargoyle))
		var/obj/structure/gargoyle/G = A
		A = G.WR_gargoyle
	if(istype(A, /obj/item/holder))
		var/obj/item/holder/H = A
		A = H.held_mob
	if(istype(A, /mob/living))
		var/mob/living/M = A
		if(!M.allow_mind_transfer)
			to_chat(user,span_danger("The target's mind is too complex to be affected!"))
			return
		if(user == M)
			toggle_self_bind(user)
			return
		if(length(possessed_voice) == 1 || self_bind)
			bind_mob(M, user)
		else
			store_mob(M, user)
		return
	if(istype(A, /obj/item))
		var/obj/item/I = A
		if(length(possessed_voice) == 1 || self_bind)
			bind_item(I, user)
		else
			store_item(I, user)
		return
	return

// Handle placing a mind into a mob
/// Mind binder "are you sure?"s.
/datum/prompt/choice/mindbinder
	title = "Confirmation"
	choices = list("Continue", "Cancel")
	buttons = TRUE
	timeout = 0

/// Binding yourself into the subject (a mob or an item). Re-checked on the answer: still next to it.
/datum/prompt/choice/mindbinder/self_bind
	ask_flags = ASK_ADJACENT | ASK_CAPABLE

/// ...and a mob must still be mindless.
/datum/prompt/choice/mindbinder/self_bind/mob
	question = "This will bind YOUR mind to the target! You may not be able to go back without help. Continue?"

/datum/prompt/choice/mindbinder/self_bind/mob/recheck_extra()
	var/mob/living/target = subject
	return target.ckey ? "already sentient" : null

/datum/prompt/choice/mindbinder/self_bind/item
	question = "This will bind YOUR mind to the target! You will not be able to go back without help. Continue?"

/// Downloading a mind. Re-checked on the answer: the binder is in hand and empty, the victim next to the user.
/datum/prompt/choice/mindbinder/store_mob
	question = "This will download the target's mind into the device. Once their mind is loaded you can then bind it into an item. This will result in the target being stuck until you put them back in their original body. Please make sure OOC prefs align! Continue?"
	ask_flags = ASK_HELD | ASK_CAPABLE
	var/mob/living/victim

CAPABILITIES(/datum/prompt/choice/mindbinder/store_mob)
	ref_one(nameof(victim), /mob/living)

/datum/prompt/choice/mindbinder/store_mob/prepare(datum/act/A)
	..()
	var/mob/living/captured_victim = victim
	rel_clear(src, nameof(victim))
	rel_set(src, nameof(victim), captured_victim)

/datum/prompt/choice/mindbinder/store_mob/recheck_extra()
	if(QDELETED(victim))
		return "gone"
	var/obj/item/mindbinder/binder = owner
	if(length(binder.possessed_voice) != 0 || !answerer.Adjacent(victim))
		return "can't download"
	return null

/obj/item/mindbinder/proc/self_bind_mob_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Continue")
		return
	var/datum/prompt/choice/mindbinder/self_bind/mob/ask = A.answer
	var/mob/user = ask.answerer
	var/mob/living/target = ask.subject
	act_message(user, src, MSG_SELF(span_notice("You begin to bind yourself into [target]!")), MSG_OTHERS(span_warning("%U% presses %T% against [target]. The device beginning to let out a series of beeps!")))
	log_and_message_admins("attempted to bind themselves to \an [target] with a Mind Binder.", user)
	task_timed(user, 30 SECONDS, target = target, receiver = src, on_done = PROC_REF(bind_mob_timed_done), done_args = list(target, user))

/obj/item/mindbinder/proc/self_bind_item_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Continue")
		return
	var/datum/prompt/choice/mindbinder/self_bind/item/ask = A.answer
	var/mob/user = ask.answerer
	var/obj/item/item = ask.subject
	log_and_message_admins("attempted to bind themselves to \an [item] with a Mind Binder.", user)
	act_message(user, src, MSG_SELF(span_notice("You begin to bind yourself into [item]!")), MSG_OTHERS(span_warning("%U% presses %T% against [item]. The device beginning to let out a series of beeps!")))
	task_timed(user, 30 SECONDS, target = item, receiver = src, on_done = PROC_REF(bind_item_timed_done), done_args = list(item, user))

/obj/item/mindbinder/proc/store_mob_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Continue")
		return
	var/datum/prompt/choice/mindbinder/store_mob/ask = A.answer
	var/mob/user = ask.answerer
	var/mob/living/target = ask.victim
	if(target.ckey && !target.client)
		log_and_message_admins("attempted to take [key_name(target)]'s mind with a Mind Binder while they were SSD!", user)
	else
		log_and_message_admins("attempted to take [key_name(target)]'s mind with a Mind Binder.", user)
	act_message(user, src, MSG_SELF(span_notice("You begin to download [target]'s mind!")), MSG_OTHERS(span_warning("%U% presses %T% against [target]'s head. The device beginning to let out a series of beeps!")))
	task_timed(user, 30 SECONDS, target = target, receiver = src, on_done = PROC_REF(store_mob_timed_done), done_args = list(target, user))

/obj/item/mindbinder/proc/bind_mob(mob/living/target, mob/user)
	if(length(possessed_voice) == 0 && !self_bind)
		to_chat(user,span_warning("The device beeps a warning that it doesn't contain a mind to bind!"))
		return

	if(target.ckey)
		to_chat(user,span_warning("The device beeps a warning that the target is already sentient!"))
		return

	if(self_bind)
		open_request(src, /datum/prompt/choice/mindbinder/self_bind/mob, PROC_REF(self_bind_mob_confirmed), answerer = user, subject = target)
		return

	act_message(user, src, MSG_SELF(span_notice("You begin to bind someone's mind into [target]!")), MSG_OTHERS(span_warning("%U% presses %T% against [target]. The device beginning to let out a series of beeps!")))
	log_and_message_admins("attempted to bind [key_name(src.possessed_voice[1])] to \an [target] with a Mind Binder.", user)
	var/doTime = 30 SECONDS
	if(ishuman(target) || issilicon(target) || isanimal(target))
		doTime = 5 SECONDS
	task_timed(user, doTime, target = target, receiver = src, on_done = PROC_REF(bind_mob_timed_done2), done_args = list(target, user))

	update_icon()

/obj/item/mindbinder/proc/bind_mob_timed_done(mob/living/target, mob/usr_mob)
	if(!target.ckey)
		usr_mob.mind.transfer_to(target)
	if(!target.tf_mob_holder)
		target.set_tf_mob_holder(usr_mob)
	if(target.tf_mob_holder == target)
		target.set_tf_mob_holder(null)
	self_bind = !self_bind
	update_icon()
	to_chat(usr_mob,span_notice("Your mind as been bound to [target]."))
/obj/item/mindbinder/proc/bind_mob_timed_done2(mob/living/target, mob/usr_mob)
	if(length(possessed_voice) == 1 && !target.ckey)
		var/mob/living/voice/V = possessed_voice[1]
		V.mind.transfer_to(target)
		if(!target.tf_mob_holder)
			target.set_tf_mob_holder(V.tf_mob_holder)
		if(target.tf_mob_holder == target)
			target.set_tf_mob_holder(null)
		rel_remove(src, nameof(possessed_voice), V)
		to_chat(usr_mob,span_notice("Mind bound to [target]."))

// Handle placing a mind into an item
/obj/item/mindbinder/proc/bind_item(obj/item/item, mob/user)
	if(length(possessed_voice) == 0 && !self_bind)
		to_chat(user,span_warning("The device beeps a warning that it doesn't contain a mind to bind!"))
		return

	if(item.possessed_voice && length(item.possessed_voice))
		to_chat(user,span_warning("The device beeps a warning that the target is already sentient!"))
		return

	if(is_type_in_list(item, GLOB.item_vore_blacklist))
		to_chat(user,span_danger("The item resists your transfer attempt!"))
		return

	if(self_bind)
		open_request(src, /datum/prompt/choice/mindbinder/self_bind/item, PROC_REF(self_bind_item_confirmed), answerer = user, subject = item)
		return

	log_and_message_admins("attempted to bind [key_name(src.possessed_voice[1])] to \an [item] with a Mind Binder.", user)
	act_message(user, src, MSG_SELF(span_notice("You begin to bind someone's mind into [item]!")), MSG_OTHERS(span_warning("%U% presses %T% against [item]. The device beginning to let out a series of beeps!")))
	task_timed(user, 5 SECONDS, target = item, receiver = src, on_done = PROC_REF(bind_item_timed_done2), done_args = list(item, user))

	update_icon()

/obj/item/mindbinder/proc/bind_item_timed_done(obj/item/item, mob/usr_mob)
	item.inhabit_item(usr_mob, null, usr_mob, TRUE)
	self_bind = !self_bind
	update_icon()
	to_chat(usr_mob,span_notice("Your mind as been bound to [item]."))
/obj/item/mindbinder/proc/bind_item_timed_done2(obj/item/item, mob/usr_mob)
	if(length(possessed_voice) == 1)
		var/mob/living/voice/V = possessed_voice[1]
		item.inhabit_item(V, null, V.tf_mob_holder, TRUE)
		rel_remove(src, nameof(possessed_voice), V)
		to_chat(usr_mob,span_notice("Mind bound to [item]."))

// Handle taking a mind out of a mob
/obj/item/mindbinder/proc/store_mob(mob/living/target, mob/user)
	if(length(possessed_voice) != 0)
		to_chat(user,span_warning("The device beeps a warning that there is already a mind loaded!"))
		return

	if(!target.mind || (target.mind.name in GLOB.prevent_respawns))
		to_chat(user,span_warning("The device beeps a warning that the target isn't sentient."))
		return

	open_request(src, /datum/prompt/choice/mindbinder/store_mob, PROC_REF(store_mob_confirmed), answerer = user, victim = target)

	update_icon()

/obj/item/mindbinder/proc/store_mob_timed_done(mob/living/target, mob/usr_mob)
	if(length(possessed_voice) == 0 && target.mind)
		inhabit_item(target, target.real_name, target)
		to_chat(usr_mob,span_notice("Mind successfully stored!"))

// Handle taking a mind out of an item
/obj/item/mindbinder/proc/store_item(obj/item/item, mob/user)
	if(length(possessed_voice) != 0)
		to_chat(user,span_warning("The device beeps a warning that there is already a mind loaded!"))
		return

	if(!(item.possessed_voice && length(item.possessed_voice)))
		return

	var/mob/living/voice/target = item.possessed_voice[1]

	log_and_message_admins("attempted to take [key_name(target)]'s mind out of \an [item] with a Mind Binder.", user)
	act_message(user, src, MSG_SELF(span_notice("You begin to download someone's mind from [item]!")), MSG_OTHERS(span_warning("%U% presses %T% against [item]. The device beginning to let out a series of beeps!")))
	task_start(/datum/task/timed/mindbinder_store_item, user, item, receiver = src, target_arg = target)

	update_icon()

/datum/task/timed/mindbinder_store_item
	duration = 5 SECONDS
	complete_proc = /obj/item/mindbinder/proc/store_item_timed_done
	var/mob/living/voice/target_arg

/obj/item/mindbinder/proc/store_item_timed_done(datum/task/timed/mindbinder_store_item/task)
	var/obj/item/item = task.target
	var/mob/living/voice/target = task.target_arg
	var/mob/usr_mob = task.actor
	if(length(possessed_voice) == 0 && item.possessed_voice.Find(target))
		inhabit_item(target, target.real_name, target.tf_mob_holder)
		rel_remove(item, nameof(item.possessed_voice), target)
		to_chat(usr_mob,span_notice("Mind successfully stored!"))

/obj/item/mindbinder/proc/appearance_bound()
	return ((possessed_voice && length(possessed_voice) > 0) || self_bind) ? TRUE : FALSE

APPEARANCE_TEMPLATE(/obj/item/mindbinder, "{initial(icon_state)}{appearance_bound?_on:}")
