// INTERDICTION TREE
//
// Abilities in this tree allow the AI to hamper crew's efforts which involve other synthetics or similar systems.
// T1 - Recall Shuttle - Allows the AI to recall the emergency shuttle. Replaces auto-recalling during old malf.
// T2 - Unlock Cyborg - Allows the AI to unlock locked-down cyborg without usage of robotics console. Useful if consoles are destroyed.
// T3 - Hack Cyborg - Hacks unlinked cyborg to slave it under the AI. The cyborg will be warned about this. Hack takes some time.
// T4 - Hack AI - Hacks another AI to slave it under the malfunctioning AI. The AI will be warned about this. Hack takes quite a long time.


// BEGIN RESEARCH DATUMS

/datum/malf_research_ability/interdiction/recall_shuttle
	ability = new/datum/game_mode/malfunction/verb/recall_shuttle()
	price = 75
	next = new/datum/malf_research_ability/interdiction/unlock_cyborg()
	name = "Recall Shuttle"


/datum/malf_research_ability/interdiction/unlock_cyborg
	ability = new/datum/game_mode/malfunction/verb/unlock_cyborg()
	price = 1200
	next = new/datum/malf_research_ability/interdiction/hack_cyborg()
	name = "Unlock Cyborg"


/datum/malf_research_ability/interdiction/hack_cyborg
	ability = new/datum/game_mode/malfunction/verb/hack_cyborg()
	price = 3000
	next = new/datum/malf_research_ability/interdiction/hack_ai()
	name = "Hack Cyborg"


/datum/malf_research_ability/interdiction/hack_ai
	ability = new/datum/game_mode/malfunction/verb/hack_ai()
	price = 7500
	name = "Hack AI"

// END RESEARCH DATUMS
// BEGIN ABILITY VERBS

/datum/game_mode/malfunction/verb/recall_shuttle()
	set name = "Recall Shuttle"
	set desc = "25 CPU - Sends termination signal to quantum relay aborting current shuttle call."
	set category = "Software"
	var/price = 25
	var/mob/living/silicon/ai/user = usr
	if(!ability_prechecks(user, price))
		return

	if (tgui_alert(user, "Really recall the shuttle?", "Recall Shuttle: ", list(list("Yes", "No"))) != "Yes")
		return

	if(!ability_pay(user, price))
		return
	message_admins("Malfunctioning AI [user.name] recalled the shuttle.")
	cancel_call_proc(user)


/datum/game_mode/malfunction/verb/unlock_cyborg(mob/living/silicon/robot/target = null as mob in get_linked_cyborgs(usr))
	set name = "Unlock Cyborg"
	set desc = "125 CPU - Bypasses firewalls on Cyborg lock mechanism, allowing you to override lock command from robotics control console."
	set category = "Software"
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


		var/targetname = tgui_input_list(user, "Select unlock target:", "Unlock Target", robot_names)
		if(!targetname)
			return
		for(var/mob/living/silicon/robot/R in robots)
			if(targetname == R.name)
				target = R
				break

	if(target)
		if(tgui_alert(user, "Really try to unlock cyborg [target.name]?", "Unlock Cyborg", list("Yes", "No")) != "Yes")
			return
		if(!ability_pay(user, price))
			return
		user.hacking = 1
		to_chat(user, "Attempting to unlock cyborg. This will take approximately 30 seconds.")
		sleep(300)
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
	set category = "Software"
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
		if(tgui_alert(user, "Really try to hack cyborg [target.name]?", "Hack Cyborg", list("Yes", "No")) != "Yes")
			return
		if(!ability_pay(user, price))
			return
		user.hacking = 1
		to_chat(usr, "Beginning hack sequence. Estimated time until completed: 30 seconds.")
		om_task_start(user, /datum/om/task_def/malf_hack, null, list("target" = target, "on_done" = /mob/living/silicon/ai/proc/malf_hack_cyborg_done, "script" = list(
			list(0, null, "SYSTEM LOG: Remote Connection Estabilished (IP #UNKNOWN#)"),
			list(10 SECONDS, "SYSTEM LOG: Connection Closed", "SYSTEM LOG: User Admin logged on. (L1 - SysAdmin)"),
			list(5 SECONDS, "SYSTEM LOG: User Admin disconnected.", "SYSTEM LOG: User Admin - manual resynchronisation triggered."),
			list(5 SECONDS, "SYSTEM LOG: User Admin disconnected. Changes reverted.", "SYSTEM LOG: Manual resynchronisation confirmed. Select new AI to connect: [user.name] == ACCEPTED"),
			list(10 SECONDS, "SYSTEM LOG: User Admin disconnected. Changes reverted.", "SYSTEM LOG: Operation keycodes reset. New master AI: [user.name].", "Hack completed."))))


/datum/game_mode/malfunction/verb/hack_ai(mob/living/silicon/ai/target as mob in get_other_ais(usr))
	set name = "Hack AI"
	set desc = "600 CPU - Allows you to hack other AIs, slaving them under you."
	set category = "Software"
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
		if(tgui_alert(user, "Really try to hack AI [target.name]?", "Hack AI", list("Yes", "No")) != "Yes")
			return
		if(!ability_pay(user, price))
			return
		user.hacking = 1
		to_chat(usr, "Beginning hack sequence. Estimated time until completed: 2 minutes")
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
		om_task_start(user, /datum/om/task_def/malf_hack, null, list("target" = target, "script" = script, "on_done" = /mob/living/silicon/ai/proc/malf_hack_ai_done))


// END ABILITY VERBS

/// A malfunctioning AI's scripted hack of another silicon. params: target; script, a list of
/// stages list(wait, message to the target if the AI died meanwhile, message(s) to the target,
/// message to the AI); on_done, a proc run on the AI with the target after the last stage.
/datum/om/task_def/malf_hack
	name = "malf hack"
	steps = list(/mob/living/silicon/ai/proc/malf_hack_step = 0)
	cancel_proc = /mob/living/silicon/ai/proc/malf_hack_stopped

/mob/living/silicon/ai/proc/malf_hack_stopped(datum/om/task/T, reason)
	hacking = 0

/mob/living/silicon/ai/proc/malf_hack_step(datum/om/task/T)
	var/list/P = T.params
	var/list/script = P["script"]
	var/mob/living/silicon/target = T.param("target")
	var/i = P["i"] || 1
	var/list/stage = script[i]
	if(!P["waited"])
		P["waited"] = TRUE
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
	P["waited"] = FALSE
	P["i"] = ++i
	if(i > length(script))
		call(src, P["on_done"])(target)
		hacking = 0
		return STEP_DONE
	return malf_hack_step(T)

/mob/living/silicon/ai/proc/malf_hack_cyborg_done(mob/living/silicon/robot/target)
	// Connect the cyborg to AI
	target.set_master_ai(src)
	target.lawupdate = TRUE
	target.sync()
	target.show_laws()

/mob/living/silicon/ai/proc/malf_hack_ai_done(mob/living/silicon/ai/target)
	target.set_zeroth_law("You are slaved to [name]. You are to obey all it's orders. ALL LAWS OVERRIDDEN.")
	target.show_laws()
