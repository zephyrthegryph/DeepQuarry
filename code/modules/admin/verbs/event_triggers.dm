/*
Eventkit verb to be used to spawn the obj/effect/landmarks defined under code\game\objects\effects\landmarks_events.dm
*/
ADMIN_VERB(manage_event_triggers, R_FUN, "Manage Event Triggers", "Open dialogue to create or delete narration/notification triggers", ADMIN_CATEGORY_FUN_EVENT_KIT)
	om_prompt(user, user, list("kind" = "list", "message" = "What do you wish to do?", "title" = "Manage Event Triggers", "default" = "Cancel", "requires" = PROMPT_ADMIN(R_FUN), "choices" = list(
		"Create Notification Trigger",
		"Create Narration Trigger",
		"Manage Personal Triggers",
		"Manage Other's Triggers",
		"Cancel"
	)), GLOBAL_PROC_REF(event_triggers_mode))

/proc/event_triggers_mode(client/C, mob/user, mode, datum/om/prompt/ask)
	if(mode == "Cancel")
		return
	feedback_add_details("admin_verb","EventTriggerManage")
	switch(mode)
		if("Create Notification Trigger")
			var/obj/effect/landmark/event_trigger/ET = new /obj/effect/landmark/event_trigger(user.loc)
			ET.set_vars(user)
		if("Create Narration Trigger")
			var/obj/effect/landmark/event_trigger/auto_narrate/AN = new /obj/effect/landmark/event_trigger/auto_narrate(user.loc)
			AN.set_vars(user)
		if("Manage Personal Triggers")
			event_triggers_list(C, user, C.ckey)
		if("Manage Other's Triggers")
			om_prompt_chain(ask, list("kind" = "text", "message" = "input trigger owner's ckey", "title" = "CKEY", "default" = "", "max_length" = MAX_MESSAGE_LEN), GLOBAL_PROC_REF(event_triggers_other))

/proc/event_triggers_other(client/C, mob/user, other_ckey, datum/om/prompt/ask)
	event_triggers_list(C, user, other_ckey)

/// Lists `owner_ckey`'s triggers to teleport to or delete.
/proc/event_triggers_list(client/C, mob/user, owner_ckey)
	var/list/triggers = GLOB.event_triggers[owner_ckey]
	if(!LAZYLEN(triggers))
		to_chat(user, span_notice(owner_ckey == C.ckey ? "You don't have any landmarks to manage!" : "[owner_ckey] doesn't have any landmarks to manage!"))
		return
	var/list/choices = triggers.Copy()
	choices |= list("Cancel", "Delete All")
	om_prompt(C, user, list("kind" = "list", "message" = "Select a landmark to choose between teleporting to it or deleting it, select delete all to clear them.", "title" = "Manage Personal Triggers", "choices" = choices, "requires" = PROMPT_ADMIN(R_FUN), "data" = list("owner" = owner_ckey)), GLOBAL_PROC_REF(event_triggers_picked))

/// The owner is logged in and was active in the last 30 minutes (someone else's triggers only).
/proc/event_triggers_owner_active(client/C, owner_ckey)
	if(owner_ckey == C.ckey)
		return null
	var/client/owner = GLOB.directory[owner_ckey]
	var/mob/stat_mob = owner?.statobj
	if(stat_mob?.client && stat_mob.client.inactivity < 30 MINUTES)
		return stat_mob

/proc/event_triggers_picked(client/C, mob/user, choice, datum/om/prompt/ask)
	if(choice == "Cancel")
		return
	var/owner_ckey = ask.get("owner")
	if(choice == "Delete All")
		var/mob/stat_mob = event_triggers_owner_active(C, owner_ckey)
		if(stat_mob)
			om_prompt_chain(ask, list("message" = "[stat_mob] has only been inactive for [stat_mob.client.inactivity / (1 MINUTE)] minutes.\n \
				If you want to delete their event triggers, ask them in asay or discord to do it themselves or wait 30 minutes. \n \
				Only proceed if you are absolutely certain.", "title" = "Force Delete", "choices" = list("Confirm", "Cancel")), GLOBAL_PROC_REF(event_triggers_delete_all))
			return
		om_prompt_chain(ask, list("message" = "ARE YOU SURE? THERE IS NO GOING BACK", "title" = "CONFIRM", "choices" = list("Go Back", "Delete all my event triggers")), GLOBAL_PROC_REF(event_triggers_delete_all))
		return
	var/obj/effect/landmark/event_trigger/ET = choice
	if(!istype(ET))
		return
	ask.put("trigger", ET)
	om_prompt_chain(ask, list("message" = "Teleport to Landmark or Delete it?", "title" = "Manage [ET.name]", "choices" = list("Teleport", "Delete")), GLOBAL_PROC_REF(event_triggers_manage))

/proc/event_triggers_delete_all(client/C, mob/user, confirm, datum/om/prompt/ask)
	if(confirm != "Confirm" && confirm != "Delete all my event triggers")
		return
	var/owner_ckey = ask.get("owner")
	for(var/obj/effect/landmark/event_trigger/ET in GLOB.event_triggers[owner_ckey])
		ET.delete_me = TRUE
		qdel(ET)
	if(owner_ckey != C.ckey)
		log_and_message_admins("[C.ckey] deleted all of [owner_ckey]'s event triggers[confirm == "Confirm" ? " while [owner_ckey] was active" : ". [owner_ckey] was either inactive or disconnected at this time."]", user)

/proc/event_triggers_manage(client/C, mob/user, decision, datum/om/prompt/ask)
	var/obj/effect/landmark/event_trigger/ET = ask.get("trigger")
	if(decision == "Teleport")
		if(isobserver(user))
			om_prompt_chain(ask, list("message" = "You're not a ghost! Admin-ghost?", "title" = "You're not a ghost", "choices" = list("Cancel", "Teleport me with my character")), GLOBAL_PROC_REF(event_triggers_teleport))
			return
		user.forceMove(get_turf(ET))
		return
	if(decision != "Delete")
		return
	var/mob/stat_mob = event_triggers_owner_active(C, ask.get("owner"))
	if(stat_mob)
		om_prompt_chain(ask, list("message" = "[stat_mob] has only been inactive for [stat_mob.client.inactivity / (1 MINUTE)] minutes.\n \
			If you want to delete their event triggers, ask them in asay or discord to do it themselves or wait 30 minutes. \n \
			Only proceed if you are absolutely certain.", "title" = "Force Delete", "choices" = list("Confirm", "Cancel")), GLOBAL_PROC_REF(event_triggers_delete_one))
		return
	om_prompt_chain(ask, list("message" = "ARE YOU SURE? THERE IS NO GOING BACK FROM DELETING [ET.name]", "title" = "CONFIRM", "choices" = list("Go Back", "Delete it!")), GLOBAL_PROC_REF(event_triggers_delete_one))

/proc/event_triggers_teleport(client/C, mob/user, confirm, datum/om/prompt/ask)
	if(confirm == "Teleport me with my character")
		var/obj/effect/landmark/event_trigger/ET = ask.get("trigger")
		user.forceMove(get_turf(ET))

/proc/event_triggers_delete_one(client/C, mob/user, confirm, datum/om/prompt/ask)
	if(confirm != "Confirm" && confirm != "Delete it!")
		return
	var/obj/effect/landmark/event_trigger/ET = ask.get("trigger")
	var/owner_ckey = ask.get("owner")
	var/trigger_name = ET.name
	ET.delete_me = TRUE
	qdel(ET)
	if(owner_ckey != C.ckey)
		log_and_message_admins("[C.ckey] deleted event trigger [trigger_name][confirm == "Confirm" ? " while [owner_ckey] is active." : ", [owner_ckey] is either disconnected or inactive."]", user)
