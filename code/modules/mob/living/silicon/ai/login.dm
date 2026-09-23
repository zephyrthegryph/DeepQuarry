/mob/living/silicon/ai/Login()	//ThisIsDumb(TM) TODO: tidy this up °_° ~Carn
	..()
	for(var/obj/effect/rune/rune in REGISTRY_MEMBERS(REGISTRY_RUNES))
		client.images += rune.blood_image
	if(stat != DEAD)
		for(var/obj/machinery/ai_status_display/O in REGISTRY_MEMBERS(REGISTRY_MACHINES)) //change status
			O.mode = 1
			O.emotion = "Neutral"
	if(multicam_on)
		end_multicam()
	src.view_core()
	return
