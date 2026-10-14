/proc/known(label)
	world.log << "DQ_REGISTER [label]"
	return 1
/datum/custom/var/static/eager = future("future_field")
/datum/custom/proc/holder()
	var/static/deferred = known("known_static")
	return deferred
var/global/late = future("bare_future")
/var/global/root = known("root")
/proc/future(label)
	world.log << "DQ_REGISTER [label]"
	return 1
/world/New()
	world.log << "DQ_REGISTER finished"
	shutdown()
