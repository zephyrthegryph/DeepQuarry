/mob/living/silicon/decoy/on_death(gibbed)
	. = ..()
	icon_state = "ai-crash"
	spawn(10)
		explosion(loc, 3, 6, 12, 15)
	for(var/obj/machinery/ai_status_display/O in REGISTRY_MEMBERS(REGISTRY_MACHINES)) //change status
		O.mode = 2
