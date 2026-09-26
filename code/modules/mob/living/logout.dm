/mob/living/Logout()
	..()
	on_client_changed("logout")
	if (mind)
		//Per BYOND docs key remains set if the player DCs, becomes null if switching bodies.
		if(!key)	//key and mind have become seperated.
			mind.active = 0	//This is to stop say, a mind.transfer_to call on a corpse causing a ghost to re-enter its body.

	var/datum/component/character_setup/cs = GetComponent(/datum/component/character_setup)
	if(cs)
		qdel(cs)

	var/datum/component/vore_panel/vp = GetComponent(/datum/component/vore_panel)
	if(vp)
		qdel(vp)

	om_after(src, 15 SECONDS, PROC_REF(logout_wake_ai)) //15 seconds to get back into the mob before it goes wild

/mob/living/proc/logout_wake_ai()
	if(!client && ai_brain)
		ai_brain.go_wake()
