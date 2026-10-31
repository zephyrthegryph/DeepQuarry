// HARDWARE TREE
//
// These abilities are dependent on hardware, they may not be researched. They are not tiered.
// Destroy Core - Allows the AI to initiate a 15 second countdown that will destroy it's core. Use again to stop countdown.
// Toggle APU Generator - Allows the AI to toggle it's integrated APU generator.
// Destroy Station - Allows the AI to initiate station self destruct. Takes 2 minutes, gives warnings to crew. Use again to stop countdown.


/datum/game_mode/malfunction/verb/ai_self_destruct()
	set category = VERB_CAT_HARDWARE
	set name = "Destroy Core"
	set desc = "Activates or deactivates self destruct sequence of your physical mainframe."
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, 0, 1))
		return

	if(!user.hardware || !istype(user.hardware, /datum/malf_hardware/core_bomb))
		return

	if(user.bombing_core)
		to_chat(user, "***** CORE SELF-DESTRUCT SEQUENCE ABORTED *****")
		user.bombing_core = 0
		return

	open_request(user, /datum/prompt/yes_no, TYPE_PROC_REF(/mob/living/silicon/ai, malf_core_bomb_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able_overridden), title = "Core self-destruct", question = "Really destroy core?", yes_text = "YES", no_text = "NO", ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/silicon/ai/proc/malf_core_bomb_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/living/silicon/ai/user = src
	if(user.bombing_core)
		return

	user.bombing_core = 1

	to_chat(user, "***** CORE SELF-DESTRUCT SEQUENCE ACTIVATED *****")
	to_chat(user, "Use command again to cancel self-destruct. Destroying in 15 seconds.")
	after(user, 1 SECOND, GLOBAL_PROC_REF(malf_core_bomb_tick), with = list(user, 14))

/// The core bomb's countdown, once a second; it goes off at zero unless cancelled.
/proc/malf_core_bomb_tick(mob/living/silicon/ai/user, timer)
	if(!user.bombing_core)
		return
	to_chat(user, "** [timer] **")
	if(timer > 0)
		after(user, 1 SECOND, GLOBAL_PROC_REF(malf_core_bomb_tick), with = list(user, timer - 1))
		return
	explosion(user.loc, 3,6,12,24)
	spent(user)


/datum/game_mode/malfunction/verb/ai_toggle_apu()
	set category = VERB_CAT_HARDWARE
	set name = "Toggle APU Generator"
	set desc = "Activates or deactivates your APU generator, allowing you to operate even without power."
	var/mob/living/silicon/ai/user = usr

	if(!ability_prechecks(user, 0, 1))
		return

	if(!user.hardware || !istype(user.hardware, /datum/malf_hardware/apu_gen))
		return

	if(user.APU_power)
		user.stop_apu()
	else
		user.start_apu()


/datum/game_mode/malfunction/verb/ai_destroy_station()
	set category = VERB_CAT_HARDWARE
	set name = "Destroy Station"
	set desc = "Activates or deactivates self destruct sequence of this station. Sequence takes two minutes, and if you are shut down before timer reaches zero it will be cancelled."
	var/mob/living/silicon/ai/user = usr


	if(!ability_prechecks(user, 0, 0))
		return

	if(user.system_override != 2)
		to_chat(user, "You do not have access to self-destruct system.")
		return

	if(user.bombing_station)
		user.bombing_station = 0
		return

	open_request(user, /datum/prompt/yes_no, TYPE_PROC_REF(/mob/living/silicon/ai, malf_station_bomb_confirmed), answerer = user, valid = TYPE_PROC_REF(/mob/living/silicon/ai, malf_able), title = "Station self-destruct", question = "Really destroy station?", yes_text = "YES", no_text = "NO", ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/silicon/ai/proc/malf_station_bomb_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/living/silicon/ai/user = src
	if(user.bombing_station)
		return
	var/obj/item/radio/radio = new/obj/item/radio()
	to_chat(user, "***** STATION SELF-DESTRUCT SEQUENCE INITIATED *****")
	to_chat(user, "Self-destructing in 2 minutes. Use this command again to abort.")
	user.bombing_station = 1
	set_security_level("delta")
	radio.autosay("Self destruct sequence has been activated. Self-destructing in 120 seconds.", "Self-Destruct Control")

	after(user, 1 SECOND, GLOBAL_PROC_REF(malf_station_bomb_tick), with = list(user, radio, 120))

/// The station self-destruct countdown, once a second.
/proc/malf_station_bomb_tick(mob/living/silicon/ai/user, obj/item/radio/radio, timer)
	if(!user.bombing_station || user.stat == DEAD)
		radio.autosay("Self destruct sequence has been cancelled.", "Self-Destruct Control")
		return
	if(timer in list(2, 3, 4, 5, 10, 30, 60, 90)) // Announcement times. "1" is not intentionally included!
		radio.autosay("Self destruct in [timer] seconds.", "Self-Destruct Control")
	if(timer == 1)
		radio.autosay("Self destructing now. Have a nice day.", "Self-Destruct Control")
	if(timer > 1)
		after(user, 1 SECOND, GLOBAL_PROC_REF(malf_station_bomb_tick), with = list(user, radio, timer - 1))
		return

	if(SSticker)
		var/datum/cinematic/malf/malf_type = /datum/cinematic/malf
		play_cinematic(malf_type)
		// The station dies at the blast, once the intro has played (it slept through it before S10b).
		after(null, initial(malf_type.intro_time), GLOBAL_PROC_REF(malf_station_blast))

/// The doomsday blast, after its cinematic's intro: kills the station.
/proc/malf_station_blast()
	// FIXME: Probably a better way
	for(var/mob/living/M in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		switch(M.z)
			if(0)	//inside a crate or something
				var/turf/T = get_turf(M)
				if(T && (T.z in using_map.station_levels))				//we don't use M.death(0) because it calls a for(/mob) loop and
					M.set_stat(DEAD)
			if(1)	//on a z-level 1 turf.
				M.set_stat(DEAD)

	if(ticker_mode())
		ticker_mode().station_was_nuked = 1
