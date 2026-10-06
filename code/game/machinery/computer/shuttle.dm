/obj/machinery/computer/shuttle
	name = "Shuttle"
	desc = "For shuttle control."
	icon_keyboard = "tech_key"
	icon_screen = "shuttle"
	light_color = "#00ffff"
	var/auth_need = 3.0
	var/list/authorized = list(  ) // ALLOW(instance_list): d: per-console authorisation state


EXTEND_INTERACTIONS(/obj/machinery/computer/shuttle, \
	INTERACT_INSERT(/obj/item/card, PROC_REF(interaction_authorize), "Use"), \
)

/obj/machinery/computer/shuttle/proc/interaction_authorize(mob/user, obj/item/card/W, datum/interaction/interaction)
	if(!operable())
		return TRUE
	if ((!( istype(W, /obj/item/card) ) || !( SSticker ) || SSemergency_shuttle.location() || !( user )))
		return TRUE
	if (istype(W, /obj/item/card/id)||istype(W, /obj/item/pda))
		if (istype(W, /obj/item/pda))
			var/obj/item/pda/pda = W
			W = pda.id
		if (!W:access) //no access
			to_chat(user, "The access level of [W:registered_name]\'s card is not high enough. ")
			return TRUE

		var/list/cardaccess = W:access
		if(!istype(cardaccess, /list) || !cardaccess.len) //no access
			to_chat(user, "The access level of [W:registered_name]\'s card is not high enough. ")
			return TRUE

		if(!(ACCESS_HEADS in W:access)) //doesn't have this access
			to_chat(user, "The access level of [W:registered_name]\'s card is not high enough. ")
			return TRUE

		open_request(src, /datum/prompt/choice/shuttle_authorization, PROC_REF(authorization_chosen), valid = PROC_REF(authorization_valid), answerer = user, question = text("Would you like to (un)authorize a shortened launch time? [] authorization\s are still needed. Use abort to cancel all authorizations.", src.auth_need - src.authorized.len), card = W, timeout = 0)
		return TRUE

	else if (istype(W, /obj/item/card/emag) && !emagged)
		open_request(src, /datum/prompt/yes_no/shuttle_emag_launch, PROC_REF(emag_launch_chosen), valid = PROC_REF(emag_launch_valid), answerer = user, card = W, timeout = 0)
		return TRUE
	return TRUE

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

/obj/machinery/computer/shuttle/proc/authorization_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/shuttle_authorization/ask = A.request
	var/obj/item/card/id/W = ask.card
	var/mob/user = ask.answerer
	switch(A.answer.value)
		if("Authorize")
			src.authorized -= W:registered_name
			src.authorized += W:registered_name
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
			src.authorized -= W:registered_name
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

/obj/machinery/computer/shuttle/proc/emag_launch_chosen(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	if(!emagged && !SSemergency_shuttle.location())
		to_chat(world, span_boldnotice("Alert: Shuttle launch time shortened to 10 seconds!"))
		SSemergency_shuttle.set_launch_countdown(10)
		set_emagged(1)
