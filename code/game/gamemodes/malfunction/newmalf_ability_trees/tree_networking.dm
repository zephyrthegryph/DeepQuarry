// NETWORKING TREE
//
// Abilities in this tree are oriented around giving the AI more control of normally uncontrollable systems.
// T1 - Basic Encryption Hack - Allows hacking of APCs. Hacked APCs can be controlled even when AI Control is cut and give exclusive control to the AI and linked cyborgs.
// T2 - Advanced Encryption Hack - Allows the AI to send fake CentCom message. Has high chance of failing.
// T3 - Elite Encryption Hack - Allows the AI to change alert levels. Has high chance of failing.
// T4 - System Override - Allows the AI to rapidly hack remaining APCs. When completed, grants access to the self destruct nuclear warhead.


// BEGIN RESEARCH DATUMS

/datum/malf_research_ability/networking/basic_hack
	ability = /datum/game_mode/malfunction/verb/basic_encryption_hack
	price = 25
	next = new/datum/malf_research_ability/networking/advanced_hack()
	name = "Basic Encryption Hack"


/datum/malf_research_ability/networking/advanced_hack
	ability = /datum/game_mode/malfunction/verb/advanced_encryption_hack
	price = 400
	next = new/datum/malf_research_ability/networking/elite_hack()
	name = "Advanced Encryption Hack"


/datum/malf_research_ability/networking/elite_hack
	ability = /datum/game_mode/malfunction/verb/elite_encryption_hack
	price = 1000
	next = new/datum/malf_research_ability/networking/system_override()
	name = "Elite Encryption Hack"


/datum/malf_research_ability/networking/system_override
	ability = /datum/game_mode/malfunction/verb/system_override
	price = 2750
	name = "System Override"

// END RESEARCH DATUMS
// BEGIN ABILITY VERBS

/datum/game_mode/malfunction/verb/basic_encryption_hack(obj/machinery/power/apc/A as obj in get_unhacked_apcs(src))
	set category = VERB_CAT_SOFTWARE
	set name = "Basic Encryption Hack"
	set desc = "10 CPU - Basic encryption hack that allows you to overtake APCs on the station."
	var/price = 10
	var/mob/living/silicon/ai/user = usr

	if(!A)
		return

	if(!istype(A))
		to_chat(user, "This is not an APC!")
		return

	if(A)
		if(A.hacker && A.hacker == user)
			to_chat(user, "You already control this APC!")
			return
		else if(A.aidisabled)
			to_chat(user, span_notice("Unable to connect to APC. Please verify wire connection and try again."))
			return
	else
		return

	if(!ability_prechecks(user, price) || !res_spend(user, RES_CPU, price, actor = user))
		return

	user.hacking = 1
	to_chat(user, "Beginning APC system override...")
	after(user, 30 SECONDS, GLOBAL_PROC_REF(to_chat), with = list(user, "APC hack completed. Uploading modified operation software.."))
	after(user, 50 SECONDS, GLOBAL_PROC_REF(to_chat), with = list(user, "Restarting APC to apply changes.."))
	after(user, 60 SECONDS, GLOBAL_PROC_REF(malf_apc_hack_done), with = list(user, REF(A)))

/proc/malf_apc_hack_done(mob/living/silicon/ai/user, apc_ref)
	var/obj/machinery/power/apc/A = locate(apc_ref)
	if(istype(A))
		A.ai_hack(user)
		if(A.hacker == user)
			to_chat(user, "Hack successful. You now have full control over the APC.")
		else
			to_chat(user, span_notice("Hack failed. Connection to APC has been lost. Please verify wire connection and try again."))
	else
		to_chat(user, span_notice("Hack failed. Unable to locate APC. Please verify the APC still exists."))
	user.hacking = 0


/datum/game_mode/malfunction/verb/advanced_encryption_hack()
	set category = VERB_CAT_SOFTWARE
	set name = "Advanced Encrypthion Hack"
	set desc = "75 CPU - Attempts to bypass encryption on the Command Quantum Relay, giving you ability to fake legitimate messages. Has chance of failing."
	var/price = 75
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, price))
		return

	open_request(user, /datum/prompt/text/malf_encryption_message, TYPE_PROC_REF(/mob/living/silicon/ai, malf_encryption_hack_titled), answerer = user, question = "Select message title: ")

/mob/living/silicon/ai/proc/malf_encryption_hack_titled(datum/act/request/context)
	if(!context.answer)
		return
	open_request(src, /datum/prompt/text/malf_encryption_message, PROC_REF(malf_encryption_hack_written), answerer = src, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), question = "Select message text: ", message_title = context.answer.answer_value, costs = list("[RES_CPU]" = 75))

/mob/living/silicon/ai/proc/malf_encryption_hack_written(datum/act/request/context)
	if(!context.answer)
		return OP_REFUSED
	var/datum/prompt/text/malf_encryption_message/ask = context.answer
	var/mob/living/silicon/ai/user = src
	var/title = ask.message_title
	var/text = ask.answer_value
	if(!title || !text)
		to_chat(user, "Hack Aborted")
		return OP_REFUSED

	if(prob(60) && user.hack_can_fail)
		to_chat(user, "Hack Failed.")
		if(prob(10))
			user.hack_fails ++
			announce_hack_failure(user, "quantum message relay")
		return

	var/datum/announcement/priority/command/AN = new/datum/announcement/priority/command()
	AN.title = title
	AN.Announce(text)


/datum/game_mode/malfunction/verb/elite_encryption_hack()
	set category = VERB_CAT_SOFTWARE
	set name = "Elite Encryption Hack"
	set desc = "200 CPU - Allows you to hack station's ALERTCON system, changing alert level. Has high chance of failijng."
	var/price = 200
	var/mob/living/silicon/ai/user = usr
	if(!ability_prechecks(user, price))
		return

	open_request(user, /datum/prompt/choice/malf_alert_level, TYPE_PROC_REF(/mob/living/silicon/ai, malf_alert_hack_chosen), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Alert Level", question = "Select new alert level:", choices = list("green", "yellow", "violet", "orange", "blue", "red", "delta"), costs = list("[RES_CPU]" = price))

/mob/living/silicon/ai/proc/malf_alert_hack_chosen(datum/act/request/A)
	if(!A.answer)
		return OP_REFUSED
	var/mob/living/silicon/ai/user = src
	var/alert_target = A.answer.answer_value
	if(!alert_target)
		to_chat(user, "Hack Aborted")
		return OP_REFUSED

	if(prob(75) && user.hack_can_fail)
		to_chat(user, "Hack Failed.")
		if(prob(20))
			user.hack_fails ++
			announce_hack_failure(user, "alert control system")
		return
	set_security_level(alert_target)


/datum/game_mode/malfunction/verb/system_override()
	set category = VERB_CAT_SOFTWARE
	set name = "System Override"
	set desc = "500 CPU - Begins hacking station's primary firewall, quickly overtaking remaining APC systems. When completed grants access to station's self-destruct mechanism. Network administrators will probably notice this."
	var/mob/living/silicon/ai/user = usr
	open_request(user, /datum/prompt/choice/malf_system_override, TYPE_PROC_REF(/mob/living/silicon/ai, malf_system_override_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), costs = list("[RES_CPU]" = 500))

/mob/living/silicon/ai/proc/malf_system_override_confirmed(datum/act/request/context)
	if(!context.answer || context.answer.answer_value != "Yes")
		return OP_REFUSED
	var/mob/living/silicon/ai/user = src
	if(user.system_override)
		to_chat(user, "You already started the system override sequence.")
		return OP_REFUSED
	var/list/remaining_apcs = list()
	for(var/obj/machinery/power/apc/A in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(!(A.z in using_map.station_levels)) 		// Only station APCs
			continue
		if(A.hacker == user || A.aidisabled) 		// This one is already hacked, or AI control is disabled on it.
			continue
		remaining_apcs += A

	var/duration = (remaining_apcs.len * 100)		// Calculates duration for announcing system
	if(duration > 3000)								// Two types of announcements. Short hacks trigger immediate warnings. Long hacks are more "progressive".
		// Network monitoring closes in over the hack, on the AI's clock.
		for(var/stage in 1 to 4)
			after(user, stage * duration / 5, TYPE_PROC_REF(/mob/living/silicon/ai, network_trace_announce), with = list(stage))
	else
		GLOB.command_announcement.Announce("We have detected a strong brute-force attack on your firewall which seems to be originating from your AI system. It already controls almost the whole network, and the only thing that's preventing it from accessing the self-destruct is this firewall. You don't have much time before it succeeds.", "Network Monitoring")
	to_chat(user, "## BEGINNING SYSTEM OVERRIDE.")
	to_chat(user, "## ESTIMATED DURATION: [round((duration+300)/600)] MINUTES")
	user.hacking = 1
	user.system_override = 1
	// Now actually begin the hack. Each APC takes 10 seconds.
	after(user, 10 SECONDS, GLOBAL_PROC_REF(malf_override_next_apc), with = list(user, shuffle(remaining_apcs)))

/// Overrides the next APC every 10 seconds; the firewall falls 30 seconds after the last.
/proc/malf_override_next_apc(mob/living/silicon/ai/user, list/remaining_apcs)
	if(user.stat == DEAD)
		return
	if(length(remaining_apcs))
		var/obj/machinery/power/apc/A = remaining_apcs[1]
		remaining_apcs.Cut(1, 2)
		if(istype(A) && !QDELETED(A) && !A.aidisabled)
			A.ai_hack(user)
			if(A.hacker == user)
				to_chat(user, "## OVERRIDDEN: [A.name]")
		if(length(remaining_apcs))
			after(user, 10 SECONDS, GLOBAL_PROC_REF(malf_override_next_apc), with = list(user, remaining_apcs))
			return
	to_chat(user, "## REACHABLE APC SYSTEMS OVERTAKEN. BYPASSING PRIMARY FIREWALL.")
	after(user, 30 SECONDS, GLOBAL_PROC_REF(malf_override_finish), with = list(user))

/proc/malf_override_finish(mob/living/silicon/ai/user)
	// Hack all APCs, including those built during hack sequence.
	for(var/obj/machinery/power/apc/A in REGISTRY_MEMBERS(REGISTRY_APCS))
		if((!A.hacker || A.hacker != user) && !A.aidisabled && (A.z in using_map.station_levels))
			A.ai_hack(user)

	to_chat(user, "## PRIMARY FIREWALL BYPASSED. YOU NOW HAVE FULL SYSTEM CONTROL.")
	GLOB.command_announcement.Announce("Our system administrators just reported that we've been locked out from your control network. Whoever did this now has full access to the station's systems.", "Network Administration Center")
	user.hack_can_fail = 0
	user.hacking = 0
	user.system_override = 2
	// Granted by the AI's malf research (the AI itself if it has none).
	grant(user, granted_verb(/datum/game_mode/malfunction/verb/ai_destroy_station), user.research || user)


// END ABILITY VERBS

/// One of network monitoring's announcements while a malfunctioning AI overrides the station.
/mob/living/silicon/ai/proc/network_trace_announce(stage)
	if(stat == DEAD)
		return
	var/list/messages = list(
		"Caution, [station_name()]. We have detected abnormal behaviour in your network. It seems someone is trying to hack your electronic systems. We will update you when we have more information.",
		"We started tracing the intruder. Whoever is doing this, they seem to be on the station itself. We suggest checking all network control terminals. We will keep you updated on the situation.",
		"This is highly abnormal and somewhat concerning. The intruder is too fast, he is evading our traces. No man could be this fast...",
		"We have traced the intrude#, it seem& t( e yo3r AI s7stem, it &# *#ck@ng th$ sel$ destru$t mechani&m, stop i# bef*@!)$#&&@@  <CONNECTION LOST>")
	GLOB.command_announcement.Announce(messages[stage], "Network Monitoring")

/datum/prompt/text/malf_encryption_message
	timeout = 0
	recheck_on_open = TRUE
	ask_flags = ASK_CONSCIOUS
	var/message_title

/datum/prompt/text/malf_encryption_message/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/malf_alert_level
	timeout = 0
	recheck_on_open = TRUE
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/malf_system_override
	title = "System Override:"
	question = "Begin system override? This cannot be stopped once started. The network administrators will probably notice this."
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	recheck_on_open = TRUE

/datum/prompt/choice/malf_system_override/recheck_extra()
	var/mob/living/silicon/ai/user = answerer
	if(!istype(user) || QDELETED(user))
		return "gone"
	return null
