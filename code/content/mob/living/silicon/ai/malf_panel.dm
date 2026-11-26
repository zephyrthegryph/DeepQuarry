// The malfunction panel: the hardware and software commands of a malfunctioning AI in one command panel (code/library/ui/command_panel.dm).
// They were verbs granted as the AI researched them; the panel lists a command while the AI has it: the always-on hardware commands while it
// malfunctions, a hardware driver while that hardware is installed, a software command once its research is finished, and Destroy Station once
// the system override has won.

GLOBAL_LIST_INIT(malf_panel_commands, list(
	panel_command("ai_self_destruct", "Destroy Core", "Activates or deactivates self destruct sequence of your physical mainframe.", "Hardware", TYPE_PROC_REF(/mob/living/silicon/ai, malf_ai_self_destruct), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("ai_toggle_apu", "Toggle APU Generator", "Activates or deactivates your APU generator, allowing you to operate even without power.", "Hardware", TYPE_PROC_REF(/mob/living/silicon/ai, malf_ai_toggle_apu), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("ai_destroy_station", "Destroy Station", "Activates or deactivates self destruct sequence of this station. Sequence takes two minutes, and if you are shut down before timer reaches zero it will be cancelled.", "Hardware", TYPE_PROC_REF(/mob/living/silicon/ai, malf_ai_destroy_station), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("ai_select_hardware", "Select Hardware", "Allows you to select hardware piece to install", "Hardware", TYPE_PROC_REF(/mob/living/silicon/ai, malf_ai_select_hardware), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("ai_help", "Display Help", "Opens help window with overview of available hardware, software and other important information.", "Hardware", TYPE_PROC_REF(/mob/living/silicon/ai, malf_ai_help), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("ai_select_research", "Select Research", "Allows you to select your next research target.", "Hardware", TYPE_PROC_REF(/mob/living/silicon/ai, malf_ai_select_research), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("recall_shuttle", "Recall Shuttle", "25 CPU - Sends termination signal to quantum relay aborting current shuttle call.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_recall_shuttle), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("unlock_cyborg", "Unlock Cyborg", "125 CPU - Bypasses firewalls on Cyborg lock mechanism, allowing you to override lock command from robotics control console.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_unlock_cyborg), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("hack_cyborg", "Hack Cyborg", "350 CPU - Allows you to hack cyborgs which are not slaved to you, bringing them under your control.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_hack_cyborg), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("hack_ai", "Hack AI", "600 CPU - Allows you to hack other AIs, slaving them under you.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_hack_ai), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("electrical_pulse", "Electrical Pulse", "15 CPU - Sends feedback pulse through station's power grid, overloading some sensitive systems, such as lights.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_electrical_pulse), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("hack_camera", "Hack Camera", "100 CPU - Hacks existing camera, allowing you to add upgrade of your choice to it. Alternatively it lets you reactivate broken camera.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_hack_camera), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("emergency_forcefield", "Emergency Forcefield", "275 CPU - Uses station's emergency shielding system to create temporary barrier which lasts for few minutes, but won't resist gunfire.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_emergency_forcefield), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("machine_overload", "Machine Overload", "400 CPU - Causes cyclic short-circuit in machine, resulting in weak explosion after some time.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_machine_overload), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("basic_encryption_hack", "Basic Encryption Hack", "10 CPU - Basic encryption hack that allows you to overtake APCs on the station.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_basic_encryption_hack), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("advanced_encryption_hack", "Advanced Encrypthion Hack", "75 CPU - Attempts to bypass encryption on the Command Quantum Relay, giving you ability to fake legitimate messages. Has chance of failing.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_advanced_encryption_hack), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("elite_encryption_hack", "Elite Encryption Hack", "200 CPU - Allows you to hack station's ALERTCON system, changing alert level. Has high chance of failijng.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_elite_encryption_hack), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
	panel_command("system_override", "System Override", "500 CPU - Begins hacking station's primary firewall, quickly overtaking remaining APC systems. When completed grants access to station's self-destruct mechanism. Network administrators will probably notice this.", "Software", TYPE_PROC_REF(/mob/living/silicon/ai, malf_system_override), TYPE_PROC_REF(/mob/living/silicon/ai, malf_command_shown)),
))

/// The one malfunction verb: opens the malfunction panel.
/mob/living/silicon/ai/proc/malf_panel()
	set name = "Malfunction Panel"
	set desc = "Every malfunction hardware and software command in one window."
	set category = VERB_CAT_HARDWARE

	command_panel_open(src, "malf", "Malfunction Panel", GLOB.malf_panel_commands, TYPE_PROC_REF(/mob/living/silicon/ai, malf_panel_blocked))

/// Why the commands cannot be used: only while the AI malfunctions.
/mob/living/silicon/ai/proc/malf_panel_blocked()
	if(!malfunctioning)
		return "You are not malfunctioning."
	return null

/// Does this AI have the malfunction command with this id?
/mob/living/silicon/ai/proc/malf_command_shown(id)
	if(!malfunctioning)
		return FALSE
	switch(id)
		if("ai_select_hardware", "ai_select_research", "ai_help")
			return TRUE
		if("ai_destroy_station")
			return system_override == 2
		if("ai_toggle_apu")
			return istype(hardware, /datum/malf_hardware/apu_gen)
		if("ai_self_destruct")
			return istype(hardware, /datum/malf_hardware/core_bomb)
	var/ability = "/mob/living/silicon/ai/proc/malf_[id]"
	for(var/datum/malf_research_ability/unlocked as anything in research?.unlocked_abilities)
		if("[unlocked.ability]" == ability)
			return TRUE
	return FALSE
