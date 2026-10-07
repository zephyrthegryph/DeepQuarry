CAPABILITIES(/mob/living/silicon/robot/platform)
	op("platform_item", item(/obj/item), then(PROC_REF(platform_interaction_item)))
	op("platform_hand", hand(), ungated(), then(PROC_REF(platform_interaction_hand)))
	op("platform_take_control", observer(), label("Take control"), when(req(PROC_REF(ghost_control_possible))), asks(/datum/prompt/yes_no, fields = list("title" = "Platform Control", "question" = computed(PROC_REF(ghost_control_question)), "timeout" = 0), step = "take", keeps = TARGET_PRESENT), then(PROC_REF(ghost_control_answered)))
	op("platform_drag", item(/atom/movable), gesture(GESTURE_DRAG), label("Load into cargo"), then(PROC_REF(platform_interaction_drag)))
	op("platform_silicon_unload", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Unload cargo"), then(PROC_REF(platform_silicon_unload)))

/// Old attack_ghost: an unoccupied platform offers itself to the ghost; otherwise the default. The question is the op's asks() step; the requirement is read
/// again when the answer arrives (still a ghost, the platform still empty and alive, the round running).
/mob/living/silicon/robot/platform/proc/ghost_control_possible(datum/act/op/A)
	return read_once(!(client || key || stat == DEAD || !SSticker || !SSticker.mode)) // whether anyone is in it is asked when the click is made

/mob/living/silicon/robot/platform/proc/ghost_control_question(datum/act/A)
	return "Do you wish to take control of 	he [src]?"

/// Old attack_hand: pop out the recharging item or cargo; otherwise the cyborg touch follows.
/mob/living/silicon/robot/platform/proc/platform_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!opened)
		if(recharging)
			var/obj/item/recharging_atom = recharging
			rel_clear(src, nameof(recharging))
			if(!QDELETED(recharging_atom) && recharging_atom.loc == src)
				recharging_atom.dropInto(loc)
				user.put_in_hands(recharging_atom)
				act_message(user, src, others = span_infoplain(span_bold("%U%") + " pops %I% out of %T%'s recharging port."), item = recharging_atom)
			return OP_OK

		if(try_remove_cargo(user))
			return OP_OK

	return OP_DECLINE

/// Old attackby: a cell goes in the recharging port; a floor painter repaints; else the cyborg handling.
/mob/living/silicon/robot/platform/proc/platform_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/cell) && !opened)
		if(recharging)
			to_chat(user, span_warning("\The [src] already has \a [recharging] inserted into its recharging port."))
		else if(user.unEquip(W))
			W.forceMove(src)
			rel_set(src, nameof(recharging), W)
			recharge_complete = FALSE
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " slots %I% into %T%'s recharging port."), item = W)
		return OP_OK

	// Old code returned FALSE here so the painter's afterattack called try_paint(); a used-up input
	// skips afterattack now, so paint directly.
	if(istype(W, /obj/item/floor_painter))
		try_paint(W, user)
		return OP_OK

	return OP_DECLINE

/// A ghost takes a platform (the answer was yes).
/mob/living/silicon/robot/platform/proc/ghost_control_answered(datum/act/op/A)
	if(!A.step_value("take"))
		return OP_OK
	var/mob/observer/dead/user = A.actor
	if(!istype(user))
		return OP_OK

	if(jobban_isbanned(user, "Robot"))
		to_chat(user, span_warning("You are banned from synthetic roles and cannot take control of \the [src]."))
		return OP_OK

	// Boilerplate from drone fabs, unsure if there's a shared proc to use instead.
	var/deathtime = ELAPSED(user, timeofdeath, CLOCK_WORLD)
	var/deathtimeminutes = round(deathtime / (1 MINUTE))
	var/pluralcheck = ""
	if(deathtimeminutes == 1)
		pluralcheck = "minute"
	else if(deathtimeminutes > 0)
		pluralcheck = " [deathtimeminutes] minute\s and"
	var/deathtimeseconds = round((deathtime - deathtimeminutes * 1 MINUTE) / 10,1)
	if (deathtime < platform_respawn_time)
		to_chat(user, "You have been dead for[pluralcheck] [deathtimeseconds] seconds.")
		to_chat(user, "You must wait [platform_respawn_time/600] minute\s to take control of \the [src]!")
		return OP_OK
	// End boilerplate.

	if(user.mind)
		user.mind.transfer_to(src)
	if(key != user.key)
		key = user.key
	SetName("[modtype] [braintype]-[rand(100,999)]")
	after(src, 0.1 SECONDS, PROC_REF(welcome_client))
	spent(user)
	return OP_OK

/mob/living/silicon/robot/platform/proc/welcome_client()
	if(client)
		to_chat(src, span_notice(span_bold("You are a think-tank") + ", a kind of flexible and adaptive drone intelligence installed into an armoured platform. Your programming compels you to be friendly and helpful wherever possible."))
	status_set(STAT_SLEEPING, 0)
	status_set(STAT_WEAKENED, 0)
	status_set(STAT_PARALYZED, 0)
	set_resting(FALSE)
