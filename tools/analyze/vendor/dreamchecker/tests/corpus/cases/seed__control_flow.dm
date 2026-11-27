/proc/early_return()
	return
	world.log << "never"
/proc/loop_false()
	for(var/i = 1, 0, i++)
		world.log << i
/proc/loop_true()
	for(var/i = 1, 1, i++)
		return
/proc/if_chain()
	if(1)
		world.log << "a"
	else if(0)
		world.log << "b"
	else
		world.log << "c"
/proc/if_false()
	if(0)
		return
/proc/const_eval()
	if(2 + 2)
		return
/proc/static_term()
	if("text")
		return
/proc/do_while_return()
	do
		return
	while(TRUE)
/proc/bad_range()
	for(var/i = 10 to 1)
		world.log << i
/proc/good_range()
	for(var/i = 1 to 10)
		world.log << i
/proc/spawn_return()
	spawn(1)
		return 5
/proc/after_break()
	for(var/i in 1 to 3)
		break
		world.log << i
/proc/after_continue()
	while(TRUE)
		continue
		world.log << "x"
/proc/after_crash()
	CRASH("x")
	world.log << "y"
/proc/switch_or(x)
	switch(x)
		if(1 || 2)
			return
/proc/switch_static()
	switch(5)
		if(5)
			return
/proc/all_branches_return(x)
	if(x)
		return 1
	else
		return 2
	world.log << "unreachable"
/proc/switch_all_return(x)
	switch(x)
		if(1)
			return 1
		else
			return 2
	world.log << "unreachable"
/proc/paren_condition(x)
	if((1))
		return
	while((x))
		return
	if (  0  )
		return
