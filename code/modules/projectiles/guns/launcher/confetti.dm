//The confetti cannon is a simple weapon meant to be a toy. You shoot confetti at people and it makes a funny sound. Don't give this any combat use.
/obj/item/gun/launcher/confetti_cannon
	name = "confetti cannon"
	desc = "For those times when you absolutely need colored paper everywhere."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "confetti_cannon"
	item_state = "confetti_cannon"
	w_class = ITEMSIZE_NORMAL
	throw_distance = 7
	release_force = 5
	var/obj/item/chambered = null // a party ball, banana peel or pie

	var/confetti_charge = 0
	var/max_confetti = 20
	special_handling = TRUE

CAPABILITIES(/obj/item/gun/launcher/confetti_cannon)
	owns_one(nameof(chambered), /obj/item)

/obj/item/gun/launcher/confetti_cannon/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += span_blue("It's loaded with [confetti_charge] ball\s of confetti.")

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/gun/launcher/confetti_cannon/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	. = OP_PASS
	if(istype(I, /obj/item/paper) || istype(I, /obj/item/shreddedp))
		if(confetti_charge < max_confetti)
			user.drop_item()
			++confetti_charge
			to_chat(user, span_blue("You put the paper in the [src]."))
			consume(I, user)
		else
			to_chat(user, span_red("[src] cannot hold more paper."))

/obj/item/gun/launcher/confetti_cannon/proc/pump(mob/user)
	play_sfx(user, SFX_WEAPONS_SHOTGUNPUMP)
	if(!chambered)
		if(confetti_charge)
			rel_set(src, nameof(chambered), new /obj/item/grenade/confetti/party_ball)
			--confetti_charge
			to_chat(user, span_blue("You compress a new confetti ball."))
		else
			to_chat(user, span_red("The [src] is out of confetti!"))
	else
		to_chat(user, span_red("The [src] is already loaded!"))

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/confetti_cannon/gun_operate(datum/act/op/A, callback)
	var/mob/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	pump(user)

/obj/item/gun/launcher/confetti_cannon/consume_next_projectile()
	var/obj/item/grenade/confetti/party_ball/ball = chambered
	if(istype(ball))
		ball.activate(null)
	return chambered

/obj/item/gun/launcher/confetti_cannon/handle_post_fire(mob/user)
	rel_take(src, nameof(chambered))

/obj/item/gun/launcher/confetti_cannon/overdrive
	name = "overdrive confetti cannon"
	desc = "For those times when you absolutely need colored paper everywhere, EVERYWHERE."
	confetti_charge = 100
	max_confetti = 100

/obj/item/gun/launcher/confetti_cannon/fake_shottie
	name = "horror movie shotgun"
	desc = "The one necessary for survival of any Final Girl."
	icon = 'icons/obj/gun2.dmi'
	icon_state = "ithaca"
	item_state = "ithaca"
	confetti_charge = 20

/obj/item/gun/launcher/confetti_cannon/robot
	name = "Party Cannon"
	desc = "Confetti, pies, banana peels, chaos!"

/obj/item/gun/launcher/confetti_cannon/robot
	name = "Party Cannon"
	desc = "Confetti, pies, banana peels, chaos!"

/obj/item/gun/launcher/confetti_cannon/robot/pump(mob/user)
	return party_payload_stage(user)

/obj/item/gun/launcher/confetti_cannon/robot/proc/party_payload_stage(mob/user, settings_answer, settings_ready = FALSE)
	play_sfx(user, SFX_WEAPONS_SHOTGUNPUMP)
	if(!chambered)
		if(!settings_ready)
			open_request(src, /datum/prompt/choice/weapon_setting_review, PROC_REF(party_payload_answered), answerer = user, settings_operator = user, question = "Load the Party Canon with?", title = "Change What?", choices = list("Confetti","Banana Peel","Cream Pie"), buttons = TRUE)
			return
		var/choice = settings_answer
		if(isnull(choice))
			return
		if(!choice)
			return
		if(istype(user,/mob/living/silicon/robot))
			var/mob/living/silicon/robot/R = user
			if(!R.draw_power(ROBOT_CELL_JOULES(200), src, ROBOT_CELL_JOULES(400)))
				to_chat(R, span_warning("Warning, low power detected. Aborting action."))
				return
		play_sfx(src, SFX_EFFECTS_POP)
		switch(choice)
			if("Confetti")
				rel_set(src, nameof(chambered), new /obj/item/grenade/confetti/party_ball)
				to_chat(user, span_blue("Confetti loaded."))
			if("Banana Peel")
				rel_set(src, nameof(chambered), new /obj/item/bananapeel)
				to_chat(user, span_blue("Banana peel loaded."))
			if("Cream Pie")
				rel_set(src, nameof(chambered), new /obj/item/reagent_containers/food/snacks/pie)
				to_chat(user, span_blue("Banana cream pie loaded."))
	else
		to_chat(user, span_red("The [src] is already loaded!"))

/obj/item/gun/launcher/confetti_cannon/robot/consume_next_projectile()
	var/obj/item/grenade/confetti/party_ball/ball = chambered
	if(istype(ball))
		ball.activate(null)
	return chambered


/obj/item/gun/launcher/confetti_cannon/robot/proc/party_payload_answered(datum/act/request/context)
	if(!context.answer)
		return
	. = party_payload_apply(context)
	SStgui.update_uis(src)

/obj/item/gun/launcher/confetti_cannon/robot/proc/party_payload_apply(datum/act/request/context)
	var/datum/prompt/choice/weapon_setting_review/ask = context.answer
	return party_payload_stage(ask.settings_operator, ask.value, TRUE)
