/mob/living/silicon/ai
	death_message = "gives one shrill beep before falling lifeless."

/// Death is decided by the AI machine plan; this is the one pass that follows it.
/mob/living/silicon/ai/on_death(gibbed)
	. = ..()
	if(deployed_shell)
		disconnect_shell("Disconnecting from remote shell due to critical system failure.")
	cancel_power_restore()
	GLOB.cameranet.updateVisibility(src, 0)

	if(src.eyeobj)
		src.eyeobj.setLoc(get_turf(src))

	remove_ai_verbs(src)

	for(var/obj/machinery/ai_status_display/O in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		O.mode = 2

	if (istype(loc, /obj/item/aicard))
		var/obj/item/aicard/card = loc
		card.update_icon()

	density = TRUE

/mob/living/silicon/ai/on_revived(reason, datum/source)
	. = ..()
	add_ai_verbs(src)
	GLOB.cameranet.updateVisibility(src, 0)
