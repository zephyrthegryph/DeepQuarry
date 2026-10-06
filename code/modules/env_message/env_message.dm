
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
		consume(src)
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

CAPABILITIES(/obj/effect/env_message)
	tooltip(PROC_REF(env_message_tooltip))

/// The tooltip the hovering mob sees (tooltip(), code/engine/lifeforms/input.dm): the message, untitled.
/obj/effect/env_message/proc/env_message_tooltip(mob/user)
	return list(null, combined_message)

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
	set category = VERB_CAT_OOC_GAME

	return environment_create_stage(list())

/mob/living/proc/environment_create_stage(list/environment_answers)

	if(!istype(src) || !get_turf(src) || !src.ckey)
		return

	if(!("k74" in environment_answers))
		open_request(src, /datum/prompt/text/environment_message_review, PROC_REF(environment_create_answered), answerer = src, environment_answers = environment_answers, environment_key = "k74", question = "Type in your message. It will be displayed to players who hover over the spot where you are right now. If you already have a message somewhere, it will be removed in the process. Please refrain from abusive or deceptive messages, but otherwise, feel free to be creative!", title = "Env Message")
		return
	var/new_message = environment_answers["k74"]
	if(isnull(new_message))
		return

	if(!new_message)
		return

	clear_env_message(src.ckey)

	var/ourturf = get_turf(src)

	var/obj/effect/env_message/EM = locate_within(ourturf, /obj/effect/env_message)

	if(!EM)
		EM = new /obj/effect/env_message(ourturf)
	EM.add_message(src.ckey, new_message)

	log_game("[key_name(src)] created an Env Message: [new_message] at ([EM.x], [EM.y], [EM.z])")

/mob/living/verb/remove_env_message()
	set name = "Remove Env Message"
	set desc = "Remove your current env message."
	set category = VERB_CAT_OOC_GAME

	return environment_remove_stage(list())

/mob/living/proc/environment_remove_stage(list/environment_answers)

	if(!istype(src) || !src.ckey)
		return

	var/ourturf = get_turf(src)

	var/obj/effect/env_message/EM = locate_within(ourturf, /obj/effect/env_message)

	if(EM)
		if(!("k104" in environment_answers))
			open_request(src, /datum/prompt/choice/environment_message_review, PROC_REF(environment_remove_answered), answerer = src, environment_answers = environment_answers, environment_key = "k104", question = "Do you want to remove this env message? (Note: Selecting 'Yes' will remove other players' messages on this tyle too. Please don't remove other players' messages for no reason. Use 'Only My Message' to remove yours only.)", title = "Env Message", choices = list("Yes", "Only My Message", "No"), buttons = TRUE)
			return
		var/answer = environment_answers["k104"]
		if(isnull(answer))
			return
		if(answer == "Yes")
			if(!(src.ckey in EM.message_list) || length(EM.message_list) > 1)
				log_game("[key_name(src)] deleted an Env Message that contained other players' entries at ([EM.x], [EM.y], [EM.z])")
			spent(EM)
		else if(answer == "Only My Message")
			clear_env_message(src.ckey)
	else
		if(!("k112" in environment_answers))
			open_request(src, /datum/prompt/choice/environment_message_review, PROC_REF(environment_remove_answered), answerer = src, environment_answers = environment_answers, environment_key = "k112", question = "Do you want to remove your env message?", title = "Env Message", choices = list("Yes", "No"), buttons = TRUE)
			return
		var/answer = environment_answers["k112"]
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
	return gm_environment_create_stage(user, list())

/datum/admin_verb/create_gm_message/proc/gm_environment_create_stage(client/user, list/environment_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	var/mob/user_mob = user.mob
	if(isnewplayer(user_mob))
		to_chat(user, span_warning("You must spawn or observe to place messages."))
		return

	if(!get_turf(user_mob))
		return

	if(!("k132" in environment_answers))
		open_request(src, /datum/prompt/text/environment_message_review, PROC_REF(gm_environment_create_answered), answerer = user.mob, environment_answers = environment_answers, environment_key = "k132", rights = R_FUN, question = "Type in your message. It will be displayed to players who hover over the spot where you are right now.", title = "Env Message")
		return
	var/new_message = environment_answers["k132"]
	if(isnull(new_message))
		return

	if(!new_message)
		return

	var/ourturf = get_turf(user_mob)

	var/obj/effect/env_message/new_env_message = locate_within(ourturf, /obj/effect/env_message)

	if(!new_env_message)
		new_env_message = new /obj/effect/env_message/admin(ourturf)
	new_env_message.add_message(user.ckey, new_message)

	log_game("[key_name(user)] created an Env Message: [new_message] at ([new_env_message.x], [new_env_message.y], [new_env_message.z])")

ADMIN_VERB(remove_gm_message, R_FUN, "Map Message - Remove", "Remove any env/map message.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	return gm_environment_remove_stage(user, list())

/datum/admin_verb/remove_gm_message/proc/gm_environment_remove_stage(client/user, list/environment_answers)
	var/list/all_map_messages = list()
	for(var/obj/effect/env_message/available_message in world)
		all_map_messages |= available_message.combined_message

	if(!length(all_map_messages))
		to_chat(user, span_warning("There are no map or env messages."))
		return

	if(!("k156" in environment_answers))
		if(!user || !user.mob || QDELETED(user.mob))
			return
		open_request(src, /datum/prompt/choice/environment_message_review, PROC_REF(gm_environment_remove_answered), answerer = user.mob, environment_answers = environment_answers, environment_key = "k156", rights = R_FUN, question = "Which message do you want to remove?", title = "Make contact", choices = all_map_messages)
		return
	var/mob/chosen_message = environment_answers["k156"]
	if(isnull(chosen_message))
		return
	if(!chosen_message)
		return

	for(var/obj/effect/env_message/env_message in world)
		if(env_message.combined_message == chosen_message)
			log_game("[key_name(user)] deleted an Env Message that contained other players' entries at ([env_message.x], [env_message.y], [env_message.z])")
			spent(env_message, user)

/mob/living/proc/environment_create_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/environment_message_review/ask = context.answer
	var/list/environment_answers = ask.environment_answers.Copy()
	environment_answers[ask.environment_key] = ask.value
	environment_create_stage(environment_answers)
	SStgui.update_uis(src)

/mob/living/proc/environment_remove_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/environment_message_review/ask = context.answer
	var/list/environment_answers = ask.environment_answers.Copy()
	environment_answers[ask.environment_key] = ask.value
	environment_remove_stage(environment_answers)
	SStgui.update_uis(src)

/datum/admin_verb/create_gm_message/proc/gm_environment_create_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/environment_message_review/ask = context.answer
	var/list/environment_answers = ask.environment_answers.Copy()
	environment_answers[ask.environment_key] = ask.value
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(environment_message_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	return gm_environment_create_stage(user, environment_answers)

/datum/admin_verb/remove_gm_message/proc/gm_environment_remove_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/environment_message_review/ask = context.answer
	var/list/environment_answers = ask.environment_answers.Copy()
	environment_answers[ask.environment_key] = ask.value
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(environment_message_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	return gm_environment_remove_stage(user, environment_answers)

/proc/environment_message_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/prompt/text/environment_message_review
	timeout = 0
	recheck_on_open = TRUE
	var/list/environment_answers
	var/environment_key

/datum/prompt/text/environment_message_review/recheck_extra()
	var/mob/admin = answerer
	if(rights && !admin_can(admin?.client, 0))
		return "no admin rights"

/datum/prompt/text/environment_message_review/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/environment_message_review
	timeout = 0
	recheck_on_open = TRUE
	var/list/environment_answers
	var/environment_key

/datum/prompt/choice/environment_message_review/recheck_extra()
	var/mob/admin = answerer
	if(rights && !admin_can(admin?.client, 0))
		return "no admin rights"
