/*
Eventkit verb to be used to spawn the obj/effect/landmarks defined under code\game\objects\effects\landmarks_events.dm
*/
ADMIN_VERB(manage_event_triggers, R_FUN, "Manage Event Triggers", "Open dialogue to create or delete narration/notification triggers", ADMIN_CATEGORY_FUN_EVENT_KIT)
	user.mob?.ask_manage_event_triggers()

/// Managing event triggers keeps the initiating admin and selected landmark across each answer.
/datum/prompt/choice/manage_event_triggers
	rights = R_FUN
	timeout = 0
	var/owner_ckey
	var/obj/effect/landmark/event_trigger/trigger
	var/needs_trigger = FALSE
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/manage_event_triggers)
	ref_one(nameof(trigger), /obj/effect/landmark/event_trigger)

/datum/prompt/choice/manage_event_triggers/prepare(datum/act/A)
	..()
	var/obj/effect/landmark/event_trigger/captured_trigger = trigger
	needs_trigger = !isnull(captured_trigger)
	rel_clear(src, nameof(trigger))
	rel_set(src, nameof(trigger), captured_trigger)

/datum/prompt/choice/manage_event_triggers/recheck_extra()
	return needs_trigger && QDELETED(trigger) ? "gone" : null

/mob/proc/ask_manage_event_triggers()
	ask_event_trigger_choice(PROC_REF(event_trigger_mode_picked), null, null, "Manage Event Triggers", "What do you wish to do?", list("Create Notification Trigger", "Create Narration Trigger", "Manage Personal Triggers", "Manage Other's Triggers", "Cancel"), FALSE, "Cancel")

/mob/proc/ask_event_trigger_choice(next, owner_ckey, obj/effect/landmark/event_trigger/trigger, title, question, list/choices, buttons = FALSE, default = null)
	open_request(src, /datum/prompt/choice/manage_event_triggers, next, answerer = src, owner_ckey = owner_ckey, trigger = trigger, title = title, question = question, choices = choices, buttons = buttons, default = default)

/mob/proc/event_trigger_mode_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/choice = A.answer.value
	var/mob/user = src
	if(choice == "Cancel")
		return
	feedback_add_details("admin_verb","EventTriggerManage")
	switch(choice)
		if("Create Notification Trigger")
			var/obj/effect/landmark/event_trigger/ET = new /obj/effect/landmark/event_trigger(user.loc)
			ET.set_vars(user)
		if("Create Narration Trigger")
			var/obj/effect/landmark/event_trigger/auto_narrate/AN = new /obj/effect/landmark/event_trigger/auto_narrate(user.loc)
			AN.set_vars(user)
		if("Manage Personal Triggers")
			list_event_triggers(user.ckey)
		if("Manage Other's Triggers")
			open_request(src, /datum/prompt/text, PROC_REF(event_trigger_other_entered), answerer = src, rights = R_FUN, timeout = 0, title = "CKEY", question = "input trigger owner's ckey", default = "", max_len = MAX_MESSAGE_LEN)

/mob/proc/event_trigger_other_entered(datum/act/request/A)
	if(!A.answer || isnull(A.answer.value))
		return
	list_event_triggers(A.answer.value)

/mob/proc/list_event_triggers(owner_ckey)
	var/mob/user = src
	var/list/triggers = GLOB.event_triggers[owner_ckey]
	if(!LAZYLEN(triggers))
		to_chat(user, span_notice(owner_ckey == user.ckey ? "You don't have any landmarks to manage!" : "[owner_ckey] doesn't have any landmarks to manage!"))
		return
	var/list/choices = triggers.Copy()
	choices |= list("Cancel", "Delete All")
	ask_event_trigger_choice(PROC_REF(event_trigger_picked), owner_ckey, null, "Manage Personal Triggers", "Select a landmark to choose between teleporting to it or deleting it, select delete all to clear them.", choices)

/// The owner is logged in and was active in the last 30 minutes (someone else's triggers only).
/mob/proc/event_trigger_owner_active(owner_ckey)
	if(owner_ckey == ckey)
		return null
	var/client/owner = GLOB.directory[owner_ckey]
	var/mob/stat_mob = owner?.statobj
	if(stat_mob?.client && stat_mob.client.inactivity < 30 MINUTES)
		return stat_mob

/mob/proc/ask_delete_event_trigger(owner_ckey, obj/effect/landmark/event_trigger/trigger, sure_text, sure_message, next)
	var/mob/stat_mob = event_trigger_owner_active(owner_ckey)
	if(stat_mob)
		ask_event_trigger_choice(next, owner_ckey, trigger, "Force Delete", "[stat_mob] has only been inactive for [stat_mob.client.inactivity / (1 MINUTE)] minutes.\n \
			If you want to delete their event triggers, ask them in asay or discord to do it themselves or wait 30 minutes. \n \
			Only proceed if you are absolutely certain.", list("Confirm", "Cancel"), TRUE)
		return
	ask_event_trigger_choice(next, owner_ckey, trigger, "CONFIRM", sure_message, list("Go Back", sure_text), TRUE)

/mob/proc/event_trigger_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/manage_event_triggers/ask = A.answer
	if(ask.value == "Cancel")
		return
	if(ask.value == "Delete All")
		ask_delete_event_trigger(ask.owner_ckey, null, "Delete all my event triggers", "ARE YOU SURE? THERE IS NO GOING BACK", PROC_REF(event_triggers_delete_all))
		return
	var/obj/effect/landmark/event_trigger/trigger = ask.value
	if(!istype(trigger) || QDELETED(trigger))
		return
	ask_event_trigger_choice(PROC_REF(event_trigger_manage), ask.owner_ckey, trigger, "Manage [trigger.name]", "Teleport to Landmark or Delete it?", list("Teleport", "Delete"), TRUE)

/mob/proc/event_triggers_delete_all(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/manage_event_triggers/ask = A.answer
	var/owner_ckey = ask.owner_ckey
	var/choice = ask.value
	var/mob/user = src
	if(choice != "Confirm" && choice != "Delete all my event triggers")
		return
	for(var/obj/effect/landmark/event_trigger/ET in GLOB.event_triggers[owner_ckey])
		ET.delete_me = TRUE
		qdel(ET)
	if(owner_ckey != user.ckey)
		log_and_message_admins("[user.ckey] deleted all of [owner_ckey]'s event triggers[choice == "Confirm" ? " while [owner_ckey] was active" : ". [owner_ckey] was either inactive or disconnected at this time."]", user)

/mob/proc/event_trigger_manage(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/manage_event_triggers/ask = A.answer
	var/obj/effect/landmark/event_trigger/trigger = ask.trigger
	var/mob/user = src
	if(ask.value == "Teleport")
		if(isobserver(user))
			ask_event_trigger_choice(PROC_REF(event_trigger_teleport_confirmed), ask.owner_ckey, trigger, "You're not a ghost", "You're not a ghost! Admin-ghost?", list("Cancel", "Teleport me with my character"), TRUE)
			return
		user.forceMove(get_turf(trigger))
		return
	if(ask.value != "Delete")
		return
	ask_delete_event_trigger(ask.owner_ckey, trigger, "Delete it!", "ARE YOU SURE? THERE IS NO GOING BACK FROM DELETING [trigger.name]", PROC_REF(event_trigger_delete_one))

/mob/proc/event_trigger_teleport_confirmed(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/manage_event_triggers/ask = A.answer
	var/mob/user = src
	if(ask.value == "Teleport me with my character")
		user.forceMove(get_turf(ask.trigger))

/mob/proc/event_trigger_delete_one(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/manage_event_triggers/ask = A.answer
	var/owner_ckey = ask.owner_ckey
	var/obj/effect/landmark/event_trigger/trigger = ask.trigger
	var/choice = ask.value
	var/mob/user = src
	if(choice != "Confirm" && choice != "Delete it!")
		return
	var/trigger_name = trigger.name
	trigger.delete_me = TRUE
	qdel(trigger)
	if(owner_ckey != user.ckey)
		log_and_message_admins("[user.ckey] deleted event trigger [trigger_name][choice == "Confirm" ? " while [owner_ckey] is active." : ", [owner_ckey] is either disconnected or inactive."]", user)
