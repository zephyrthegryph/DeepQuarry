/datum/svc
	var/static/table = 1

/proc/sink(x)
	return x

/proc/test()
	var/datum/svc/d = new
	var/datum/svc/e = new
	sink(d.table)
	var/x = e.table
	return x
