// Verb: ai_select_hardware()
// Parameters: None
// Description: Allows AI to select it's hardware module.
/datum/game_mode/malfunction/verb/ai_select_hardware()
	set category = VERB_CAT_HARDWARE
	set name = "Select Hardware"
	set desc = "Allows you to select hardware piece to install"
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, 0, 1))
		return

	if(user.hardware)
		to_chat(user, "You have already selected your hardware.")
		return

	var/hardware_list = list()
	for(var/H in typesof(/datum/malf_hardware))
		var/datum/malf_hardware/HW = new H
		hardware_list += HW

	var/possible_choices = list()
	for(var/datum/malf_hardware/H in hardware_list)
		possible_choices += H.name

	open_request(user, /datum/prompt/choice, TYPE_PROC_REF(/mob/living/silicon/ai, malf_hardware_chosen), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Hardware Choice", question = "Select desired hardware. You may only choose one hardware piece!: ", choices = possible_choices, ask_flags = ASK_CONSCIOUS, timeout = 0)

// ---- what a malfunctioning AI's abilities cost ----
//
// An ability that asks first (a confirmation, a pick) opens a plain request with `costs = list(RES_CPU = price)`: the AI is not asked when it
// cannot pay, its CPU is set aside when it answers yes (or picks), and spent only when the ability went through (the handler did not return
// OP_REFUSED). valid = malf_able() re-checks the rest of ability_prechecks() when the answer arrives (busy hacking, on backup power).

MSG_DEF_SELF(malf/cpu_short, "You do not have enough CPU power stored. Please wait a moment.")
MSG_DEF_SELF(malf/cpu_storage, "Your CPU storage is not large enough to use this ability. Hack more APCs to continue.")

/// RES_CPU: a malfunctioning AI's stored CPU time (its research datum).
/datum/resource/cpu
	res_id = RES_CPU
	name = "CPU"

/datum/resource/cpu/available(datum/act/op/A)
	var/mob/living/silicon/ai/AI = A.actor
	if(!istype(AI) || !AI.research)
		return 0
	return AI.research.stored_cpu

/datum/resource/cpu/refusal(datum/act/op/A, n)
	var/mob/living/silicon/ai/AI = A.actor
	if(istype(AI) && AI.research && AI.research.max_cpu < n)
		return /datum/msg/malf/cpu_storage
	return /datum/msg/malf/cpu_short

/datum/resource/cpu/commit(datum/reservation/R)
	var/mob/living/silicon/ai/AI = R.actor
	if(!istype(AI) || !AI.research || AI.research.stored_cpu < R.amount)
		return OP_FAILED
	AI.research.stored_cpu -= R.amount
	return OP_OK

/// The AI can still use an ability when its answer arrives: it malfunctions, has its research, and is neither hacking nor on backup power. Reads only.
/mob/living/silicon/ai/proc/malf_able(datum/request/R)
	return malfunctioning && research && !hacking && !APU_power

/// malf_able() for an ability that works while the AI is busy or on backup power (the core self-destruct).
/mob/living/silicon/ai/proc/malf_able_overridden(datum/request/R)
	return malfunctioning && research

/// The hardware confirmation carries the piece the AI picked.
/datum/prompt/yes_no/malf_hardware
	title = "Hardware selection"
	ask_flags = ASK_CONSCIOUS
	timeout = 0
	/// The hardware type picked.
	var/hardware_type

/mob/living/silicon/ai/proc/malf_hardware_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/silicon/ai/user = src
	var/datum/malf_hardware/C
	for(var/H in typesof(/datum/malf_hardware))
		var/datum/malf_hardware/HW = new H
		if(HW.name == A.answer.answer_value)
			C = HW
			break
	if(!C)
		to_chat(user, "This hardware does not exist! Probably a bug in game. Please report this.")
		return
	if(!C.desc)
		log_world("## ERROR Hardware without description: [C]")
		return
	open_request(user, /datum/prompt/yes_no/malf_hardware, TYPE_PROC_REF(/mob/living/silicon/ai, malf_hardware_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), question = "[C.desc] - Is this what you want?", hardware_type = C.type)

/mob/living/silicon/ai/proc/malf_hardware_confirmed(datum/act/request/A)
	var/mob/living/silicon/ai/user = src
	var/datum/prompt/yes_no/malf_hardware/ask = A.answer
	if(!ask || !ask.answer_value)
		to_chat(user, "Selection cancelled. Use command again to select")
		return
	if(user.hardware)
		to_chat(user, "You have already selected your hardware.")
		return
	var/datum/malf_hardware/C = new ask.hardware_type
	rel_set(C, nameof(C.owner), user)
	C.install()

// Verb: ai_help()
// Parameters: None
// Descriptions: Opens help file and displays it to the AI.
/datum/game_mode/malfunction/verb/ai_help()
	set category = VERB_CAT_HARDWARE
	set name = "Display Help"
	set desc = "Opens help window with overview of available hardware, software and other important information."
	var/mob/living/silicon/ai/user = usr

	var/help = file2text('html/malf_ai.html')
	if(!help)
		help = "Error loading help (file /html/malf_ai.html is probably missing). Please report this to server administration staff."

	// structured TGUI AdminReport.
	dq_admin_report_html(user, "Malf AI Help", help)


// Verb: ai_select_research()
// Parameters: None
// Description: Allows AI to select it's next research priority.
/datum/game_mode/malfunction/verb/ai_select_research()
	set category = VERB_CAT_HARDWARE
	set name = "Select Research"
	set desc = "Allows you to select your next research target."
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, 0, 1))
		return

	var/datum/malf_research/res = user.research
	open_request(user, /datum/prompt/choice/malf_research_target, TYPE_PROC_REF(/mob/living/silicon/ai, malf_research_chosen), answerer = user, choices = res.available_abilities?.Copy())

/mob/living/silicon/ai/proc/malf_research_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/mob/living/silicon/ai/user = src
	var/datum/malf_research_ability/tar = context.answer.answer_value
	var/datum/malf_research/res = user.research
	rel_set(res, nameof(res.focus_static), tar)
	to_chat(user, "Research set: [tar.name]")

// HELPER PROCS
// Proc: ability_prechecks()
// Parameters 2 - (user - User which used this ability check_price - If different than 0 checks for ability CPU price too. Does NOT use the CPU time!)
// Description: This is pre-check proc used to determine if the AI can use the ability.
/proc/ability_prechecks(mob/living/silicon/ai/user = null, check_price = 0, override = 0)
	if(!user)
		return 0
	if(!istype(user))
		to_chat(user, "GAME ERROR: You tried to use ability that is only available for malfunctioning AIs, but you are not AI! Please report this.")
		return 0
	if(!user.malfunctioning)
		to_chat(user, "GAME ERROR: You tried to use ability that is only available for malfunctioning AIs, but you are not malfunctioning. Please report this.")
		return 0
	if(!user.research)
		to_chat(user, "GAME ERROR: No research datum detected. Please report this.")
		return 0
	if(user.research.max_cpu < check_price)
		to_chat(user, "Your CPU storage is not large enough to use this ability. Hack more APCs to continue.")
		return 0
	if(user.research.stored_cpu < check_price)
		to_chat(user, "You do not have enough CPU power stored. Please wait a moment.")
		return 0
	if(user.hacking && !override)
		to_chat(user, "Your system is busy processing another task. Please wait until completion.")
		return 0
	if(user.APU_power && !override)
		to_chat(user, "Low power. Unable to proceed.")
		return 0
	return 1

// Proc: announce_hack_failure()
// Parameters 2 - (user - hacking user, text - Used in alert text creation)
// Description: Uses up certain amount of CPU power. Returns 1 on success, 0 on failure.
/proc/announce_hack_failure(mob/living/silicon/ai/user = null, text)
	if(!user || !text)
		return 0
	var/fulltext = ""
	switch(user.hack_fails)
		if(1)
			fulltext = "We have detected a hack attempt into your [text]. The intruder failed to access anything of importance, but disconnected before we could complete our traces."
		if(2)
			fulltext = "We have detected another hack attempt. It was targeting [text]. The intruder almost gained control of the system, so we had to disconnect them. We partially finished our trace and it seems to be originating either from the station, or its immediate vicinity."
		if(3)
			fulltext = "Another hack attempt has been detected, this time targeting [text]. We are certain the intruder entered the network via a terminal located somewhere on the station."
		if(4)
			fulltext = "We have finished our traces and it seems the recent hack attempts are originating from your AI system. We recommend investigation."
		else
			fulltext = "Another hack attempt has been detected, targeting [text]. The source still seems to be your AI system."

	GLOB.command_announcement.Announce(fulltext)

// Proc: get_unhacked_apcs()
// Parameters: None
// Description: Returns a list of all unhacked APCs
/proc/get_unhacked_apcs(mob/living/silicon/ai/user)
	var/list/H = list()
	for(var/obj/machinery/power/apc/A in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(A.hacker && A.hacker == user)
			continue
		H.Add(A)
	return H


// Helper procs which return lists of relevant mobs.
/proc/get_unlinked_cyborgs(mob/living/silicon/ai/A)
	if(!A || !istype(A))
		return

	var/list/L = list()
	for(var/mob/living/silicon/robot/RB in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(istype(RB, /mob/living/silicon/robot/drone))
			continue
		if(RB.connected_ai == A)
			continue
		L.Add(RB)
	return L

/proc/get_linked_cyborgs(mob/living/silicon/ai/A)
	if(!A || !istype(A))
		return
	return A.connected_robots

/proc/get_other_ais(mob/living/silicon/ai/A)
	if(!A || !istype(A))
		return

	var/list/L = list()
	for(var/mob/living/silicon/ai/AT in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(AT == A)
			continue
		L.Add(AT)
	return L


/datum/prompt/choice/malf_research_target
	title = "Select Research"
	question = "Select your next research target"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	recheck_on_open = TRUE

/datum/prompt/choice/malf_research_target/recheck_extra()
	var/mob/living/silicon/ai/user = answerer
	if(!istype(user) || QDELETED(user))
		return "gone"
	if(!isnull(answer_value))
		var/datum/malf_research_ability/picked = answer_value
		if(!istype(picked) || QDELETED(picked))
			return "gone"
	return null
