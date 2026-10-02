/proc/sev_fx(C)
	C.severity += 1
	C.severity = 2
	C.severity == 2
	C.severity*=3
	C.severity = 4 // ALLOW(check_grep): ignored by plain grep
