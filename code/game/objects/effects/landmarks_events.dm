/*
Landmark to be spawned by GMs and admins when running events.
Do NOT directly spawn "" or buildmode spawn this.
Use the "Manage Event Triggers" verb under "Eventkit" category.
Admin verb is called by code\modules\admin\verbs\event_triggers.dm
*/
/obj/effect/landmark/event_trigger
	name = "ONLY FOR EVENTS. DO NOT USE WHEN MAPPING"
	desc = "Please notify staff if you see this!"
	var/creator_ckey = ""
	var/isTeamwork = FALSE //Whether to notify creator or whole team.
	var/isRepeating = FALSE
	var/coordinates = ""
	var/cooldown = 0 //Given in seconds in set_vars() but stored in ticks
	var/last_trigger = 0
	var/isLoud = FALSE
	var/isNarrate = FALSE

/obj/effect/landmark/event_trigger/Initialize(mapload)
	. = ..()
	coordinates = "(X:[loc.x];Y:[loc.y];Z:[loc.z])"

/// Asks the creator how the trigger behaves (om_prompt_sequence); the answers land in apply_vars().
/obj/effect/landmark/event_trigger/proc/set_vars(mob/M)
	om_prompt_sequence(src, M, setup_steps(), PROC_REF(apply_vars), list("requires" = PROMPT_ADMIN(R_FUN), "on_cancel" = PROC_REF(setup_cancelled)))

/obj/effect/landmark/event_trigger/proc/setup_steps()
	return list(
		list("key" = "name", "kind" = "text", "message" = "Input Name for the trigger", "title" = "Naming", "default" = "Event Trigger", "max_length" = MAX_MESSAGE_LEN),
		list("key" = "team", "message" = "Notify rest of team?", "title" = "Teamwork", "choices" = list("No", "Yes")),
		PROC_REF(ask_loud),
		list("key" = "repeat", "message" = "Make it fire repeatedly?", "title" = "Repetition", "choices" = list("No", "Yes")),
		PROC_REF(ask_cooldown),
	)

/obj/effect/landmark/event_trigger/proc/ask_loud(mob/user, datum/om/prompt/ask)
	if(ask.get("team") != "Yes")
		return list("key" = "loud", "message" = "Should it make a bwoink when triggered for YOU?", "title" = "bwoink", "choices" = list("No", "Yes"))

/obj/effect/landmark/event_trigger/proc/ask_cooldown(mob/user, datum/om/prompt/ask)
	if(ask.get("repeat") == "Yes")
		return list("key" = "cooldown", "kind" = "number", "message" = "Set cooldown in seconds. Minimum 5 seconds!", "title" = "Cooldown", "default" = 60, "min" = 5)

/obj/effect/landmark/event_trigger/proc/setup_cancelled(mob/user, datum/om/prompt/ask)
	qdel(src)

/obj/effect/landmark/event_trigger/proc/apply_vars(mob/M, datum/om/prompt/ask)
	var/new_name = ask.get("name")
	if(!new_name)
		qdel(src)
		return
	name = new_name
	creator_ckey = M.ckey
	if(!GLOB.event_triggers[creator_ckey])
		GLOB.event_triggers[creator_ckey] = list()
	GLOB.event_triggers[creator_ckey] |= list(src)
	isTeamwork = ask.get("team") == "Yes"
	isLoud = !isTeamwork && ask.get("loud") == "Yes"
	isRepeating = ask.get("repeat") == "Yes"
	if(isRepeating)
		cooldown = ask.get("cooldown") SECONDS
	else
		delete_me = TRUE
	log_admin("[M.ckey] has created a [isNarrate ? "Narrtion" : "Notification"] landmark trigger at [coordinates]")

/obj/effect/landmark/event_trigger/Destroy()
	if(GLOB.event_triggers[creator_ckey])
		GLOB.event_triggers[creator_ckey] -= src
	. = ..()

/obj/effect/landmark/event_trigger/Crossed(atom/movable/AM)
	if(!isliving(AM))
		return FALSE
	var/mob/living/L = AM
	if(!L.ckey) return FALSE

	if(world.time < (last_trigger + cooldown))
		return FALSE
	if(!isRepeating && last_trigger) //Used to avoid spam if qdel(src) fires too slowly
		return FALSE
	last_trigger = world.time

	if(!creator_ckey)	//For some reason, the user didn't have a ckey. Let's clean up
		qdel(src)
		return FALSE
	var/mob/creator_reference = GLOB.directory[creator_ckey]
	if(!creator_reference || isTeamwork)	//If logged/crashed, we default to teamwork mode
		message_admins("Player [L.name] ([L.ckey]) has triggered event narrate landmark [name] of type \
			[isNarrate ? "Narration" : "Notification"]. \n \
			The landmark was created by [creator_ckey], and it [isRepeating ? \
			"will be possible to trigger after [cooldown / (1 SECOND)] seconds" : "has self-deleted"]\n \
			COORDINATES: [coordinates]")
	else
		if(isLoud)
			creator_reference << 'sound/effects/adminhelp.ogg'
		to_chat(creator_reference, span_warning("Player [L.name] ([L.ckey]) has triggered event \
			narrate landmark [name] of type [isNarrate ? "Narration" : "Notification"]. \n \
			It [isRepeating ? "will be possible to trigger after [cooldown / (1 SECOND)] seconds" : "has self-deleted"] \n \
			COORDINATES: [coordinates]"))
	if(!isNarrate)
		if(!isRepeating)
			qdel(src)
		return FALSE
	else
		return L


/obj/effect/landmark/event_trigger/auto_narrate
	var/message
	var/isPersonal_orVis_orAud = 0	//0 for personal, 1 for vis, 2 for aud
	var/message_range	//Leave at 0 for world.view
	var/isWarning = FALSE 	//For personal messages
	isNarrate = TRUE

/obj/effect/landmark/event_trigger/auto_narrate/Initialize(mapload)
	. = ..()
	message_range = world.view

/obj/effect/landmark/event_trigger/auto_narrate/setup_steps()
	return ..() + list(
		list("key" = "message", "kind" = "text", "message" = "What should the automatic narration say?", "title" = "Message", "default" = "", "max_length" = MAX_MESSAGE_LEN),
		list("key" = "target", "message" = "Should it send directly to the player, or send to the turf?", "title" = "Target", "choices" = list("Player", "Turf")),
		PROC_REF(ask_style),
		PROC_REF(ask_range),
	)

/obj/effect/landmark/event_trigger/auto_narrate/proc/ask_style(mob/user, datum/om/prompt/ask)
	if(ask.get("target") == "Player")
		return list("key" = "scary", "message" = "Should it be a normal message or a big scary red text?", "title" = "Scary Red", "choices" = list("Big Red", "Normal"))
	return list("key" = "mode", "message" = "Should it be visible or audible?", "title" = "Mode", "choices" = list("Visible", "Audible"))

/obj/effect/landmark/event_trigger/auto_narrate/proc/ask_range(mob/user, datum/om/prompt/ask)
	if(ask.get("target") != "Player")
		return list("key" = "range", "kind" = "number", "message" = "Give narration range! Input value over 10 to use world.view", "title" = "Range", "default" = 11, "min" = 0)

/obj/effect/landmark/event_trigger/auto_narrate/apply_vars(mob/M, datum/om/prompt/ask)
	..()
	if(QDELETED(src))
		return
	message = encode_html_emphasis(ask.get("message"))
	if(ask.get("target") == "Player")
		isPersonal_orVis_orAud = 0
		isWarning = ask.get("scary") == "Big Red"
	else
		isPersonal_orVis_orAud = ask.get("mode") == "Audible" ? 2 : 1
		var/range = ask.get("range")
		if(range <= 10)
			message_range = range

/obj/effect/landmark/event_trigger/auto_narrate/Crossed(atom/movable/AM)
	. = ..()	//Checks if AM is mob/living and notifies admin(s)
	if(!.)
		return
	var/mob/living/L = .
	var/turf/T = get_turf(src)
	switch(isPersonal_orVis_orAud)
		if(0)
			if(isWarning)
				to_chat(L, span_danger(message))
			else
				to_chat(L, message)
		if(1)
			T.visible_message(message, range = message_range, runemessage = message)
		if(2)
			T.audible_message(message, hearing_distance = message_range, runemessage= message)
	if(!isRepeating)
		qdel(src)
