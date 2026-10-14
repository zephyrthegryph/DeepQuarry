/proc/sink(x)
	return x

/proc/test()
	var/i = 0
	while(i++ < 3)
		sink(1)
	var/j = 0; sink(j)
	return 0
