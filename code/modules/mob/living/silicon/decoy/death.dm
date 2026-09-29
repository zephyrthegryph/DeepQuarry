/mob/living/silicon/decoy/on_death(gibbed)
	. = ..()
	icon_state = "ai-crash"
	om_after(src, 1 SECOND, PROC_REF(crash_explode))
	for(var/obj/machinery/ai_status_display/O in REGISTRY_MEMBERS(REGISTRY_MACHINES)) //change status
		O.set_mode(2)

/// A second after the crash.
/mob/living/silicon/decoy/proc/crash_explode()
	explosion(loc, 3, 6, 12, 15)
