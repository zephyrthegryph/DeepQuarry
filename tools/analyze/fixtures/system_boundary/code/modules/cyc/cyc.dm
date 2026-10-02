/datum/system/c1
	var/list/needs = list(/datum/system/c2)
/datum/system/c2
	var/list/needs = list(/datum/system/c3)
/datum/system/c3
	var/list/needs = list(/datum/system/c1)
