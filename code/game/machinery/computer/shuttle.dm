/obj/machinery/computer/shuttle
	name = "Shuttle"
	desc = "For shuttle control."
	icon_keyboard = "tech_key"
	icon_screen = "shuttle"
	light_color = "#00ffff"
	var/auth_need = 3.0
	var/list/authorized = list(  ) // ALLOW(instance_list): d: per-console authorisation state




CAPABILITIES(/obj/machinery/computer/shuttle)
	op("shuttle_authorize", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), asks(/datum/prompt/choice/shuttle_authorization, fields = list("card" = computed(PROC_REF(shuttle_held_card)), "timeout" = 0), when = PROC_REF(shuttle_can_authorize)), then(PROC_REF(authorization_chosen)))
	op("shuttle_emag_launch", item(/obj/item/card/emag), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), asks(/datum/prompt/yes_no/shuttle_emag_launch, fields = list("card" = computed(PROC_REF(shuttle_held_card)), "timeout" = 0), when = PROC_REF(shuttle_can_emag_launch)), then(PROC_REF(emag_launch_chosen)))


/datum/prompt/choice/shuttle_authorization
	title = "Shuttle Launch"
	choices = list("Authorize", "Repeal", "Abort")
	buttons = TRUE
	var/obj/item/card/card

CAPABILITIES(/datum/prompt/choice/shuttle_authorization)
	ref_one(nameof(card), /obj/item/card)

/// The card is still in the hands of whoever was asked, who can still act.
/obj/machinery/computer/shuttle/proc/authorization_valid(datum/request/R)
	var/datum/prompt/choice/shuttle_authorization/ask = R
	var/mob/living/user = R.answerer
	return istype(user) && ask.card?.loc == user && !user.incapacitated()

/obj/machinery/computer/shuttle/proc/authorization_chosen(datum/act/op/A)
	if(!A.answer)
		var/obj/item/card/id/card = A.held_provider()
		if(operable() && SSticker && !SSemergency_shuttle.location() && istype(card) && !(ACCESS_HEADS in card.access))
			to_chat(A.actor, "The access level of [card.registered_name]\'s card is not high enough. ")
		return OP_OK
	var/datum/prompt/choice/shuttle_authorization/ask = A.answer
	var/obj/item/card/id/W = ask.card
	var/mob/user = ask.answerer
	switch(A.answer.value)
		if("Authorize")
			src.authorized -= W.registered_name
			src.authorized += W.registered_name
			if (src.auth_need - src.authorized.len > 0)
				message_admins("[key_name_admin(user)] has authorized early shuttle launch")
				log_game("[user.ckey] has authorized early shuttle launch")
				to_chat(world, span_boldnotice("Alert: [src.auth_need - src.authorized.len] authorizations needed until shuttle is launched early"))
			else
				message_admins("[key_name_admin(user)] has launched the shuttle")
				log_game("[user.ckey] has launched the shuttle early")
				to_chat(world, span_boldnotice("Alert: Shuttle launch time shortened to 10 seconds!"))
				SSemergency_shuttle.set_launch_countdown(10)
				src.authorized = list(  )

		if("Repeal")
			src.authorized -= W.registered_name
			to_chat(world, span_boldnotice("Alert: [src.auth_need - src.authorized.len] authorizations needed until shuttle is launched early"))

		if("Abort")
			to_chat(world, span_boldnotice("All authorizations to shortening time for shuttle launch have been revoked!"))
			src.authorized.len = 0
			src.authorized = list(  )

/// Launching on an emag: asked of whoever holds it.
/datum/prompt/yes_no/shuttle_emag_launch
	title = "Shuttle control"
	question = "Would you like to launch the shuttle?"
	yes_text = "Launch"
	no_text = "Cancel"
	var/obj/item/card/card

CAPABILITIES(/datum/prompt/yes_no/shuttle_emag_launch)
	ref_one(nameof(card), /obj/item/card)

/obj/machinery/computer/shuttle/proc/emag_launch_valid(datum/request/R)
	var/datum/prompt/yes_no/shuttle_emag_launch/ask = R
	var/mob/living/user = R.answerer
	return istype(user) && ask.card?.loc == user && !user.incapacitated()

/obj/machinery/computer/shuttle/proc/emag_launch_chosen(datum/act/op/A)
	if(!A.answer || !A.answer.value)
		return
	if(!emagged() && !SSemergency_shuttle.location())
		to_chat(world, span_boldnotice("Alert: Shuttle launch time shortened to 10 seconds!"))
		SSemergency_shuttle.set_launch_countdown(10)
		set_emagged(1)

/obj/machinery/computer/shuttle/proc/shuttle_held_card(datum/act/op/A)
	return A.held_provider()

/obj/machinery/computer/shuttle/proc/shuttle_can_authorize(datum/act/op/A)
	var/obj/item/card/id/card = A.held_provider()
	return operable() && SSticker && !SSemergency_shuttle.location() && A.actor && istype(card) && (ACCESS_HEADS in card.access)


/obj/machinery/computer/shuttle/proc/shuttle_can_emag_launch(datum/act/op/A)
	return operable() && SSticker && !SSemergency_shuttle.location() && A.actor && !emagged()

/datum/prompt/choice/shuttle_authorization/prepare(datum/act/A)
	..()
	var/obj/machinery/computer/shuttle/S = owner
	question = "Would you like to (un)authorize a shortened launch time? [S.auth_need - length(S.authorized)] authorization\s are still needed. Use abort to cancel all authorizations."
