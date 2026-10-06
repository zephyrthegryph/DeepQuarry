/mob/observer/dead/Logout()
	..()
	after(src, 0, PROC_REF(logout_cleanup))

/mob/observer/dead/proc/logout_cleanup()
	if(!key)	//we've transferred to another mob. This ghost should be deleted.
		// ALLOW(lifecycle): a ghost whose player moved to another mob is cleaned up
		qdel(src)
		return
	if(mind && mind.assigned_role)
		return
	expire(10 MINUTES)
