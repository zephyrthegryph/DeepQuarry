/datum/base/proc/act()
	return 1

/datum/base/child/proc/act()
	return 2

/world/New()
	new /datum/base/child()
