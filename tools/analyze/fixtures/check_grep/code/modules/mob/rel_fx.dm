/proc/rel_fx(M)
	M.buckled = null
	M.pulling += 1
	M.buckled == 1
	var/x = M.buckled = 1
	M.pulledby = null // om-field-exempt
	// M.buckled = 2
	M.grabbed_by |= 3
	M.affecting = 4
	M.buckled_mobs = list() // ALLOW(check_grep): ok
