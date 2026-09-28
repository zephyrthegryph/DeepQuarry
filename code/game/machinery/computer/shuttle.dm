/obj/machinery/computer/shuttle
	name = "Shuttle"
	desc = "For shuttle control."
	icon_keyboard = "tech_key"
	icon_screen = "shuttle"
	light_color = "#00ffff"
	var/auth_need = 3.0
	var/list/authorized = list(  ) // ALLOW(instance_list): d: per-console authorisation state


/obj/machinery/computer/shuttle/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/shuttle_authorize,
	)
	..()

/datum/interaction/machine_item/shuttle_authorize
	id = "shuttle_authorize"
	name = "Use"
	held_type = /obj/item/card
	effect = /obj/machinery/computer/shuttle/proc/interaction_authorize

/obj/machinery/computer/shuttle/proc/interaction_authorize(mob/user, obj/item/card/W, datum/interaction/interaction)
	if(stat & (BROKEN|NOPOWER))
		return TRUE
	if ((!( istype(W, /obj/item/card) ) || !( SSticker ) || GLOB.emergency_shuttle_service.location() || !( user )))
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

		om_prompt(src, user, list("message" = text("Would you like to (un)authorize a shortened launch time? [] authorization\s are still needed. Use abort to cancel all authorizations.", src.auth_need - src.authorized.len), "title" = "Shuttle Launch", "choices" = list("Authorize", "Repeal", "Abort"), "target" = W, "requires" = PROMPT_IN_HAND, "data" = list("card" = W)), PROC_REF(authorization_chosen))
		return TRUE

	else if (istype(W, /obj/item/card/emag) && !emagged)
		om_prompt(src, user, list("message" = "Would you like to launch the shuttle?", "title" = "Shuttle control", "choices" = list("Launch", "Cancel"), "target" = W, "requires" = PROMPT_IN_HAND), PROC_REF(emag_launch_chosen))
		return TRUE
	return TRUE

/obj/machinery/computer/shuttle/proc/authorization_chosen(mob/user, choice, datum/om/prompt/ask)
	var/obj/item/card/id/W = ask.get("card")
	switch(choice)
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
				GLOB.emergency_shuttle_service.set_launch_countdown(10)
				src.authorized = list(  )

		if("Repeal")
			src.authorized -= W:registered_name
			to_chat(world, span_boldnotice("Alert: [src.auth_need - src.authorized.len] authorizations needed until shuttle is launched early"))

		if("Abort")
			to_chat(world, span_boldnotice("All authorizations to shortening time for shuttle launch have been revoked!"))
			src.authorized.len = 0
			src.authorized = list(  )

/obj/machinery/computer/shuttle/proc/emag_launch_chosen(mob/user, choice, datum/om/prompt/ask)
	if(!emagged && !GLOB.emergency_shuttle_service.location())
		switch(choice)
			if("Launch")
				to_chat(world, span_boldnotice("Alert: Shuttle launch time shortened to 10 seconds!"))
				GLOB.emergency_shuttle_service.set_launch_countdown(10)
				emagged = 1
			if("Cancel")
				return TRUE
