/proc/prior()
	var/static/x = mark("static")
	return x
var/global/late = mark("late")
/proc/reset()
	return 1
/var/global/first = mark("first")
/proc/mark(label)
	world.log << "DQ_REGISTER [label]"
	return 1
/world/New()
	world.log << "DQ_REGISTER finished"
	shutdown()
