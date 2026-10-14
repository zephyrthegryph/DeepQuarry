/datum/svc
	var/static/datum/svc/table = null
	var/other = 1

/proc/sink(x)
	return x

/proc/test()
	var/datum/svc/a = new
	var/datum/svc/b = new
	var/datum/svc/c = new
	sink(a.table.other)
	sink(b?.table)
	return c.other
