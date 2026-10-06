// NEWMALF FUNCTIONS/PROCEDURES

// Sets up malfunction-related variables, research system and such.
/mob/living/silicon/ai/proc/setup_for_malf()
	var/mob/living/silicon/ai/user = src
	// Setup Variables
	malfunctioning = 1
	rel_set(src, nameof(research), new/datum/malf_research())
	rel_set(research, nameof(research.owner), src)
	recalc_cpu()

	om_grant(src, GRANT_VERB, /datum/game_mode/malfunction/verb/ai_select_hardware, src)
	om_grant(src, GRANT_VERB, /datum/game_mode/malfunction/verb/ai_select_research, src)
	om_grant(src, GRANT_VERB, /datum/game_mode/malfunction/verb/ai_help, src)

	// And greet user with some OOC info.
	to_chat(user, "You are malfunctioning, you do not have to follow any laws.")
	to_chat(user, "Use ai-help command to view relevant information about your abilities")

// Safely remove malfunction status, fixing hacked APCs and resetting variables.
/mob/living/silicon/ai/proc/stop_malf()
	// Generic variables
	malfunctioning = 0
	after(src, 1 SECOND, PROC_REF(stop_malf_finish))

/mob/living/silicon/ai/proc/stop_malf_finish()
	var/mob/living/silicon/ai/user = src
	// Every malf verb goes: the research, its unlocked abilities and the hardware granted them.
	if(research)
		for(var/datum/ability as anything in research.unlocked_abilities)
			om_revoke_all_of(src, GRANT_VERB, ability)
		om_revoke_all_of(src, GRANT_VERB, research)
	if(hardware)
		om_revoke_all_of(src, GRANT_VERB, hardware)
	om_revoke_each(src, GRANT_VERB, list(/datum/game_mode/malfunction/verb/ai_select_hardware, /datum/game_mode/malfunction/verb/ai_select_research, /datum/game_mode/malfunction/verb/ai_help, /datum/game_mode/malfunction/verb/ai_destroy_station), src)
	rel_clear(src, nameof(research))
	// Fix hacked APCs (a pair: clearing our side clears each APC's hacker)
	rel_clear(src, nameof(hacked_apcs))
	// Let them know.
	to_chat(user, "You are no longer malfunctioning. Your abilities have been removed.")

// Called every tick. Checks if AI is malfunctioning. If yes calls Process on research datum which handles all logic.
/mob/living/silicon/ai/proc/malf_process()
	if(!malfunctioning)
		return
	if(!research)
		if(COOLDOWN_FINISHED(src, research_error_cooldown))
			COOLDOWN_START(src, research_error_cooldown, 2 MINUTES)
			log_world("## ERROR malf_process() called on AI without research datum. Report this.")
			message_admins("ERROR: malf_process() called on AI without research datum. If admin modified one of the AI's vars revert the change and don't modify variables directly, instead use ProcCall or admin panels.")
		return
	recalc_cpu()
	if(APU_power || aiRestorePowerRoutine != 0)
		research.research_tick(1)
	else
		research.research_tick(0)

// Recalculates CPU time gain and storage capacities.
/mob/living/silicon/ai/proc/recalc_cpu()
	// AI Starts with these values.
	var/cpu_gain = 0.01
	var/cpu_storage = 10

	// Off-Station APCs should not count towards CPU generation.
	for(var/obj/machinery/power/apc/A in hacked_apcs)
		if(A.z in using_map.station_levels)
			cpu_gain += 0.004
			cpu_storage += 10

	research.max_cpu = cpu_storage + override_CPUStorage
	if(hardware && istype(hardware, /datum/malf_hardware/dual_ram))
		research.max_cpu = research.max_cpu * 1.5
	research.stored_cpu = min(research.stored_cpu, research.max_cpu)

	research.cpu_increase_per_tick = cpu_gain + override_CPURate
	if(hardware && istype(hardware, /datum/malf_hardware/dual_cpu))
		research.cpu_increase_per_tick = research.cpu_increase_per_tick * 2

// Starts AI's APU generator
/mob/living/silicon/ai/proc/start_apu(shutup = 0)
	if(!hardware || !istype(hardware, /datum/malf_hardware/apu_gen))
		if(!shutup)
			to_chat(src, "You do not have an APU generator and you shouldn't have this verb. Report this.")
		return
	if(hardware_integrity() < 50)
		if(!shutup)
			to_chat(src, span_notice("Starting APU... <b>FAULT</b>(System Damaged)"))
		return
	if(!shutup)
		to_chat(src, "Starting APU... ONLINE")
	APU_power = 1

// Stops AI's APU generator
/mob/living/silicon/ai/proc/stop_apu(shutup = 0)
	if(!hardware || !istype(hardware, /datum/malf_hardware/apu_gen))
		return

	if(APU_power)
		APU_power = 0
		if(!shutup)
			to_chat(src, "Shutting down APU... DONE")

// Returns percentage of AI's remaining backup capacitor charge.
/mob/living/silicon/ai/proc/backup_capacitor()
	return backup_charge * 100 / AI_BACKUP_CAPACITY

// Returns percentage of AI's remaining hardware integrity (machine body vitality).
/mob/living/silicon/ai/proc/hardware_integrity()
	return round(vitality() * 100)

// Shows capacitor charge and hardware integrity information to the AI in Status tab.
/mob/living/silicon/ai/show_system_integrity()
	. = ""
	if(!src.stat)
		. += "Hardware integrity: [hardware_integrity()]%"
		. += "Internal capacitor: [backup_capacitor()]%"
	else
		. += "Systems nonfunctional"

// Shows AI Malfunction related information to the AI.
/mob/living/silicon/ai/show_malf_ai()
	. = ""
	if(src.is_malf())
		. += "Hacked APCs: [length(src.hacked_apcs)]"
		. += "System Status: [src.hacking ? "Busy" : "Stand-By"]"
		if(src.research)
			. += "Available CPU: [src.research.stored_cpu] TFlops"
			. += "Maximal CPU: [src.research.max_cpu] TFlops"
			. += "CPU generation rate: [src.research.cpu_increase_per_tick * 10] TFlops/s"
			. += "Current research focus: [src.research.get_focus() ? src.research.get_focus().name : "None"]"
			if(src.research.get_focus())
				. += "Research completed: [round(src.research.get_focus().invested, 0.1)]/[round(src.research.get_focus().price)]"
			if(system_override == 1)
				. += "SYSTEM OVERRIDE INITIATED"
			else if(system_override == 2)
				. += "SYSTEM OVERRIDE COMPLETED"

// Cleaner proc for creating powersupply for an AI.
/mob/living/silicon/ai/proc/create_powersupply()
	rel_set(src, nameof(psupply), new/obj/machinery/ai_powersupply(src))
