/datum/system/beta
	var/list/needs = list(/datum/system/alpha)
	var/list/emits = list()
/datum/system/beta/proc/go()
	OM_EMIT(/datum/om/event/zzz)
	return system(/datum/system/alpha).ping()
