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
	EXPIRY_DECLARE(last_trigger)
	COOLDOWN_DECLARE(trigger_cooldown)
	var/isLoud = FALSE
	var/isNarrate = FALSE
	/// The setup questions set_vars() asks.
	var/setup_flow = /datum/prompt/text/event_trigger_setup/name

// ALLOW(init/INSTANCE_STATE): coordinates taken from where this instance is placed
/obj/effect/landmark/event_trigger/Initialize(mapload)
	. = ..()
	coordinates = "(X:[loc.x];Y:[loc.y];Z:[loc.z])"

/// The original creator and scalar answers remain attached to each native question.
/obj/effect/landmark/event_trigger/proc/set_vars(mob/M)
	if(setup_refusal(M))
		return
	var/list/state = list("stage" = "name", "narrate" = ispath(setup_flow, /datum/prompt/text/event_trigger_setup/narrate_name), "trigger_name" = null, "team" = FALSE, "loud" = FALSE, "repeat" = FALSE, "cooldown_seconds" = 0, "narration" = null, "to_player" = FALSE, "scary" = FALSE, "audible" = FALSE, "range" = 11)
	setup_step_checked(M, state, null, TRUE)

/// The flow checked the same rights before starting and before every later step.
/obj/effect/landmark/event_trigger/proc/setup_refusal(mob/M)
	if(QDELETED(M) || QDELETED(src))
		return "gone"
	if(!admin_can(M.client, 0) || !check_rights_for(M.client, R_FUN))
		return "no admin rights"
	return null

/// Keep the original unfinished-landmark cleanup, including a fault in any full step.
/obj/effect/landmark/event_trigger/proc/discard_setup()
	var/obj/effect/landmark/event_trigger/target = src
	qdel(target)

/obj/effect/landmark/event_trigger/proc/setup_step_checked(mob/M, list/state, answer, opening = FALSE)
	try
		if(!opening)
			state = state.Copy()
		setup_step(M, state, answer, opening)
	catch(var/exception/fault)
		try
			discard_setup()
		catch(var/exception/cleanup_fault)
			stack_trace("Event trigger setup cleanup: [cleanup_fault]")
		throw fault

/obj/effect/landmark/event_trigger/proc/setup_answered(datum/act/request/A)
	if(!A.answer)
		discard_setup()
		return
	setup_step_checked(A.request.answerer, A.request.captured, A.answer.value)

/obj/effect/landmark/event_trigger/proc/setup_step(mob/M, list/state, answer, opening)
	if(opening)
		setup_question(M, state)
		return
	switch(state["stage"])
		if("name")
			if(!answer)
				discard_setup()
				return
			state["trigger_name"] = answer
			state["stage"] = "team"
		if("team")
			state["team"] = answer == "Yes"
			state["stage"] = state["team"] ? "repeat" : "loud"
		if("loud")
			state["loud"] = answer == "Yes"
			state["stage"] = "repeat"
		if("repeat")
			state["repeat"] = answer == "Yes"
			if(state["repeat"])
				state["stage"] = "cooldown"
			else if(state["narrate"])
				state["stage"] = "narration"
			else
				apply_vars(M, state)
				return
		if("cooldown")
			state["cooldown_seconds"] = answer
			if(state["narrate"])
				state["stage"] = "narration"
			else
				apply_vars(M, state)
				return
		if("narration")
			state["narration"] = answer
			state["stage"] = "target"
		if("target")
			state["to_player"] = answer == "Player"
			state["stage"] = state["to_player"] ? "scary" : "mode"
		if("scary")
			state["scary"] = answer == "Big Red"
			apply_vars(M, state)
			return
		if("mode")
			state["audible"] = answer == "Audible"
			state["stage"] = "range"
		if("range")
			state["range"] = answer
			apply_vars(M, state)
			return
	setup_question(M, state)

/obj/effect/landmark/event_trigger/proc/setup_question(mob/M, list/state)
	switch(state["stage"])
		if("name")
			open_request(src, setup_flow, PROC_REF(setup_answered), answerer = M, captured = state)
		if("team")
			open_request(src, /datum/prompt/choice/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Teamwork", question = "Notify rest of team?", choices = list("No", "Yes"))
		if("loud")
			open_request(src, /datum/prompt/choice/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "bwoink", question = "Should it make a bwoink when triggered for YOU?", choices = list("No", "Yes"))
		if("repeat")
			open_request(src, /datum/prompt/choice/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Repetition", question = "Make it fire repeatedly?", choices = list("No", "Yes"))
		if("cooldown")
			open_request(src, /datum/prompt/number/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Cooldown", question = "Set cooldown in seconds. Minimum 5 seconds!", default = 60, min_value = 5)
		if("narration")
			open_request(src, /datum/prompt/text/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Message", question = "What should the automatic narration say?", default = "")
		if("target")
			open_request(src, /datum/prompt/choice/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Target", question = "Should it send directly to the player, or send to the turf?", choices = list("Player", "Turf"))
		if("scary")
			open_request(src, /datum/prompt/choice/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Scary Red", question = "Should it be a normal message or a big scary red text?", choices = list("Big Red", "Normal"))
		if("mode")
			open_request(src, /datum/prompt/choice/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Mode", question = "Should it be visible or audible?", choices = list("Visible", "Audible"))
		if("range")
			open_request(src, /datum/prompt/number/event_trigger_setup, PROC_REF(setup_answered), answerer = M, captured = state, title = "Range", question = "Give narration range! Input value over 10 to use world.view", default = 11, min_value = 0)

/datum/prompt/text/event_trigger_setup
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE
	max_len = MAX_MESSAGE_LEN

/datum/prompt/text/event_trigger_setup/normalize(given)
	return given

/datum/prompt/text/event_trigger_setup/recheck_extra()
	var/obj/effect/landmark/event_trigger/trigger = owner
	return trigger.setup_refusal(answerer)

/datum/prompt/text/event_trigger_setup/name
	title = "Naming"
	question = "Input Name for the trigger"
	default = "Event Trigger"

/datum/prompt/text/event_trigger_setup/narrate_name
	parent_type = /datum/prompt/text/event_trigger_setup/name

/datum/prompt/choice/event_trigger_setup
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE
	buttons = TRUE

/datum/prompt/choice/event_trigger_setup/refusal(given)
	return null

/datum/prompt/choice/event_trigger_setup/recheck_extra()
	var/obj/effect/landmark/event_trigger/trigger = owner
	return trigger.setup_refusal(answerer)

/datum/prompt/number/event_trigger_setup
	timeout = 0
	rights = R_FUN
	recheck_on_open = TRUE

/datum/prompt/number/event_trigger_setup/normalize(given)
	return isnum(given) ? given : null

/datum/prompt/number/event_trigger_setup/recheck_extra()
	var/obj/effect/landmark/event_trigger/trigger = owner
	return trigger.setup_refusal(answerer)

/obj/effect/landmark/event_trigger/proc/apply_vars(mob/M, list/setup)
	name = setup["trigger_name"]
	creator_ckey = M.ckey
	if(!GLOB.event_triggers[creator_ckey])
		GLOB.event_triggers[creator_ckey] = list()
	GLOB.event_triggers[creator_ckey] |= list(src)
	isTeamwork = setup["team"]
	isLoud = !isTeamwork && setup["loud"]
	isRepeating = setup["repeat"]
	if(isRepeating)
		cooldown = setup["cooldown_seconds"] SECONDS
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
	EXPIRY_STAMP(src, last_trigger, CLOCK_WORLD)
	COOLDOWN_START(src, trigger_cooldown, cooldown)

	if(!creator_ckey)	//For some reason, the user didn't have a ckey. Let's clean up
		consume(src)
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
			consume(src)
		return FALSE
	else
		return L

/obj/effect/landmark/event_trigger/auto_narrate
	var/message
	var/isPersonal_orVis_orAud = 0	//0 for personal, 1 for vis, 2 for aud
	var/message_range	//Leave at 0 for world.view
	var/isWarning = FALSE 	//For personal messages
	isNarrate = TRUE
	setup_flow = /datum/prompt/text/event_trigger_setup/narrate_name

/obj/effect/landmark/event_trigger/auto_narrate/Initialize(mapload)
	. = ..()
	message_range = world.view

/obj/effect/landmark/event_trigger/auto_narrate/apply_vars(mob/M, list/setup)
	..()
	if(QDELETED(src))
		return
	message = encode_html_emphasis(setup["narration"])
	if(setup["to_player"])
		isPersonal_orVis_orAud = 0
		isWarning = setup["scary"]
	else
		isPersonal_orVis_orAud = setup["audible"] ? 2 : 1
		if(setup["range"] <= 10)
			message_range = setup["range"]

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
		consume(src)
