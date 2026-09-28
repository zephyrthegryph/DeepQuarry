// Verb: ai_select_hardware()
// Parameters: None
// Description: Allows AI to select it's hardware module.
/datum/game_mode/malfunction/verb/ai_select_hardware()
	set category = "Hardware"
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

	om_prompt(user, user, list("kind" = "list", "message" = "Select desired hardware. You may only choose one hardware piece!: ", "title" = "Hardware Choice", "choices" = possible_choices, "requires" = PROMPT_CONSCIOUS, "data" = list("hardware" = hardware_list)), GLOBAL_PROC_REF(malf_hardware_chosen))

/proc/malf_hardware_chosen(mob/living/silicon/ai/user, mob/answerer, choice, datum/om/prompt/ask)
	var/datum/malf_hardware/C
	for (var/datum/malf_hardware/H in ask.get("hardware"))
		if(H.name == choice)
			C = H
			break
	if(!C)
		to_chat(user, "This hardware does not exist! Probably a bug in game. Please report this.")
		return
	if(!C.desc)
		log_world("## ERROR Hardware without description: [C]")
		return
	ask.put("chosen", C)
	ask.chain(list("message" = "[C.desc] - Is this what you want?", "title" = "Hardware selection", "choices" = list("Yes", "No")), GLOBAL_PROC_REF(malf_hardware_confirmed))

/proc/malf_hardware_confirmed(mob/living/silicon/ai/user, mob/answerer, confirmation, datum/om/prompt/ask)
	if(confirmation != "Yes")
		to_chat(user, "Selection cancelled. Use command again to select")
		return
	if(user.hardware)
		to_chat(user, "You have already selected your hardware.")
		return
	var/datum/malf_hardware/C = ask.get("chosen")
	C.owner_handle = om_handle(user)
	C.install()

// Verb: ai_help()
// Parameters: None
// Descriptions: Opens help file and displays it to the AI.
/datum/game_mode/malfunction/verb/ai_help()
	set category = "Hardware"
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
	set category = "Hardware"
	set name = "Select Research"
	set desc = "Allows you to select your next research target."
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, 0, 1))
		return

	var/datum/malf_research/res = user.research
	om_prompt(user, user, list("kind" = "list", "message" = "Select your next research target", "title" = "Select Research", "choices" = res.available_abilities, "requires" = PROMPT_CONSCIOUS), GLOBAL_PROC_REF(malf_research_chosen))

/proc/malf_research_chosen(mob/living/silicon/ai/user, mob/answerer, datum/malf_research_ability/tar, datum/om/prompt/ask)
	var/datum/malf_research/res = user.research
	res.focus_static = tar
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

// Proc: ability_pay()
// Parameters 2 - (user - User from which we deduct CPU from, price - Amount of CPU power to use)
// Description: Uses up certain amount of CPU power. Returns 1 on success, 0 on failure.
/proc/ability_pay(mob/living/silicon/ai/user = null, price = 0)
	if(!user)
		return 0
	if(user.APU_power)
		to_chat(user, "Low power. Unable to proceed.")
		return 0
	if(!user.research)
		to_chat(user, "GAME ERROR: No research datum detected. Please report this.")
		return 0
	if(user.research.max_cpu < price)
		to_chat(user, "Your CPU storage is not large enough to use this ability. Hack more APCs to continue.")
		return 0
	if(user.research.stored_cpu < price)
		to_chat(user, "You do not have enough CPU power stored. Please wait a moment.")
		return 0
	user.research.stored_cpu -= price
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
