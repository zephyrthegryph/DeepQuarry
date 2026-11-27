/proc/pure_thing()
	set SpacemanDMM_should_be_pure = TRUE
	return 1
/proc/discards()
	pure_thing()
/proc/impure(list/L, mob/M, savefile/S)
	set SpacemanDMM_should_be_pure = TRUE
	L << "x"
	M << "x"
	S << "x"
	L[1] = 2
/proc/impure_assign(datum/D)
	set SpacemanDMM_should_be_pure = TRUE
	D.vars["x"] = 1
/proc/sleeps_builtins(client/C)
	set SpacemanDMM_should_not_sleep = TRUE
	alert("x")
	shell("x")
	winexists(C, "x")
	winget(C, "x", "y")
	input("x")
	world.Export("x")
	C.SoundQuery()
	C.MeasureText("x")
/proc/allowed()
	set SpacemanDMM_allowed_to_sleep = TRUE
	sleep(1)
/proc/calls_allowed()
	set SpacemanDMM_should_not_sleep = TRUE
	allowed()
/datum/proc/sleeper()
	return
/datum/child/sleeper()
	sleep(1)
/datum/proc/calls_sleeper()
	set SpacemanDMM_should_not_sleep = TRUE
	sleeper()
/datum/proc/pure_parent()
	set SpacemanDMM_should_be_pure = TRUE
	return 1
/datum/child/pure_parent()
	world.log << "impure"
	return 2
/datum/proc/calls_pure_parent()
	set SpacemanDMM_should_be_pure = TRUE
	return pure_parent()
/proc/spawned_sleep()
	set SpacemanDMM_should_not_sleep = TRUE
	spawn(0)
		sleep(1)
		input("x")
