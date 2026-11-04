/*
Event Collector Admin Commands
*/

ADMIN_VERB_AND_CONTEXT_MENU(modify_event_collector, R_ADMIN, "Configure Collector", "Configure Event Collector.", ADMIN_CATEGORY_FUN_EVENT_KIT, obj/structure/event_collector/target in REGISTRY_MEMBERS(REGISTRY_EVENT_COLLECTORS))
	var/msg = "---------------\n"
	if(target?.active_recipe?.len > 0)
		msg += " [target] has [target.active_recipe.len] left in its current recipe\n"
		for(var/i in target.active_recipe)
			msg += "* [i] \n"

	else
		msg += "[target] has no more required items! \n"

	if(target.calls_remaining > 0)
		msg += "[target] has [target.calls_remaining] progress to go! - unless stopped or slowed, this is about [(target.calls_remaining / 10 ) * 2] seconds! \n"

	var/blockers = target.get_blockers()

	if(blockers > 0)
		msg += "[target] has [blockers] things blocking/slowing it down! Anything more than 10 means it's stopped!"

	to_chat(user, msg)


	var/list/options = list(
		"Cancel",
		"Start New Recipe",
		"Clear Current Recipe",
		"Force Clear Blockers"
	)

	var/option
	var/datum/request/resumed = length(args) > 2 ? args[3] : null
	if(istype(resumed, /datum/prompt/choice/admin_collector_configuration) && resumed.owner == src && resumed.answerer == user.mob && resumed.subject == target && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(collector_configuration_answered))
		option = resumed.value
	else
		open_request(src, /datum/prompt/choice/admin_collector_configuration, PROC_REF(collector_configuration_answered), answerer = user.mob, subject = target, question = "What Would You Like To Do?", title = "Event Collector", choices = options, default = "Cancel")
		return
	if(isnull(option))
		return
	switch(option)
		if("Cancel")
			return
		if("Start New Recipe")
			target.pick_new_recipe()
		if("Clear Current Recipe")
			target.active_recipe = list()
			target.calls_remaining = 0
			target.set_awaiting_next_recipe(TRUE)

		if("Force Clear Blockers")
			for(var/obj/structure/event_collector_blocker/tofix as anything in REGISTRY_MEMBERS(REGISTRY_EVENT_COLLECTOR_BLOCKERS))
				if(tofix.blocker_channel == target.blocker_channel)
					tofix.fix()

		if("Empty Stored Items")
			target.empty_items()

ADMIN_VERB_AND_CONTEXT_MENU(induce_malfunction, R_ADMIN, "Toggle Malfunction State", "Configure Collector Blocker.", ADMIN_CATEGORY_FUN_EVENT_KIT, obj/structure/event_collector_blocker/target in REGISTRY_MEMBERS(REGISTRY_EVENT_COLLECTOR_BLOCKERS))
	if(target.block_amount)
		target.fix()
		return

	target.induce_failure()

/// The typed subject preserves the original context-menu target across the wait.
/datum/prompt/choice/admin_collector_configuration
	timeout = 0
	rights = R_ADMIN
	recheck_on_open = TRUE

/datum/prompt/choice/admin_collector_configuration/normalize(given)
	return given

/datum/prompt/choice/admin_collector_configuration/refusal(given)
	return null

/datum/prompt/choice/admin_collector_configuration/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer) || !subject || QDELETED(subject))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/admin_verb/modify_event_collector/proc/collector_configuration_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	var/obj/structure/event_collector/target = A.request.subject
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, target, A.answer)
