/proc/e()
	var/a = take(/datum/foo)
	a.release() // ALLOW(pool): hidden release
