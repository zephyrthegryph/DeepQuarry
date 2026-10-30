
/mob/living/silicon/ai/proc/store_core_ready(datum/act/op/A)
	if(SSticker && ticker_mode() && ticker_mode().name == "AI malfunction")
		return span_danger("You cannot use this verb in malfunction. If you need to leave, please adminhelp.")
	return null

/mob/living/silicon/ai/proc/store_core()
	// Guard against misclicks, this isn't the sort of thing we want happening accidentally
	open_request(src, /datum/prompt/yes_no, PROC_REF(store_core_confirmed), answerer = src, title = "Store Core", question = "WARNING: This will immediately empty your core and ghost you, removing your character from the round permanently (similar to cryo and robotic storage). Are you entirely sure you want to do this?", timeout = 0)

/mob/living/silicon/ai/proc/store_core_op(datum/act/op/A)
	store_core()

/mob/living/silicon/ai/proc/store_core_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	// We warned you.
	registry_join(REGISTRY_EMPTY_AI_CORES, new /obj/structure/AIcore/deactivated(loc))
	GLOB.global_announcer.autosay("[src] has been moved to intelligence storage.", "Artificial Intelligence Oversight")

	//Handle job slot/tater cleanup.
	set_respawn_timer()
	clear_client()
