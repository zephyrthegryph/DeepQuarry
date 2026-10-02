/proc/pipe_fx(P, E, M)
	P.asleep = TRUE
	E.parked |= 2
	M.bits[3] &= 1
	var/x = P.idle_frames = 3
	if(P.asleep == 1)
	P.parked_index += 1
	P.asleep = FALSE // ALLOW(check_grep): ok
