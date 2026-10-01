/*
Eventkit verb to be used to spawn the obj/effect/landmarks defined under code\game\objects\effects\landmarks_events.dm
*/
ADMIN_VERB(manage_event_triggers, R_FUN, "Manage Event Triggers", "Open dialogue to create or delete narration/notification triggers", ADMIN_CATEGORY_FUN_EVENT_KIT)
	om_flow_start(/datum/om/flow/event_triggers, user.mob, null)

/// Managing event triggers: pick a mode, then a trigger list (yours or someone else's), then
/// teleport to or delete one (or all). The admin keeps R_FUN on every step.
/datum/om/flow/event_triggers
	name = "manage event triggers"
	requires = PROMPT_ADMIN(R_FUN)
	/// Whose triggers are listed.
	var/owner_ckey
	var/obj/effect/landmark/event_trigger/trigger

/datum/om/flow/event_triggers/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(mode_picked), title = "Manage Event Triggers", message = "What do you wish to do?", default = "Cancel", choices = list(
		"Create Notification Trigger",
		"Create Narration Trigger",
		"Manage Personal Triggers",
		"Manage Other's Triggers",
		"Cancel"
	))

/datum/om/flow/event_triggers/proc/mode_picked(datum/om/prompt/choice/ask)
	var/mob/user = actor
	if(ask.choice == "Cancel")
		return
	feedback_add_details("admin_verb","EventTriggerManage")
	switch(ask.choice)
		if("Create Notification Trigger")
			var/obj/effect/landmark/event_trigger/ET = new /obj/effect/landmark/event_trigger(user.loc)
			ET.set_vars(user)
		if("Create Narration Trigger")
			var/obj/effect/landmark/event_trigger/auto_narrate/AN = new /obj/effect/landmark/event_trigger/auto_narrate(user.loc)
			AN.set_vars(user)
		if("Manage Personal Triggers")
			list_triggers(user.ckey)
		if("Manage Other's Triggers")
			om_ask(user, /datum/om/prompt/text, PROC_REF(other_entered), title = "CKEY", message = "input trigger owner's ckey", default = "", max_length = MAX_MESSAGE_LEN)

/datum/om/flow/event_triggers/proc/other_entered(datum/om/prompt/text/ask)
	list_triggers(ask.text)

/// Lists `ckey`'s triggers to teleport to or delete.
/datum/om/flow/event_triggers/proc/list_triggers(ckey)
	var/mob/user = actor
	owner_ckey = ckey
	var/list/triggers = GLOB.event_triggers[owner_ckey]
	if(!LAZYLEN(triggers))
		to_chat(user, span_notice(owner_ckey == user.ckey ? "You don't have any landmarks to manage!" : "[owner_ckey] doesn't have any landmarks to manage!"))
		return
	var/list/choices = triggers.Copy()
	choices |= list("Cancel", "Delete All")
	om_ask(user, /datum/om/prompt/choice, PROC_REF(trigger_picked), title = "Manage Personal Triggers", message = "Select a landmark to choose between teleporting to it or deleting it, select delete all to clear them.", choices = choices)

/// The owner is logged in and was active in the last 30 minutes (someone else's triggers only).
/datum/om/flow/event_triggers/proc/owner_active()
	var/mob/user = actor
	if(owner_ckey == user.ckey)
		return null
	var/client/owner = GLOB.directory[owner_ckey]
	var/mob/stat_mob = owner?.statobj
	if(stat_mob?.client && stat_mob.client.inactivity < 30 MINUTES)
		return stat_mob

/// Asks to force-delete while the owner is active, else the plain confirmation.
/datum/om/flow/event_triggers/proc/ask_delete(sure_text, sure_message, next)
	var/mob/stat_mob = owner_active()
	if(stat_mob)
		om_ask(actor, /datum/om/prompt/choice, next, buttons = TRUE, title = "Force Delete", message = "[stat_mob] has only been inactive for [stat_mob.client.inactivity / (1 MINUTE)] minutes.\n \
			If you want to delete their event triggers, ask them in asay or discord to do it themselves or wait 30 minutes. \n \
			Only proceed if you are absolutely certain.", choices = list("Confirm", "Cancel"))
		return
	om_ask(actor, /datum/om/prompt/choice, next, buttons = TRUE, title = "CONFIRM", message = sure_message, choices = list("Go Back", sure_text))

/datum/om/flow/event_triggers/proc/trigger_picked(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	if(ask.choice == "Delete All")
		ask_delete("Delete all my event triggers", "ARE YOU SURE? THERE IS NO GOING BACK", PROC_REF(delete_all))
		return
	rel_set(src, nameof(trigger), ask.choice)
	if(!istype(trigger))
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(manage), buttons = TRUE, title = "Manage [trigger.name]", message = "Teleport to Landmark or Delete it?", choices = list("Teleport", "Delete"))

/datum/om/flow/event_triggers/proc/delete_all(datum/om/prompt/choice/ask)
	var/mob/user = actor
	if(ask.choice != "Confirm" && ask.choice != "Delete all my event triggers")
		return
	for(var/obj/effect/landmark/event_trigger/ET in GLOB.event_triggers[owner_ckey])
		ET.delete_me = TRUE
		qdel(ET)
	if(owner_ckey != user.ckey)
		log_and_message_admins("[user.ckey] deleted all of [owner_ckey]'s event triggers[ask.choice == "Confirm" ? " while [owner_ckey] was active" : ". [owner_ckey] was either inactive or disconnected at this time."]", user)

/datum/om/flow/event_triggers/proc/manage(datum/om/prompt/choice/ask)
	var/mob/user = actor
	if(ask.choice == "Teleport")
		if(isobserver(user))
			om_ask(user, /datum/om/prompt/choice, PROC_REF(teleport_confirmed), buttons = TRUE, title = "You're not a ghost", message = "You're not a ghost! Admin-ghost?", choices = list("Cancel", "Teleport me with my character"))
			return
		user.forceMove(get_turf(trigger))
		return
	if(ask.choice != "Delete")
		return
	ask_delete("Delete it!", "ARE YOU SURE? THERE IS NO GOING BACK FROM DELETING [trigger.name]", PROC_REF(delete_one))

/datum/om/flow/event_triggers/proc/teleport_confirmed(datum/om/prompt/choice/ask)
	var/mob/user = actor
	if(ask.choice == "Teleport me with my character")
		user.forceMove(get_turf(trigger))

/datum/om/flow/event_triggers/proc/delete_one(datum/om/prompt/choice/ask)
	var/mob/user = actor
	if(ask.choice != "Confirm" && ask.choice != "Delete it!")
		return
	var/trigger_name = trigger.name
	trigger.delete_me = TRUE
	qdel(trigger)
	if(owner_ckey != user.ckey)
		log_and_message_admins("[user.ckey] deleted event trigger [trigger_name][ask.choice == "Confirm" ? " while [owner_ckey] is active." : ", [owner_ckey] is either disconnected or inactive."]", user)
