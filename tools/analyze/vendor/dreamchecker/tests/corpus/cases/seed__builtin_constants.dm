/proc/constants(atom/A)
	if(NORTH)
		return
	while(SOUTH)
		return
	if(A.dir == NORTH)
		return
	if(NORTH == SOUTH)
		return
	if(TRUE)
		return
	var/d = EAST
	world.log << d
	for(var/i = NORTH to SOUTH)
		world.log << i
	switch(A.dir)
		if(NORTH || SOUTH)
			return
	if(!NORTH)
		return
