/datum/thing/child
	parent_type = /datum/thing

/datum/thing/child/no_sleep()
	..()
	spawn(1)
		deep_sleep()

/proc/global_sleeper()
	set SpacemanDMM_should_not_sleep = TRUE
	var/datum/thing/T = new
	T.no_sleep()
	T.helper_one()

/proc/undefined_caller()
	nonexistent_global()
	var/list/L = list()
	L.Add(1, 2)
	for(var/i in 1 to 3)
		continue
	while(TRUE)
		break
