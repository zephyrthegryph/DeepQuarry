/datum/required/missing/run()
    return 0
/datum/required/calls/run()
    return ..()
/datum/required/disabled/run()
    set SpacemanDMM_should_call_parent = FALSE
    return 0
/datum/required/own/proc/run()
    set SpacemanDMM_should_call_parent = TRUE
    return 0
