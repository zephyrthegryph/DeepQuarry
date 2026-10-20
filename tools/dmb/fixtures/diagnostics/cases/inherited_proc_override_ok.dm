/datum/base/proc/act()
	return 1

/datum/base/child/act()
	return 2

/world/New()
	new /datum/base/child()
