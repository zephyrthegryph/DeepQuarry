/datum/base/proc/act()
	return 1

/datum/base/mid/act()
	return 2

/datum/base/mid/leaf/proc/act()
	return 3

/world/New()
	new /datum/base/mid/leaf()
