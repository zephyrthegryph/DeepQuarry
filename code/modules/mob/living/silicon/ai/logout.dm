/mob/living/silicon/ai/Logout()
	..()
	for(var/obj/machinery/ai_status_display/O in REGISTRY_MEMBERS(REGISTRY_MACHINES)) //change status
		O.mode = 0
	src.view_core()
	return
