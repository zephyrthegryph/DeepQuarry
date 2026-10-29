/proc/plain()
	return null
/proc/none()
	set SpacemanDMM_return_type = null
	return null
/proc/probe()
	plain().invoke(hidden_missing())
	none().invoke(hidden_missing())
	(new /datum()).invoke(hidden_missing())
	locate(/datum).invoke(hidden_missing())
	plain()[1].invoke(hidden_missing())
	plain().invoke().again()
