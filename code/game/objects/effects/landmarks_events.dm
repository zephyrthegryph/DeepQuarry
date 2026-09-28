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
	COOLDOWN_DECLARE(trigger_cooldown)
	var/isLoud = FALSE
	var/isNarrate = FALSE
	/// The setup questions set_vars() asks.
	var/setup_flow = /datum/om/flow/event_trigger_setup

/obj/effect/landmark/event_trigger/Initialize(mapload)
	. = ..()
	coordinates = "(X:[loc.x];Y:[loc.y];Z:[loc.z])"

/// Asks the creator how the trigger behaves (setup_flow); the answers land in apply_vars().
/obj/effect/landmark/event_trigger/proc/set_vars(mob/M)
	om_flow_start(setup_flow, M, src)

/// The trigger's setup questions: name, teamwork, bwoink, repetition, cooldown. The creator
/// keeps their event rights throughout; any cancel deletes the unfinished trigger.
/datum/om/flow/event_trigger_setup
	requires = PROMPT_ADMIN(R_FUN)
	var/trigger_name
	var/team = FALSE
	var/loud = FALSE
	var/repeat = FALSE
	var/cooldown_seconds = 0

/datum/om/flow/event_trigger_setup/ended(reason)
	qdel(target)

/datum/om/flow/event_trigger_setup/start()
	om_ask(actor, /datum/om/prompt/text, PROC_REF(named), title = "Naming", message = "Input Name for the trigger", default = "Event Trigger", max_length = MAX_MESSAGE_LEN)

/datum/om/flow/event_trigger_setup/proc/named(datum/om/prompt/text/ask)
	if(!ask.text)
		qdel(target)
		return
	trigger_name = ask.text
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(team_answered), title = "Teamwork", message = "Notify rest of team?", no_first = TRUE, answer_on_no = TRUE)

/datum/om/flow/event_trigger_setup/proc/team_answered(datum/om/prompt/confirm/ask)
	team = ask.yes
	if(team)
		ask_repeat()
		return
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(loud_answered), title = "bwoink", message = "Should it make a bwoink when triggered for YOU?", no_first = TRUE, answer_on_no = TRUE)

/datum/om/flow/event_trigger_setup/proc/loud_answered(datum/om/prompt/confirm/ask)
	loud = ask.yes
	ask_repeat()

/datum/om/flow/event_trigger_setup/proc/ask_repeat()
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(repeat_answered), title = "Repetition", message = "Make it fire repeatedly?", no_first = TRUE, answer_on_no = TRUE)

/datum/om/flow/event_trigger_setup/proc/repeat_answered(datum/om/prompt/confirm/ask)
	repeat = ask.yes
	if(!repeat)
		basics_done()
		return
	om_ask(actor, /datum/om/prompt/number, PROC_REF(cooldown_entered), title = "Cooldown", message = "Set cooldown in seconds. Minimum 5 seconds!", default = 60, min = 5)

/datum/om/flow/event_trigger_setup/proc/cooldown_entered(datum/om/prompt/number/ask)
	cooldown_seconds = ask.number
	basics_done()

/// The shared questions are answered: subtypes ask theirs here, then apply.
/datum/om/flow/event_trigger_setup/proc/basics_done()
	finish()

/datum/om/flow/event_trigger_setup/proc/finish()
	var/obj/effect/landmark/event_trigger/ET = target
	ET.apply_vars(actor, src)

/obj/effect/landmark/event_trigger/proc/apply_vars(mob/M, datum/om/flow/event_trigger_setup/setup)
	name = setup.trigger_name
	creator_ckey = M.ckey
	if(!GLOB.event_triggers[creator_ckey])
		GLOB.event_triggers[creator_ckey] = list()
	GLOB.event_triggers[creator_ckey] |= list(src)
	isTeamwork = setup.team
	isLoud = !isTeamwork && setup.loud
	isRepeating = setup.repeat
	if(isRepeating)
		cooldown = setup.cooldown_seconds SECONDS
	else
		delete_me = TRUE
	log_admin("[M.ckey] has created a [isNarrate ? "Narrtion" : "Notification"] landmark trigger at [coordinates]")

/// Phase 2: leaves its creator's event trigger list.
/obj/effect/landmark/event_trigger/lifecycle_dematerialize()
	. = ..()
	if(GLOB.event_triggers[creator_ckey])
		GLOB.event_triggers[creator_ckey] -= src

/obj/effect/landmark/event_trigger/Crossed(atom/movable/AM)
	if(!isliving(AM))
		return FALSE
	var/mob/living/L = AM
	if(!L.ckey) return FALSE

	if(COOLDOWN_TIMELEFT(src, trigger_cooldown))
		return FALSE
	if(!isRepeating && last_trigger) //Used to avoid spam if qdel(src) fires too slowly
		return FALSE
	last_trigger = world.time
	COOLDOWN_START(src, trigger_cooldown, cooldown)

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
	setup_flow = /datum/om/flow/event_trigger_setup/narrate

/obj/effect/landmark/event_trigger/auto_narrate/Initialize(mapload)
	. = ..()
	message_range = world.view

/// Then: the narration, where it goes, its style and its range.
/datum/om/flow/event_trigger_setup/narrate
	var/narration
	var/to_player = FALSE
	var/scary = FALSE
	var/audible = FALSE
	var/range = 11

/datum/om/flow/event_trigger_setup/narrate/basics_done()
	om_ask(actor, /datum/om/prompt/text, PROC_REF(narration_entered), title = "Message", message = "What should the automatic narration say?", default = "", max_length = MAX_MESSAGE_LEN)

/datum/om/flow/event_trigger_setup/narrate/proc/narration_entered(datum/om/prompt/text/ask)
	narration = ask.text
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(target_chosen), title = "Target", message = "Should it send directly to the player, or send to the turf?", choices = list("Player", "Turf"), buttons = TRUE)

/datum/om/flow/event_trigger_setup/narrate/proc/target_chosen(datum/om/prompt/choice/ask)
	to_player = (ask.choice == "Player")
	if(to_player)
		om_ask(actor, /datum/om/prompt/choice, PROC_REF(scary_chosen), title = "Scary Red", message = "Should it be a normal message or a big scary red text?", choices = list("Big Red", "Normal"), buttons = TRUE)
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(mode_chosen), title = "Mode", message = "Should it be visible or audible?", choices = list("Visible", "Audible"), buttons = TRUE)

/datum/om/flow/event_trigger_setup/narrate/proc/scary_chosen(datum/om/prompt/choice/ask)
	scary = (ask.choice == "Big Red")
	finish()

/datum/om/flow/event_trigger_setup/narrate/proc/mode_chosen(datum/om/prompt/choice/ask)
	audible = (ask.choice == "Audible")
	om_ask(actor, /datum/om/prompt/number, PROC_REF(range_entered), title = "Range", message = "Give narration range! Input value over 10 to use world.view", default = 11, min = 0)

/datum/om/flow/event_trigger_setup/narrate/proc/range_entered(datum/om/prompt/number/ask)
	range = ask.number
	finish()

/obj/effect/landmark/event_trigger/auto_narrate/apply_vars(mob/M, datum/om/flow/event_trigger_setup/narrate/setup)
	..()
	if(QDELETED(src))
		return
	message = encode_html_emphasis(setup.narration)
	if(setup.to_player)
		isPersonal_orVis_orAud = 0
		isWarning = setup.scary
	else
		isPersonal_orVis_orAud = setup.audible ? 2 : 1
		if(setup.range <= 10)
			message_range = setup.range

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
