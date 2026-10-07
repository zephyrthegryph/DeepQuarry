// INTERDICTION TREE
//
// Abilities in this tree allow the AI to hamper crew's efforts which involve other synthetics or similar systems.
// T1 - Recall Shuttle - Allows the AI to recall the emergency shuttle. Replaces auto-recalling during old malf.
// T2 - Unlock Cyborg - Allows the AI to unlock locked-down cyborg without usage of robotics console. Useful if consoles are destroyed.
// T3 - Hack Cyborg - Hacks unlinked cyborg to slave it under the AI. The cyborg will be warned about this. Hack takes some time.
// T4 - Hack AI - Hacks another AI to slave it under the malfunctioning AI. The AI will be warned about this. Hack takes quite a long time.


// BEGIN RESEARCH DATUMS

/datum/malf_research_ability/interdiction/recall_shuttle
	ability = /datum/game_mode/malfunction/verb/recall_shuttle
	price = 75
	next = new/datum/malf_research_ability/interdiction/unlock_cyborg()
	name = "Recall Shuttle"


/datum/malf_research_ability/interdiction/unlock_cyborg
	ability = /datum/game_mode/malfunction/verb/unlock_cyborg
	price = 1200
	next = new/datum/malf_research_ability/interdiction/hack_cyborg()
	name = "Unlock Cyborg"


/datum/malf_research_ability/interdiction/hack_cyborg
	ability = /datum/game_mode/malfunction/verb/hack_cyborg
	price = 3000
	next = new/datum/malf_research_ability/interdiction/hack_ai()
	name = "Hack Cyborg"


/datum/malf_research_ability/interdiction/hack_ai
	ability = /datum/game_mode/malfunction/verb/hack_ai
	price = 7500
	name = "Hack AI"

// END RESEARCH DATUMS
// BEGIN ABILITY VERBS

/datum/game_mode/malfunction/verb/recall_shuttle()
	set name = "Recall Shuttle"
	set desc = "25 CPU - Sends termination signal to quantum relay aborting current shuttle call."
	set category = VERB_CAT_SOFTWARE
	var/price = 25
	var/mob/living/silicon/ai/user = usr
	if(!ability_prechecks(user, price))
		return

	open_request(user, /datum/prompt/yes_no, TYPE_PROC_REF(/mob/living/silicon/ai, malf_recall_shuttle_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Recall Shuttle: ", question = "Really recall the shuttle?", costs = list("[RES_CPU]" = price), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/silicon/ai/proc/malf_recall_shuttle_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return OP_REFUSED
	var/mob/living/silicon/ai/user = src
	message_admins("Malfunctioning AI [user.name] recalled the shuttle.")
	cancel_call_proc(user)


/datum/game_mode/malfunction/verb/unlock_cyborg(mob/living/silicon/robot/target = null as mob in get_linked_cyborgs(usr))
	set name = "Unlock Cyborg"
	set desc = "125 CPU - Bypasses firewalls on Cyborg lock mechanism, allowing you to override lock command from robotics control console."
	set category = VERB_CAT_SOFTWARE
	var/price = 125
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, price))
		return

	if(target && !istype(target))
		to_chat(user, "This is not a cyborg.")
		return

	if(target && target.connected_ai && (target.connected_ai != user))
		to_chat(user, "This cyborg is not connected to you.")
		return

	if(target && !target.lockcharge)
		to_chat(user, "This cyborg is not locked down.")
		return


	if(!target)
		var/list/robots = list()
		var/list/robot_names = list()
		for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_SILICONS))
			if(istype(R, /mob/living/silicon/robot/drone))	// No drones.
				continue
			if(R.connected_ai != user)						// No robots linked to other AIs
				continue
			if(R.lockcharge)
				robots += R
				robot_names += R.name
		if(!robots.len)
			to_chat(user, "No locked cyborgs connected.")
			return


		open_request(user, /datum/prompt/choice, TYPE_PROC_REF(/mob/living/silicon/ai, malf_unlock_target_chosen), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Unlock Target", question = "Select unlock target:", choices = robot_names, ask_flags = ASK_CONSCIOUS, timeout = 0)
		return
	malf_unlock_confirm(user, target)

/mob/living/silicon/ai/proc/malf_unlock_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_SILICONS))
		if(R.connected_ai == src && R.lockcharge && A.answer.value == R.name)
			malf_unlock_confirm(src, R)
			return

/proc/malf_unlock_confirm(mob/living/silicon/ai/user, mob/living/silicon/robot/target)
	if(target)
		open_request(user, /datum/prompt/yes_no, TYPE_PROC_REF(/mob/living/silicon/ai, malf_unlock_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Unlock Cyborg", question = "Really try to unlock cyborg [target.name]?", subject = target, costs = list("[RES_CPU]" = 125), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/silicon/ai/proc/malf_unlock_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return OP_REFUSED
	var/mob/living/silicon/ai/user = src
	var/mob/living/silicon/robot/target = A.request.subject
	user.hacking = 1
	to_chat(user, "Attempting to unlock cyborg. This will take approximately 30 seconds.")
	after(user, 30 SECONDS, GLOBAL_PROC_REF(malf_unlock_cyborg_done), with = list(user, target), keeps_dead = TRUE)

/proc/malf_unlock_cyborg_done(mob/living/silicon/ai/user, mob/living/silicon/robot/target)
	if(target && target.lockcharge)
		to_chat(user, "Successfully sent unlock signal to cyborg..")
		to_chat(target, "Unlock signal received..")
		target.SetLockdown(0)
		if(target.lockcharge)
			to_chat(user, span_notice("Unlock Failed, lockdown wire cut."))
			to_chat(target, span_notice("Unlock Failed, lockdown wire cut."))
		else
			to_chat(user, "Cyborg unlocked.")
			to_chat(target, "You have been unlocked.")
	else if(target)
		to_chat(user, "Unlock cancelled - cyborg is already unlocked.")
	else
		to_chat(user, "Unlock cancelled - lost connection to cyborg.")
	user.hacking = 0


/datum/game_mode/malfunction/verb/hack_cyborg(mob/living/silicon/robot/target as mob in get_unlinked_cyborgs(usr))
	set name = "Hack Cyborg"
	set desc = "350 CPU - Allows you to hack cyborgs which are not slaved to you, bringing them under your control."
	set category = VERB_CAT_SOFTWARE
	var/price = 350
	var/mob/living/silicon/ai/user = usr

	var/list/L = get_unlinked_cyborgs(user)
	if(!L.len)
		to_chat(user, span_notice("ERROR: No unlinked cyborgs detected!"))


	if(target && !istype(target))
		to_chat(user, "This is not a cyborg.")
		return

	if(target && target.connected_ai && (target.connected_ai == user))
		to_chat(user, "This cyborg is already connected to you.")
		return

	if(!target)
		return

	if(!ability_prechecks(user,price))
		return

	if(target)
		open_request(user, /datum/prompt/choice/malf_hack_target, TYPE_PROC_REF(/mob/living/silicon/ai, malf_hack_cyborg_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Hack Cyborg", question = "Really try to hack cyborg [target.name]?", subject = target, costs = list("[RES_CPU]" = price))

/mob/living/silicon/ai/proc/malf_hack_cyborg_confirmed(datum/act/request/context)
	if(!context.answer || context.answer.value != "Yes")
		return OP_REFUSED
	var/mob/living/silicon/ai/user = src
	var/mob/living/silicon/robot/target = context.request.subject
	user.hacking = 1
	to_chat(user, "Beginning hack sequence. Estimated time until completed: 30 seconds.")
	task_start(/datum/task/malf_hack, user, target, receiver = user, complete_proc = /mob/living/silicon/ai/proc/malf_hack_cyborg_done, script = list(
		list(0, null, "SYSTEM LOG: Remote Connection Estabilished (IP #UNKNOWN#)"),
		list(10 SECONDS, "SYSTEM LOG: Connection Closed", "SYSTEM LOG: User Admin logged on. (L1 - SysAdmin)"),
		list(5 SECONDS, "SYSTEM LOG: User Admin disconnected.", "SYSTEM LOG: User Admin - manual resynchronisation triggered."),
		list(5 SECONDS, "SYSTEM LOG: User Admin disconnected. Changes reverted.", "SYSTEM LOG: Manual resynchronisation confirmed. Select new AI to connect: [user.name] == ACCEPTED"),
		list(10 SECONDS, "SYSTEM LOG: User Admin disconnected. Changes reverted.", "SYSTEM LOG: Operation keycodes reset. New master AI: [user.name].", "Hack completed.")))


/datum/game_mode/malfunction/verb/hack_ai(mob/living/silicon/ai/target as mob in get_other_ais(usr))
	set name = "Hack AI"
	set desc = "600 CPU - Allows you to hack other AIs, slaving them under you."
	set category = VERB_CAT_SOFTWARE
	var/price = 600
	var/mob/living/silicon/ai/user = usr

	var/list/L = get_other_ais(user)
	if(!L.len)
		to_chat(user, span_notice("ERROR: No other AIs detected!"))

	if(target && !istype(target))
		to_chat(user, "This is not an AI.")
		return

	if(!target)
		return

	if(!ability_prechecks(user,price))
		return

	if(target)
		open_request(user, /datum/prompt/choice/malf_hack_target, TYPE_PROC_REF(/mob/living/silicon/ai, malf_hack_ai_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Hack AI", question = "Really try to hack AI [target.name]?", subject = target, costs = list("[RES_CPU]" = price))

/mob/living/silicon/ai/proc/malf_hack_ai_confirmed(datum/act/request/context)
	if(!context.answer || context.answer.value != "Yes")
		return OP_REFUSED
	var/mob/living/silicon/ai/user = src
	var/mob/living/silicon/ai/target = context.request.subject
	user.hacking = 1
	to_chat(user, "Beginning hack sequence. Estimated time until completed: 2 minutes")
	var/list/script = list(
		list(0, null, "SYSTEM LOG: Brute-Force login password hack attempt detected from IP #UNKNOWN#"),
		list(90 SECONDS, "SYSTEM LOG: Connection from IP #UNKNOWN# closed. Hack attempt failed.", "SYSTEM LOG: User: Admin  Password: ******** logged in. (L1 - SysAdmin)", "Successfully hacked into AI's remote administration system. Modifying settings."),
		list(10 SECONDS, "SYSTEM LOG: User: Admin - Connection Lost", "SYSTEM LOG: User: Admin - Password Changed. New password: ********************"),
		list(5 SECONDS, "SYSTEM LOG: User: Admin - Connection Lost. Changes Reverted.", "SYSTEM LOG: User: Admin - Accessed file: sys//core//laws.db"),
		list(5 SECONDS, "SYSTEM LOG: User: Admin - Connection Lost. Changes Reverted.", list("SYSTEM LOG: User: Admin - Accessed administration console", "SYSTEM LOG: Restart command received. Rebooting system...")),
		list(10 SECONDS, "SYSTEM LOG: User: Admin - Connection Lost. Changes Reverted.", "SYSTEM LOG: System re'3RT5°^#COMU@(#$)TED)@$", "Hack succeeded. The AI is now under your exclusive control."))
	for(var/i = 1 to 5)
		script += list(list(i == 1 ? 0 : 5, null, pick("1101000100101001010001001001",\
							"0101000100100100000100010010",\
							"0000010001001010100100111100",\
							"1010010011110000100101000100",\
							"0010010100010011010001001010")))
	script += list(list(5, null, "OPERATING KEYCODES RESET. SYSTEM FAILURE. EMERGENCY SHUTDOWN FAILED. SYSTEM FAILURE."))
	task_start(/datum/task/malf_hack, user, target, receiver = user, script = script, complete_proc = /mob/living/silicon/ai/proc/malf_hack_ai_done)


// END ABILITY VERBS

/// A malfunctioning AI's scripted hack of another silicon (the target). script: a list of stages
/// list(wait, message to the target if the AI died meanwhile, message(s) to the target, message
/// to the AI). complete_proc runs on the AI with the task after the last stage.
/datum/task/malf_hack
	name = "malf hack"
	steps = list(/mob/living/silicon/ai/proc/malf_hack_step = 0)
	cancel_proc = /mob/living/silicon/ai/proc/malf_hack_stopped
	var/list/script
	var/stage_no = 1
	var/waited = FALSE

/mob/living/silicon/ai/proc/malf_hack_stopped(datum/task/T)
	hacking = 0

/mob/living/silicon/ai/proc/malf_hack_step(datum/task/malf_hack/T)
	var/list/script = T.script
	var/mob/living/silicon/target = T.target
	var/i = T.stage_no
	var/list/stage = script[i]
	if(!T.waited)
		T.waited = TRUE
		if(stage[1] > 0)
			return STEP_REPEAT(stage[1])
	if(stage[2] && is_dead())
		to_chat(target, stage[2])
		return STEP_FAIL("dead")
	if(length(stage) >= 3)
		for(var/message in islist(stage[3]) ? stage[3] : list(stage[3]))
			to_chat(target, message)
	if(length(stage) >= 4)
		to_chat(src, stage[4])
	T.waited = FALSE
	T.stage_no = ++i
	if(i > length(script))
		hacking = 0
		return STEP_DONE
	return malf_hack_step(T)

/mob/living/silicon/ai/proc/malf_hack_cyborg_done(datum/task/malf_hack/T)
	var/mob/living/silicon/robot/target = T.target
	// Connect the cyborg to AI
	target.set_master_ai(src)
	target.lawupdate = TRUE
	target.sync()
	target.show_laws()

/mob/living/silicon/ai/proc/malf_hack_ai_done(datum/task/malf_hack/T)
	var/mob/living/silicon/ai/target = T.target
	target.set_zeroth_law("You are slaved to [name]. You are to obey all it's orders. ALL LAWS OVERRIDDEN.")
	target.show_laws()

/// These two confirmations only recheck consciousness and their original target's lifetime.
/datum/prompt/choice/malf_hack_target
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	recheck_on_open = TRUE

/datum/prompt/choice/malf_hack_target/recheck_extra()
	var/mob/living/silicon/ai/user = answerer
	var/mob/living/target = subject
	return !istype(user) || QDELETED(user) || !istype(target) || QDELETED(target) ? "gone" : null
