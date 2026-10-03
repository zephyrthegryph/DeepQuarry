/mob/observer/dead/Logout()
	..()
	after(src, 0, PROC_REF(logout_cleanup))

/mob/observer/dead/proc/logout_cleanup()
	if(!key)	//we've transferred to another mob. This ghost should be deleted.
		qdel(src)
		return
	if(mind && mind.assigned_role)
		return
	expire(10 MINUTES)
