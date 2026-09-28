
/obj/effect/env_message
	name = "Env message"
	icon = 'icons/effects/env_message.dmi'
	icon_state = "env_message"
	plane = PLANE_LIGHTING_ABOVE
	mouse_opacity = TRUE
	anchored = TRUE
	var/list/message_list
	var/combined_message = DEVELOPER_WARNING_NAME

REGISTRY_MEMBERSHIP(/obj/effect/env_message, REGISTRY_ENV_MESSAGES)

/obj/effect/env_message/Initialize(mapload)
	.=..()

/obj/effect/env_message/examine(mob/user)
	. = ..()
	for(var/tckey in message_list)
		. += LAZYACCESS(message_list, tckey)

/obj/effect/env_message/proc/add_message(tckey, message)
	LAZYSET(message_list, tckey, message)
	update_message()

/obj/effect/env_message/proc/remove_message(tckey)
	LAZYREMOVE(message_list, tckey)
	if(!length(message_list))
		qdel(src)
	else
		update_message()

/obj/effect/env_message/proc/update_message()
	combined_message = ""
	var/count = 0
	for(var/tckey in message_list)
		combined_message += LAZYACCESS(message_list, tckey)
		count++
		if(!(count == length(message_list)))
			combined_message += "<br><br>"

/obj/effect/env_message/MouseEntered(location, control, params)
	if(usr)
		openToolTip(user = usr, tip_src = src, params = params, title = null, content = combined_message)

	..()

/obj/effect/env_message/MouseDown()
	closeToolTip(usr, src) //No reason not to, really

	..()

/obj/effect/env_message/MouseExited()
	closeToolTip(usr, src) //No reason not to, really

	..()

/proc/clear_env_message(tckey)
	for(var/obj/effect/env_message/EM in REGISTRY_MEMBERS(REGISTRY_ENV_MESSAGES))
		if(tckey in EM.message_list)
			EM.remove_message(tckey)

/mob/living/verb/create_env_message()
	set name = "Create Env Message"
	set desc = "Create an ooc message in the environment for other players to see."
	set category = "OOC.Game"

	if(!istype(src) || !get_turf(src) || !src.ckey)
		return

	var/new_message = rerun_prompt(src, "k74", list("kind" = "text", "message" = "Type in your message. It will be displayed to players who hover over the spot where you are right now. If you already have a message somewhere, it will be removed in the process. Please refrain from abusive or deceptive messages, but otherwise, feel free to be creative!", "title" = "Env Message", "max_length" = MAX_MESSAGE_LEN), VERB_REF(create_env_message), args)
	if(isnull(new_message))
		return

	if(!new_message)
		return

	clear_env_message(src.ckey)

	var/ourturf = get_turf(src)

	var/obj/effect/env_message/EM = locate(/obj/effect/env_message) in ourturf

	if(!EM)
		EM = new /obj/effect/env_message(ourturf)
	EM.add_message(src.ckey, new_message)

	log_game("[key_name(src)] created an Env Message: [new_message] at ([EM.x], [EM.y], [EM.z])")

/mob/living/verb/remove_env_message()
	set name = "Remove Env Message"
	set desc = "Remove your current env message."
	set category = "OOC.Game"

	if(!istype(src) || !src.ckey)
		return

	var/ourturf = get_turf(src)

	var/obj/effect/env_message/EM = locate(/obj/effect/env_message) in ourturf

	if(EM)
		var/answer = rerun_prompt(src, "k104", list("message" = "Do you want to remove this env message? (Note: Selecting 'Yes' will remove other players' messages on this tyle too. Please don't remove other players' messages for no reason. Use 'Only My Message' to remove yours only.)", "title" = "Env Message", "choices" = list("Yes", "Only My Message", "No")), VERB_REF(remove_env_message), args)
		if(isnull(answer))
			return
		if(answer == "Yes")
			if(!(src.ckey in EM.message_list) || length(EM.message_list) > 1)
				log_game("[key_name(src)] deleted an Env Message that contained other players' entries at ([EM.x], [EM.y], [EM.z])")
			qdel(EM)
		else if(answer == "Only My Message")
			clear_env_message(src.ckey)
	else
		var/answer = rerun_prompt(src, "k112", list("message" = "Do you want to remove your env message?", "title" = "Env Message", "choices" = list("Yes", "No")), VERB_REF(remove_env_message), args)
		if(isnull(answer))
			return
		if(answer == "Yes")
			clear_env_message(src.ckey)

//GM tool version

/obj/effect/env_message/admin
	name = "Map message"
	icon = 'icons/effects/env_message.dmi'
	icon_state = "env_message_red"

ADMIN_VERB(create_gm_message, R_FUN, "Map Message - Create", "Create an ooc message in the environment for other players to see.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/mob/user_mob = user.mob
	if(isnewplayer(user_mob))
		to_chat(user, span_warning("You must spawn or observe to place messages."))
		return

	if(!get_turf(user_mob))
		return

	var/new_message = verb_prompt(user, "k132", list("kind" = "text", "message" = "Type in your message. It will be displayed to players who hover over the spot where you are right now.", "title" = "Env Message", "max_length" = MAX_MESSAGE_LEN), args)
	if(isnull(new_message))
		return

	if(!new_message)
		return

	var/ourturf = get_turf(user_mob)

	var/obj/effect/env_message/new_env_message = locate(/obj/effect/env_message) in ourturf

	if(!new_env_message)
		new_env_message = new /obj/effect/env_message/admin(ourturf)
	new_env_message.add_message(user.ckey, new_message)

	log_game("[key_name(user)] created an Env Message: [new_message] at ([new_env_message.x], [new_env_message.y], [new_env_message.z])")

ADMIN_VERB(remove_gm_message, R_FUN, "Map Message - Remove", "Remove any env/map message.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/list/all_map_messages = list()
	for(var/obj/effect/env_message/available_message in world)
		all_map_messages |= available_message.combined_message

	if(!length(all_map_messages))
		to_chat(user, span_warning("There are no map or env messages."))
		return

	var/mob/chosen_message = verb_prompt(user, "k156", list("kind" = "list", "message" = "Which message do you want to remove?", "title" = "Make contact", "choices" = all_map_messages), args)
	if(isnull(chosen_message))
		return
	if(!chosen_message)
		return

	for(var/obj/effect/env_message/env_message in world)
		if(env_message.combined_message == chosen_message)
			log_game("[key_name(user)] deleted an Env Message that contained other players' entries at ([env_message.x], [env_message.y], [env_message.z])")
			qdel(env_message)
