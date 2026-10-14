/proc/test(cond)
	var/a = 1
	var/b = 2
	var/c = 3
	c++
	var/d = list(1,
2)
	return cond ? a : b + d[1]
