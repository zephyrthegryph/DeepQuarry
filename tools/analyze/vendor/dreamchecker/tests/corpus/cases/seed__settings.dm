/proc/bad_background()
	set background = 2
/mob/verb/bad_name()
	set name = 5
	set category = null
	set desc = "fine"
/mob/verb/bad_invisibility()
	set invisibility = 200
/mob/verb/good_invisibility()
	set invisibility = 50
/proc/unknown_lint()
	set SpacemanDMM_bogus_setting = 1
/proc/bad_value()
	set SpacemanDMM_should_not_sleep = 2
/proc/global_parent()
	set SpacemanDMM_should_call_parent = 1
/mob/proc/cannot_disable()
	set SpacemanDMM_should_not_override = 0
/mob/proc/twice()
	set SpacemanDMM_should_call_parent = 1
	set SpacemanDMM_should_call_parent = 1
	..()
/mob/proc/not_top()
	world.log << "x"
	set SpacemanDMM_should_call_parent = 1
/mob/proc/later()
	return
/mob/later()
	set SpacemanDMM_should_not_sleep = 1
	return
/proc/waitfor_bad()
	set waitfor = 3
/proc/waitfor_false()
	set waitfor = FALSE
	sleep(1)
/proc/nested_setting(x)
	if(x)
		set SpacemanDMM_should_be_pure = 1
