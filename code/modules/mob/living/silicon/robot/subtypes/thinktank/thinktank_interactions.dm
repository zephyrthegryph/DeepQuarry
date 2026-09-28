EXTEND_INTERACTIONS(/mob/living/silicon/robot/platform, \
	INTERACT_ITEM(null, PROC_REF(platform_interaction_item)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(platform_interaction_hand)), \
	INTERACT_DRAG("Load into cargo", PROC_REF(platform_interaction_drag)))

/// Old attack_hand: pop out the recharging item or cargo; otherwise the cyborg touch follows.
/mob/living/silicon/robot/platform/proc/platform_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!opened)
		if(recharging)
			var/obj/item/recharging_atom = om_resolve(recharging)
			if(istype(recharging_atom) && !QDELETED(recharging_atom) && recharging_atom.loc == src)
				recharging_atom.dropInto(loc)
				user.put_in_hands(recharging_atom)
				user.visible_message(span_infoplain(span_bold("\The [user]") + " pops \the [recharging_atom] out of \the [src]'s recharging port."))
			recharging = null
			return TRUE

		if(try_remove_cargo(user))
			return TRUE

	return FALSE

/// Old attackby: a cell goes in the recharging port; a floor painter repaints; else the cyborg handling.
/mob/living/silicon/robot/platform/proc/platform_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/cell) && !opened)
		if(recharging)
			to_chat(user, span_warning("\The [src] already has \a [om_resolve(recharging)] inserted into its recharging port."))
		else if(user.unEquip(W))
			W.forceMove(src)
			recharging = om_handle(W)
			recharge_complete = FALSE
			user.visible_message(span_infoplain(span_bold("\The [user]") + " slots \the [W] into \the [src]'s recharging port."))
		return TRUE

	// Old code returned FALSE here so the painter's afterattack called try_paint(); a used-up input
	// skips afterattack now, so paint directly.
	if(istype(W, /obj/item/floor_painter))
		try_paint(W, user)
		return TRUE

	return FALSE

/mob/living/silicon/robot/platform/attack_ghost(mob/observer/dead/user)

	if(client || key || stat == DEAD || !SSticker || !SSticker.mode)
		return ..()

	om_prompt(src, user, list("message" = "Do you wish to take control of \the [src]?", "title" = "Platform Control", "choices" = list("No", "Yes")), PROC_REF(ghost_control_answered))

/mob/living/silicon/robot/platform/proc/ghost_control_answered(mob/observer/dead/user, confirm, datum/om/prompt/ask)
	if(confirm != "Yes" || !isobserver(user) || client || key || stat == DEAD || !SSticker || !SSticker.mode)
		return

	if(jobban_isbanned(user, "Robot"))
		to_chat(user, span_warning("You are banned from synthetic roles and cannot take control of \the [src]."))
		return

	// Boilerplate from drone fabs, unsure if there's a shared proc to use instead.
	var/deathtime = world.time - user.timeofdeath
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
		return
	// End boilerplate.

	if(user.mind)
		user.mind.transfer_to(src)
	if(key != user.key)
		key = user.key
	SetName("[modtype] [braintype]-[rand(100,999)]")
	om_after(src, 1, PROC_REF(welcome_client))
	qdel(user)

/mob/living/silicon/robot/platform/proc/welcome_client()
	if(client)
		to_chat(src, span_notice(span_bold("You are a think-tank") + ", a kind of flexible and adaptive drone intelligence installed into an armoured platform. Your programming compels you to be friendly and helpful wherever possible."))
	status_set(EFFECT_SLEEPING, 0)
	status_set(EFFECT_WEAKENED, 0)
	status_set(EFFECT_PARALYZED, 0)
	resting = FALSE
