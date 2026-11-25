/datum/thing
	var/count = 0
	var/datum/thing/next

/datum/thing/proc/no_sleep()
	set SpacemanDMM_should_not_sleep = TRUE
	helper_one()
	helper_two()

/datum/thing/proc/helper_one()
	helper_two()
	deep_sleep()

/datum/thing/proc/helper_two()
	helper_one()
	count++

/datum/thing/proc/deep_sleep()
	sleep(1)

/datum/thing/proc/pure_calc()
	set SpacemanDMM_should_be_pure = TRUE
	count = 5
	return impure_helper()

/datum/thing/proc/impure_helper()
	world << "hi"
	return 1

/datum/thing/proc/takes_args(alpha, beta)
	return alpha + beta

/datum/thing/child/takes_args(alpha)
	return alpha

/datum/thing/proc/caller()
	takes_args(beta = 2)
	var/datum/thing/T = new
	T.missing_proc()
	return
	count = 3

/datum/thing/proc/must_parent()
	set SpacemanDMM_should_call_parent = TRUE

/datum/thing/child/must_parent()
	count = 1

/datum/thing/proc/secret()
	set SpacemanDMM_private_proc = TRUE

/datum/other/proc/peek(datum/thing/T)
	T.secret()
	var/x = T:count
	if(1)
		x = 2
	return x
