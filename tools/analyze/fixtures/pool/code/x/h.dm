/proc/h()
	var/a = take(/datum/foo) // ALLOW(pool): skipped
	var/b = "a.release()"
