/datum/notice/probe
/datum/probe/proc/run(datum/notice/probe/N)
	N.value = 1
	var/list/L = N.items
	L.Add(1)
	N.value = 2 // ALLOW(read_back): deliberate same-line original annotation compatibility
